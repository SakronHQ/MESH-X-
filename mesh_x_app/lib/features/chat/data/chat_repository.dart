import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/ble_constants.dart';
import '../../../core/security/crypto_service.dart';
import '../../../core/security/preferences_key_storage.dart';
import '../../../data/database/app_database.dart';
import '../../device/data/ble_repository.dart';
import '../../mesh/domain/mesh_node_model.dart';
import '../domain/conversation_model.dart';
import '../domain/message_model.dart';

class ChatRepository {
  final BleRepository _bleRepository;
  final CryptoService _cryptoService;
  final _uuid = const Uuid();
  StreamSubscription<List<int>>? _bleEventSubscription;

  final _conversationsStreamController =
      StreamController<List<ConversationModel>>.broadcast();
  Stream<List<ConversationModel>> get conversationsStream =>
      _conversationsStreamController.stream;

  final _messagesStreamController =
      StreamController<String>.broadcast(); // Emits conversationId on update
  Stream<String> get messagesUpdateStream => _messagesStreamController.stream;

  final _nodesStreamController =
      StreamController<List<MeshNodeModel>>.broadcast();
  Stream<List<MeshNodeModel>> get nodesStream => _nodesStreamController.stream;

  ChatRepository(
    this._bleRepository, [
    CryptoService? cryptoService,
  ]) : _cryptoService =
            cryptoService ?? CryptoService(SharedPreferencesKeyStorage()) {
    _initEventListener();
  }

  void _initEventListener() {
    _bleEventSubscription = _bleRepository.eventStream.listen((rawFrame) {
      _handleBleEvent(rawFrame);
    });
  }

  CryptoService get cryptoService => _cryptoService;

  Future<List<ConversationModel>> getConversations() async {
    final db = await AppDatabase.instance;
    final maps = await db.query(
      'conversations',
      orderBy: 'is_pinned DESC, updated_at DESC',
    );
    return maps.map((m) => ConversationModel.fromMap(m)).toList();
  }

