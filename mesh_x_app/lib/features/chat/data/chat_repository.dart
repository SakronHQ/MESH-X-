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
import '../../sos/domain/sos_alert_model.dart';
import '../domain/conversation_model.dart';
import '../domain/message_model.dart';

class ChatRepository {
  final BleRepository _bleRepository;
  final CryptoService _cryptoService;
  final _uuid = const Uuid();
  StreamSubscription<List<int>>? _bleEventSubscription;
  StreamSubscription<bool>? _bleConnectionSubscription;
  Future<void> _eventQueue = Future.value();
  int _localNodeId = 0;

  final List<String> _recentPacketOrder = [];
  final Set<String> _recentPacketKeys = {};

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

  final _sosAlertStreamController =
      StreamController<SosAlertModel>.broadcast();
  Stream<SosAlertModel> get sosAlertStream => _sosAlertStreamController.stream;

  // In-memory buffer for assembling incoming multi-chunk micro images
  final Map<String, Map<int, String>> _incomingImageBuffers = {};
  final Map<String, int> _incomingImageTotals = {};

  ChatRepository(
    this._bleRepository, [
    CryptoService? cryptoService,
  ]) : _cryptoService =
            cryptoService ?? CryptoService(SharedPreferencesKeyStorage()) {
    _initEventListener();
  }

  void _initEventListener() {
    _bleEventSubscription = _bleRepository.eventStream.listen((rawFrame) {
      _eventQueue = _eventQueue
          .then((_) => _handleBleEvent(rawFrame))
          .catchError((_) {});
    });
    _bleConnectionSubscription = _bleRepository.connectionStream.listen((connected) {
      if (connected) {
        flushQueuedMessages();
      }
    });
  }

  Future<void> flushQueuedMessages() async {
    if (!_bleRepository.isReady) return;
    final db = await AppDatabase.instance;
    final queued = await db.query(
      'messages',
      where: 'is_incoming = 0 AND delivery_status = ?',
      whereArgs: [MessageDeliveryStatus.queued.toDbString()],
      orderBy: 'created_at ASC',
      limit: 20,
    );
    for (final row in queued) {
      final msg = MessageModel.fromMap(row);
      if (msg.textContent.startsWith('[IMAGE:') ||
          msg.textContent.startsWith('🚨 [SOS DISTRESS]')) {
        continue;
      }
      await retryMessage(msg.id);
      await Future.delayed(const Duration(milliseconds: 350));
    }
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
    if (localNodeId != 0) _localNodeId = localNodeId;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final messageId = _uuid.v4();
    final packetId = Random().nextInt(0x7FFFFFFE) + 1; // Non-zero 31-bit int

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
      flags = BleConstants.flagBroadcast; // 0x04: Broadcast is cleartext flood
      wirePayload = Uint8List.fromList(utf8.encode(textContent));
    }

    final exceedsRfLimit = wirePayload.length > 235;
    var initialStatus =
        exceedsRfLimit ? MessageDeliveryStatus.failed : MessageDeliveryStatus.queued;

    var message = MessageModel(
      id: messageId,
      packetId: packetId,
      conversationId: conversationId,
      senderNodeId: localNodeId,
      recipientNodeId: recipientNodeId,
      textContent: textContent,
      deliveryStatus: initialStatus,
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

    if (exceedsRfLimit) {
      return message;
    }

    // Package payload for BLE command: [PACKET_ID: 4B][DEST_NODE: 4B][FLAGS: 1B][DATA]
    final payload = Uint8List(4 + 4 + 1 + wirePayload.length);
    final bd = ByteData.sublistView(payload);
    bd.setUint32(0, packetId, Endian.little);
    bd.setUint32(4, recipientNodeId, Endian.little);
    bd.setUint8(8, flags);
    payload.setRange(9, 9 + wirePayload.length, wirePayload);

    // Transmit over BLE Command characteristic
    final sent = await _bleRepository.sendCommand(BleConstants.cmdSubmitMessage, payload);
    if (!sent && _bleRepository.isReady) {
      message = message.copyWith(deliveryStatus: MessageDeliveryStatus.failed);
      await db.update(
        'messages',
        {'delivery_status': MessageDeliveryStatus.failed.toDbString()},
        where: 'id = ?',
        whereArgs: [messageId],
      );
      _notifyUpdates(conversationId);
    }

    return message;
  }