  Future<List<MessageModel>> getMessages(String conversationId) async {
    final db = await AppDatabase.instance;
    final maps = await db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at ASC',
    );
    return maps.map((m) => MessageModel.fromMap(m)).toList();
  }

  Future<List<MeshNodeModel>> getDiscoveredNodes() async {
    final db = await AppDatabase.instance;
    final maps = await db.query(
      'nodes',
      orderBy: 'last_seen_at DESC',
    );
    return maps.map((m) => MeshNodeModel.fromMap(m)).toList();
  }

  Future<void> setPeerPublicKey(int nodeId, String pubKeyHex,
      {bool isVerified = true}) async {
    final db = await AppDatabase.instance;
    await db.update(
      'nodes',
      {
        'public_key': pubKeyHex,
        'is_verified': isVerified ? 1 : 0,
      },
      where: 'node_id = ?',
      whereArgs: [nodeId],
    );
    final nodes = await getDiscoveredNodes();
    _nodesStreamController.add(nodes);
  }

  Future<String?> getPeerPublicKey(int nodeId) async {
    final db = await AppDatabase.instance;
    final res = await db.query(
      'nodes',
      columns: ['public_key'],
      where: 'node_id = ?',
      whereArgs: [nodeId],
    );
    if (res.isNotEmpty) {
      return res.first['public_key'] as String?;
    }
    return null;
  }

  Future<ConversationModel> ensureConversationForNode(int nodeId) async {
    final db = await AppDatabase.instance;
    final convId =
        '0x${nodeId.toRadixString(16).padLeft(8, '0').toUpperCase()}';
    final existing = await db.query(
      'conversations',
      where: 'id = ?',
      whereArgs: [convId],
    );

    if (existing.isEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final conv = ConversationModel(
        id: convId,
        title: 'Node $convId',
        peerNodeId: nodeId,
        lastMessageText: 'Direct channel opened.',
        lastMessageTimestamp: now,
        unreadCount: 0,
        isPinned: false,
        createdAt: now,
        updatedAt: now,
      );
      await db.insert('conversations', conv.toMap());
      final convs = await getConversations();
      _conversationsStreamController.add(convs);
      return conv;
    } else {
      return ConversationModel.fromMap(existing.first);
    }
  }

  Future<MessageModel> sendMessage({
    required String conversationId,
    required int recipientNodeId,
    required String textContent,
    required int localNodeId,
  }) async {
    final db = await AppDatabase.instance;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final messageId = _uuid.v4();
    final packetId = Random().nextInt(0x7FFFFFFF); // 31-bit positive int

    bool isEncrypted = false;
    Uint8List wirePayload;
    int flags = 0x01; // Default: Requires ACK flag

    if (recipientNodeId != 0xFFFFFFFF) {
      final peerKey = await getPeerPublicKey(recipientNodeId);
      if (peerKey != null && peerKey.length == 64) {
        try {
          wirePayload = await _cryptoService.encryptPayload(
            plaintext: textContent,
            peerPublicKeyHex: peerKey,
          );
          flags = 0x03; // REQ_ACK (0x01) | FLAG_ENCRYPTED (0x02)
          isEncrypted = true;
        } catch (_) {
          wirePayload = Uint8List.fromList(utf8.encode(textContent));
        }
      } else {
        wirePayload = Uint8List.fromList(utf8.encode(textContent));
      }
    } else {
      flags = 0x00; // Broadcast is cleartext
      wirePayload = Uint8List.fromList(utf8.encode(textContent));
    }

    final message = MessageModel(
      id: messageId,
      packetId: packetId,
      conversationId: conversationId,
      senderNodeId: localNodeId,
      recipientNodeId: recipientNodeId,
      textContent: textContent,
      deliveryStatus: MessageDeliveryStatus.queued,
      isIncoming: false,
      isEncrypted: isEncrypted,
      createdAt: now,
    );

    // Insert message into SQLite
    await db.insert('messages', message.toMap());

    // Update conversation metadata
    await db.update(
      'conversations',
      {
        'last_message_text': textContent,
        'last_message_timestamp': now,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [conversationId],
    );

    _notifyUpdates(conversationId);

    // Package payload for BLE command: [PACKET_ID: 4B][DEST_NODE: 4B][FLAGS: 1B][DATA]
    final payload = Uint8List(4 + 4 + 1 + wirePayload.length);
    final bd = ByteData.sublistView(payload);
    bd.setUint32(0, packetId, Endian.little);
    bd.setUint32(4, recipientNodeId, Endian.little);
    bd.setUint8(8, flags);
    payload.setRange(9, 9 + wirePayload.length, wirePayload);

    // Transmit over BLE Command characteristic
    await _bleRepository.sendCommand(BleConstants.cmdSubmitMessage, payload);

    return message;
  }

  Future<void> retryMessage(String messageId) async {
    final db = await AppDatabase.instance;
    final maps =
        await db.query('messages', where: 'id = ?', whereArgs: [messageId]);
    if (maps.isEmpty) return;

    final msg = MessageModel.fromMap(maps.first);
    final updatedRetry = msg.retryCount + 1;

    // Re-submit to BLE with encryption if peer key exists
    bool isEncrypted = false;
    Uint8List wirePayload;
    int flags = 0x01;

    if (msg.recipientNodeId != 0xFFFFFFFF) {
      final peerKey = await getPeerPublicKey(msg.recipientNodeId);
      if (peerKey != null && peerKey.length == 64) {
        try {
          wirePayload = await _cryptoService.encryptPayload(
            plaintext: msg.textContent,
            peerPublicKeyHex: peerKey,
          );
          flags = 0x03;
          isEncrypted = true;
        } catch (_) {
          wirePayload = Uint8List.fromList(utf8.encode(msg.textContent));
        }
      } else {
        wirePayload = Uint8List.fromList(utf8.encode(msg.textContent));
      }
    } else {
      flags = 0x00;
      wirePayload = Uint8List.fromList(utf8.encode(msg.textContent));
    }

    await db.update(
      'messages',
      {
        'delivery_status': MessageDeliveryStatus.queued.toDbString(),
        'retry_count': updatedRetry,
        'is_encrypted': isEncrypted ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );

    _notifyUpdates(msg.conversationId);

    final payload = Uint8List(4 + 4 + 1 + wirePayload.length);
    final bd = ByteData.sublistView(payload);
    bd.setUint32(0, msg.packetId, Endian.little);
    bd.setUint32(4, msg.recipientNodeId, Endian.little);
    bd.setUint8(8, flags);
    payload.setRange(9, 9 + wirePayload.length, wirePayload);

    await _bleRepository.sendCommand(BleConstants.cmdSubmitMessage, payload);
  }

  Future<void> _handleBleEvent(List<int> rawFrame) async {
    if (rawFrame.length < 12) return;
    final bytes = Uint8List.fromList(rawFrame);
    final eventType = bytes[3];
    final payload = bytes.sublist(10, bytes.length - 2);

    final db = await AppDatabase.instance;

    // 1. Inbound Received LoRa Message: EVT_RX_MESSAGE (0x80)
    // Payload: [SRC_NODE: 4B][RSSI: 1B (int8)][SNR: 1B (int8)][FLAGS: 1B][DATA]
    if (eventType == BleConstants.evtRxMessage && payload.length >= 7) {
      final bd = ByteData.sublistView(payload);
      final srcNode = bd.getUint32(0, Endian.little);
      final rssi = bd.getInt8(4);
      final snr = bd.getInt8(5).toDouble();
      final flags = bd.getUint8(6);
      final rawMsg = payload.sublist(7);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final isEncrypted = (flags & 0x02) != 0;

      String text;
      if (isEncrypted) {
        final peerKey = await getPeerPublicKey(srcNode);
        if (peerKey != null && peerKey.length == 64) {
          try {
            text = await _cryptoService.decryptPayload(
              wireBytes: rawMsg,
              peerPublicKeyHex: peerKey,
            );
          } catch (_) {
            text = '🔒 [Decryption failed / MAC verification mismatch]';
          }
        } else {
          text = '🔒 [Encrypted message - Contact key not paired]';
        }
      } else {
        text = utf8.decode(rawMsg);
      }

      final convId =
          '0x${srcNode.toRadixString(16).padLeft(8, '0').toUpperCase()}';

      // Ensure conversation exists
      final existingConvs =
          await db.query('conversations', where: 'id = ?', whereArgs: [convId]);
      if (existingConvs.isEmpty) {
        await db.insert('conversations', {
          'id': convId,
          'title': 'Node $convId',
          'peer_node_id': srcNode,
          'last_message_text': text,
          'last_message_timestamp': now,
          'unread_count': 1,
          'is_pinned': 0,
          'created_at': now,
          'updated_at': now,
        });
      } else {
        await db.rawUpdate('''
          UPDATE conversations 
          SET last_message_text = ?, last_message_timestamp = ?, unread_count = unread_count + 1, updated_at = ?
          WHERE id = ?
        ''', [text, now, now, convId]);
      }

      // Insert incoming message
      final msgId = _uuid.v4();
      final incomingMsg = MessageModel(
        id: msgId,
        packetId: 0,
        conversationId: convId,
        senderNodeId: srcNode,
        recipientNodeId: 0,
        textContent: text,
        deliveryStatus: MessageDeliveryStatus.delivered,
        isIncoming: true,
        isEncrypted: isEncrypted,
        rssi: rssi,
        snr: snr,
        createdAt: now,
        deliveredAt: now,
      );
      await db.insert('messages', incomingMsg.toMap());

      _notifyUpdates(convId);
    }

    // 2. Transmit Status: EVT_TX_STATUS (0x81)
    // Payload: [SEQ: 1B][STATUS: 1B]
    else if (eventType == BleConstants.evtTxStatus && payload.length >= 2) {
      final statusByte = payload[1];
      final newStatus = statusByte == 0x02
          ? MessageDeliveryStatus.transmitted
          : (statusByte == 0x03
              ? MessageDeliveryStatus.failed
              : MessageDeliveryStatus.queued);

      // Update most recent queued message
      final latest = await db.query(
        'messages',
        where: 'delivery_status = ?',
        whereArgs: [MessageDeliveryStatus.queued.toDbString()],
        orderBy: 'created_at DESC',
        limit: 1,
      );

      if (latest.isNotEmpty) {
        final msgId = latest.first['id'] as String;
        final convId = latest.first['conversation_id'] as String;
        await db.update(
          'messages',
          {'delivery_status': newStatus.toDbString()},
          where: 'id = ?',
          whereArgs: [msgId],
        );
        _notifyUpdates(convId);
      }
    }

    // 3. Remote Delivery ACK: EVT_DELIVERY_ACK (0x82)
    // Payload: [PACKET_ID: 4B]
    else if (eventType == BleConstants.evtDeliveryAck && payload.length >= 4) {
      final bd = ByteData.sublistView(payload);
      final packetId = bd.getUint32(0, Endian.little);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final matched = await db
          .query('messages', where: 'packet_id = ?', whereArgs: [packetId]);
      if (matched.isNotEmpty) {
        final convId = matched.first['conversation_id'] as String;
        await db.update(
          'messages',
          {
            'delivery_status': MessageDeliveryStatus.delivered.toDbString(),
            'delivered_at': now,
          },
          where: 'packet_id = ?',
          whereArgs: [packetId],
        );
        _notifyUpdates(convId);
      }
    }

    // 4. Mesh Node Discovered: EVT_NODE_DISCOVERED (0x84)
    // Payload: [NODE_ID: 4B][HOPS: 1B][RSSI: 1B (int8)][SNR: 1B (int8)]
    else if (eventType == BleConstants.evtNodeDiscovered &&
        payload.length >= 7) {
      final bd = ByteData.sublistView(payload);
      final nodeId = bd.getUint32(0, Endian.little);
      final hops = bd.getUint8(4);
      final rssi = bd.getInt8(5);
      final snr = bd.getInt8(6).toDouble();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Preserve existing public_key and is_verified if already set
      final existingNode = await db.query('nodes', where: 'node_id = ?', whereArgs: [nodeId]);
      String? pubKey;
      int isVerified = 0;
      if (existingNode.isNotEmpty) {
        pubKey = existingNode.first['public_key'] as String?;
        isVerified = (existingNode.first['is_verified'] as int?) ?? 0;
      }

      await db.insert(
        'nodes',
        {
          'node_id': nodeId,
          'alias':
              'Node 0x${nodeId.toRadixString(16).padLeft(8, '0').toUpperCase()}',
          'hop_distance': hops,
          'last_rssi': rssi,
          'last_snr': snr,
          'last_seen_at': now,
          'public_key': pubKey,
          'is_verified': isVerified,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final nodes = await getDiscoveredNodes();
      _nodesStreamController.add(nodes);
    }
  }

  void _notifyUpdates(String conversationId) async {
    _messagesStreamController.add(conversationId);
    final convs = await getConversations();
    _conversationsStreamController.add(convs);
  }

  void dispose() {
    _bleEventSubscription?.cancel();
    _conversationsStreamController.close();
    _messagesStreamController.close();
    _nodesStreamController.close();
  }
}