  /// Compresses and sends a micro-image as multi-packet LoRa chunks
  Future<void> sendImage({
    required String conversationId,
    required int recipientNodeId,
    required Uint8List imageBytes,
    required int localNodeId,
    void Function(int current, int total)? onProgress,
  }) async {
    if (!_bleRepository.isReady) {
      throw StateError('Hardware node is offline. Connect via BLE to send photos.');
    }
    if (localNodeId != 0) _localNodeId = localNodeId;

    final db = await AppDatabase.instance;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final messageId = _uuid.v4();
    final base64Data = base64Encode(imageBytes);

    // Save full image locally in SQLite
    final localMsg = MessageModel(
      id: messageId,
      packetId: Random().nextInt(0x7FFFFFFE) + 1,
      conversationId: conversationId,
      senderNodeId: localNodeId,
      recipientNodeId: recipientNodeId,
      textContent: '[IMAGE:$base64Data]',
      deliveryStatus: MessageDeliveryStatus.transmitted,
      isIncoming: false,
      isEncrypted: false,
      createdAt: now,
    );
    await db.insert('messages', localMsg.toMap());

    await db.update(
      'conversations',
      {
        'last_message_text': '📷 Photo',
        'last_message_timestamp': now,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [conversationId],
    );
    _notifyUpdates(conversationId);

    // Chunk base64 into safe ~140 character RF packets
    const chunkSize = 140;
    final totalChunks = (base64Data.length / chunkSize).ceil();
    final imageId = Random().nextInt(0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
    final isBroadcast = recipientNodeId == 0xFFFFFFFF;
    final flags = isBroadcast ? BleConstants.flagBroadcast : 0x00;

    for (int i = 0; i < totalChunks; i++) {
      final start = i * chunkSize;
      final end = (start + chunkSize > base64Data.length) ? base64Data.length : start + chunkSize;
      final chunkSlice = base64Data.substring(start, end);
      final chunkText =
          'IMG:$imageId:${i.toRadixString(16).padLeft(2, '0')}:${totalChunks.toRadixString(16).padLeft(2, '0')}:$chunkSlice';

      final wirePayload = Uint8List.fromList(utf8.encode(chunkText));
      final packetId = Random().nextInt(0x7FFFFFFE) + 1;

      final payload = Uint8List(4 + 4 + 1 + wirePayload.length);
      final bd = ByteData.sublistView(payload);
      bd.setUint32(0, packetId, Endian.little);
      bd.setUint32(4, recipientNodeId, Endian.little);
      bd.setUint8(8, flags);
      payload.setRange(9, 9 + wirePayload.length, wirePayload);

      var ok = await _bleRepository.sendCommand(BleConstants.cmdSubmitMessage, payload);
      if (!ok) {
        await Future.delayed(const Duration(milliseconds: 250));
        ok = await _bleRepository.sendCommand(BleConstants.cmdSubmitMessage, payload);
      }
      if (!ok) {
        throw StateError('Lost BLE link while transmitting chunk ${i + 1}/$totalChunks');
      }
      onProgress?.call(i + 1, totalChunks);

      // Pacing aligned with LoRa SF9 airtime (~500ms) so BLE/TX queue never overflows
      if (i < totalChunks - 1) {
        await Future.delayed(const Duration(milliseconds: 480));
      }
    }
  }

  String? _reassembleImageChunk({
    required int senderNodeId,
    required String imageId,
    required int chunkIdx,
    required int totalChunks,
    required String chunkData,
  }) {
    final key = '$senderNodeId-$imageId';
    if (!_incomingImageBuffers.containsKey(key) && _incomingImageBuffers.length >= 8) {
      final oldestKey = _incomingImageBuffers.keys.first;
      _incomingImageBuffers.remove(oldestKey);
      _incomingImageTotals.remove(oldestKey);
    }
    final buffer = _incomingImageBuffers.putIfAbsent(key, () => {});
    _incomingImageTotals[key] = totalChunks;
    buffer[chunkIdx] = chunkData;

    if (buffer.length == totalChunks) {
      final sortedChunks = List.generate(totalChunks, (i) => buffer[i] ?? '');
      if (sortedChunks.any((c) => c.isEmpty)) return null;

      final fullBase64 = sortedChunks.join();
      _incomingImageBuffers.remove(key);
      _incomingImageTotals.remove(key);
      return fullBase64;
    }
    return null;
  }

  Future<void> submitSos({
    required String distressMessage,
    double? latitude,
    double? longitude,
    required int localNodeId,
  }) async {
    if (localNodeId != 0) _localNodeId = localNodeId;
    final db = await AppDatabase.instance;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final packetId = Random().nextInt(0x7FFFFFFE) + 1;

    // Wire format: [PACKET_ID: 4B][LAT_E7: 4B][LON_E7: 4B][TEXT]
    final textBytes = Uint8List.fromList(utf8.encode(distressMessage));
    final payload = Uint8List(4 + 4 + 4 + textBytes.length);
    final bd = ByteData.sublistView(payload);
    bd.setUint32(0, packetId, Endian.little);
    final latE7 = latitude != null ? (latitude * 10000000).round() : 0;
    final lonE7 = longitude != null ? (longitude * 10000000).round() : 0;
    bd.setInt32(4, latE7, Endian.little);
    bd.setInt32(8, lonE7, Endian.little);
    payload.setRange(12, 12 + textBytes.length, textBytes);

    // Send emergency command to ESP32 BLE and verify link
    final sent = await _bleRepository.sendCommand(BleConstants.cmdSubmitSos, payload);
    if (!sent) {
      throw StateError('Hardware node is offline or BLE write failed.');
    }

    // Format local SOS alert message
    final locationTag = (latitude != null &&
            longitude != null &&
            (latitude != 0.0 || longitude != 0.0))
        ? ' [GPS: ${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}]'
        : '';
    final formattedContent = '🚨 [SOS DISTRESS] $distressMessage$locationTag';

    final msgId = _uuid.v4();
    final message = MessageModel(
      id: msgId,
      packetId: packetId,
      conversationId: 'broadcast',
      senderNodeId: localNodeId,
      recipientNodeId: 0xFFFFFFFF,
      textContent: formattedContent,
      deliveryStatus: MessageDeliveryStatus.queued,
      isIncoming: false,
      isEncrypted: false,
      createdAt: now,
    );

    await db.insert('messages', message.toMap());
    await db.rawUpdate('''
      UPDATE conversations 
      SET last_message_text = ?, last_message_timestamp = ?, updated_at = ?
      WHERE id = ?
    ''', [formattedContent, now, now, 'broadcast']);

    _notifyUpdates('broadcast');

    final localAlert = SosAlertModel(
      packetId: packetId,
      senderNodeId: localNodeId,
      latitude: latitude,
      longitude: longitude,
      distressMessage: distressMessage,
      timestamp: now,
    );
    _sosAlertStreamController.add(localAlert);
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
      flags = BleConstants.flagBroadcast;
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

    final sent = await _bleRepository.sendCommand(BleConstants.cmdSubmitMessage, payload);
    if (!sent && _bleRepository.isReady) {
      await db.update(
        'messages',
        {'delivery_status': MessageDeliveryStatus.failed.toDbString()},
        where: 'id = ?',
        whereArgs: [messageId],
      );
      _notifyUpdates(msg.conversationId);
    }
  }

  bool _markPacketSeenInMemory(int srcNode, int packetId) {
    final key = '$srcNode-$packetId';
    if (_recentPacketKeys.contains(key)) {
      return true;
    }
    _recentPacketKeys.add(key);
    _recentPacketOrder.add(key);
    if (_recentPacketOrder.length > 256) {
      final oldest = _recentPacketOrder.removeAt(0);
      _recentPacketKeys.remove(oldest);
    }
    return false;
  }

  Future<void> _handleBleEvent(List<int> rawFrame) async {
    if (rawFrame.length < 12) return;
    final bytes = Uint8List.fromList(rawFrame);
    final eventType = bytes[3];
    final payload = bytes.sublist(10, bytes.length - 2);

    final db = await AppDatabase.instance;

    // 1. Inbound Received LoRa Message: EVT_RX_MESSAGE (0x80)
    // Payload v1: [SRC_NODE: 4B][RSSI: 1B][SNR: 1B][FLAGS: 1B][DATA] (>= 7 B)
    // Payload v2: [SRC_NODE: 4B][PACKET_ID: 4B][RSSI: 1B][SNR: 1B][FLAGS: 1B][DATA] (>= 11 B)
    if (eventType == BleConstants.evtRxMessage && payload.length >= 7) {
      final bd = ByteData.sublistView(payload);
      final int srcNode;
      final int packetId;
      final int rssi;
      final double snr;
      final int flags;
      final Uint8List rawMsg;

      if (payload.length >= 11) {
        srcNode = bd.getUint32(0, Endian.little);
        packetId = bd.getUint32(4, Endian.little);
        rssi = bd.getInt8(8);
        snr = bd.getInt8(9).toDouble();
        flags = bd.getUint8(10);
        rawMsg = payload.sublist(11);
      } else {
        srcNode = bd.getUint32(0, Endian.little);
        packetId = 0;
        rssi = bd.getInt8(4);
        snr = bd.getInt8(5).toDouble();
        flags = bd.getUint8(6);
        rawMsg = payload.sublist(7);
      }

      // Drop our own echoed packets and suppress rapid in-memory duplicates
      if (_localNodeId != 0 && srcNode == _localNodeId) {
        return;
      }
      if (packetId != 0 && _markPacketSeenInMemory(srcNode, packetId)) {
        return;
      }

      // Deduplicate incoming packets on mobile SQLite database
      if (packetId != 0) {
        final duplicate = await db.query(
          'messages',
          where: 'packet_id = ? AND sender_node_id = ?',
          whereArgs: [packetId, srcNode],
          limit: 1,
        );
        if (duplicate.isNotEmpty) {
          return; // Duplicate frame suppressed
        }
      }

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final isEncrypted = (flags & BleConstants.flagEncrypted) != 0;
      final isSos = (flags & BleConstants.flagSos) != 0;
      final isBroadcast = (flags & BleConstants.flagBroadcast) != 0;

      // Handle SOS Distress Packets
      if (isSos) {
        double? lat;
        double? lon;
        String sosText;
        if (rawMsg.length >= 8) {
          final sosBd = ByteData.sublistView(rawMsg);
          final latE7 = sosBd.getInt32(0, Endian.little);
          final lonE7 = sosBd.getInt32(4, Endian.little);
          if (latE7 != 0 || lonE7 != 0) {
            lat = latE7 / 10000000.0;
            lon = lonE7 / 10000000.0;
          }
          final textBytes = rawMsg.sublist(8);
          sosText = utf8.decode(textBytes, allowMalformed: true);
        } else {
          sosText = utf8.decode(rawMsg, allowMalformed: true);
        }

        final alert = SosAlertModel(
          packetId: packetId,
          senderNodeId: srcNode,
          latitude: lat,
          longitude: lon,
          distressMessage: sosText,
          timestamp: now,
          rssi: rssi,
          snr: snr,
        );
        _sosAlertStreamController.add(alert);

        final locationTag = alert.hasLocation ? ' [GPS: ${alert.locationString}]' : '';
        final broadcastText = '🚨 [EMERGENCY SOS from ${alert.formattedNodeHex}] $sosText$locationTag';

        await db.rawUpdate('''
          UPDATE conversations 
          SET last_message_text = ?, last_message_timestamp = ?, unread_count = unread_count + 1, updated_at = ?
          WHERE id = ?
        ''', [broadcastText, now, now, 'broadcast']);

        final msgId = _uuid.v4();
        final incomingMsg = MessageModel(
          id: msgId,
          packetId: packetId,
          conversationId: 'broadcast',
          senderNodeId: srcNode,
          recipientNodeId: 0xFFFFFFFF,
          textContent: broadcastText,
          deliveryStatus: MessageDeliveryStatus.delivered,
          isIncoming: true,
          isEncrypted: false,
          rssi: rssi,
          snr: snr,
          createdAt: now,
          deliveredAt: now,
        );
        await db.insert('messages', incomingMsg.toMap());

        _notifyUpdates('broadcast');
        return;
      }

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

      // Check if incoming text is an incoming LoRa micro-image chunk
      if (text.startsWith('IMG:')) {
        final parts = text.split(':');
        if (parts.length >= 5) {
          final imgId = parts[1];
          final chunkIdx = int.tryParse(parts[2], radix: 16) ?? 0;
          final totalChunks = int.tryParse(parts[3], radix: 16) ?? 1;
          final chunkData = parts.sublist(4).join(':');

          final fullBase64 = _reassembleImageChunk(
            senderNodeId: srcNode,
            imageId: imgId,
            chunkIdx: chunkIdx,
            totalChunks: totalChunks,
            chunkData: chunkData,
          );

          if (fullBase64 != null) {
            text = '[IMAGE:$fullBase64]';
          } else {
            // Partial image chunk buffered; wait for all chunks before committing
            return;
          }
        }
      }

      final convId = isBroadcast
          ? 'broadcast'
          : '0x${srcNode.toRadixString(16).padLeft(8, '0').toUpperCase()}';

      final summaryText = text.startsWith('[IMAGE:') ? '📷 Photo' : text;

      if (isBroadcast) {
        // Update default broadcast conversation
        await db.rawUpdate('''
          UPDATE conversations 
          SET last_message_text = ?, last_message_timestamp = ?, unread_count = unread_count + 1, updated_at = ?
          WHERE id = ?
        ''', [summaryText, now, now, 'broadcast']);
      } else {
        // Ensure direct conversation exists
        final existingConvs =
            await db.query('conversations', where: 'id = ?', whereArgs: [convId]);
        if (existingConvs.isEmpty) {
          await db.insert('conversations', {
            'id': convId,
            'title': 'Node $convId',
            'peer_node_id': srcNode,
            'last_message_text': summaryText,
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
          ''', [summaryText, now, now, convId]);
        }
      }

      // Insert incoming message
      final msgId = _uuid.v4();
      final incomingMsg = MessageModel(
        id: msgId,
        packetId: packetId,
        conversationId: convId,
        senderNodeId: srcNode,
        recipientNodeId: isBroadcast ? 0xFFFFFFFF : 0,
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
    // Legacy: [SEQ: 1B][STATUS: 1B]
    // Enhanced: [SEQ: 1B][STATUS: 1B][PACKET_ID: 4B]
    else if (eventType == BleConstants.evtTxStatus && payload.length >= 2) {
      final statusByte = payload[1];
      if (statusByte != 0x02 && statusByte != 0x03) return;
      final newStatus = statusByte == 0x02
          ? MessageDeliveryStatus.transmitted
          : MessageDeliveryStatus.failed;

      if (payload.length >= 6) {
        final bd = ByteData.sublistView(payload);
        final packetId = bd.getUint32(2, Endian.little);
        final matched = await db.query(
          'messages',
          where: 'packet_id = ? AND delivery_status != ?',
          whereArgs: [packetId, MessageDeliveryStatus.delivered.toDbString()],
          limit: 1,
        );
        if (matched.isNotEmpty) {
          final convId = matched.first['conversation_id'] as String;
          await db.update(
            'messages',
            {'delivery_status': newStatus.toDbString()},
            where: 'packet_id = ? AND delivery_status != ?',
            whereArgs: [packetId, MessageDeliveryStatus.delivered.toDbString()],
          );
          _notifyUpdates(convId);
        }
      } else {
        // Legacy fallback: update oldest queued message
        final latest = await db.query(
          'messages',
          where: 'delivery_status = ?',
          whereArgs: [MessageDeliveryStatus.queued.toDbString()],
          orderBy: 'created_at ASC',
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
    _bleConnectionSubscription?.cancel();
    _conversationsStreamController.close();
    _messagesStreamController.close();
    _nodesStreamController.close();
    _sosAlertStreamController.close();
  }
}
