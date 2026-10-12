import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../../../core/constants/ble_constants.dart';
import '../../../data/database/app_database.dart';
import '../../device/data/ble_repository.dart';
import '../domain/conversation_model.dart';
import '../domain/message_model.dart';

class ChatRepository {
  final BleRepository _bleRepository;
  final _uuid = const Uuid();
  StreamSubscription<List<int>>? _bleEventSubscription;

  final _conversationsStreamController = StreamController<List<ConversationModel>>.broadcast();
  Stream<List<ConversationModel>> get conversationsStream => _conversationsStreamController.stream;

  final _messagesStreamController = StreamController<String>.broadcast(); // Emits conversationId on update
  Stream<String> get messagesUpdateStream => _messagesStreamController.stream;

  ChatRepository(this._bleRepository) {
    _initEventListener();
  }

  void _initEventListener() {
    _bleEventSubscription = _bleRepository.eventStream.listen((rawFrame) {
      _handleBleEvent(rawFrame);
    });
  }

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

    final message = MessageModel(
      id: messageId,
      packetId: packetId,
      conversationId: conversationId,
      senderNodeId: localNodeId,
      recipientNodeId: recipientNodeId,
      textContent: textContent,
      deliveryStatus: MessageDeliveryStatus.queued,
      isIncoming: false,
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

    // Package payload for BLE command: [PACKET_ID: 4B][DEST_NODE: 4B][FLAGS: 1B][TEXT]
    final textBytes = utf8.encode(textContent);
    final payload = Uint8List(4 + 4 + 1 + textBytes.length);
    final bd = ByteData.sublistView(payload);
    bd.setUint32(0, packetId, Endian.little);
    bd.setUint32(4, recipientNodeId, Endian.little);
    bd.setUint8(8, 0x01); // Requires ACK flag
    payload.setRange(9, 9 + textBytes.length, textBytes);

    // Transmit over BLE Command characteristic
    await _bleRepository.sendCommand(BleConstants.cmdSubmitMessage, payload);

    return message;
  }

  Future<void> retryMessage(String messageId) async {
    final db = await AppDatabase.instance;
    final maps = await db.query('messages', where: 'id = ?', whereArgs: [messageId]);
    if (maps.isEmpty) return;

    final msg = MessageModel.fromMap(maps.first);
    final updatedRetry = msg.retryCount + 1;

    await db.update(
      'messages',
      {
        'delivery_status': MessageDeliveryStatus.queued.toDbString(),
        'retry_count': updatedRetry,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );

    _notifyUpdates(msg.conversationId);

    // Re-submit to BLE
    final textBytes = utf8.encode(msg.textContent);
    final payload = Uint8List(4 + 4 + 1 + textBytes.length);
    final bd = ByteData.sublistView(payload);
    bd.setUint32(0, msg.packetId, Endian.little);
    bd.setUint32(4, msg.recipientNodeId, Endian.little);
    bd.setUint8(8, 0x01);
    payload.setRange(9, 9 + textBytes.length, textBytes);

    await _bleRepository.sendCommand(BleConstants.cmdSubmitMessage, payload);
  }

  Future<void> _handleBleEvent(List<int> rawFrame) async {
    if (rawFrame.length < 12) return;
    final bytes = Uint8List.fromList(rawFrame);
    final eventType = bytes[3];
    final payload = bytes.sublist(10, bytes.length - 2);

    final db = await AppDatabase.instance;

    // 1. Inbound Received LoRa Message: EVT_RX_MESSAGE (0x80)
    // Payload: [SRC_NODE: 4B][RSSI: 1B (int8)][SNR: 1B (int8)][TEXT]
    if (eventType == BleConstants.evtRxMessage && payload.length >= 6) {
      final bd = ByteData.sublistView(payload);
      final srcNode = bd.getUint32(0, Endian.little);
      final rssi = bd.getInt8(4);
      final snr = bd.getInt8(5).toDouble();
      final text = utf8.decode(payload.sublist(6));
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final convId = '0x${srcNode.toRadixString(16).padLeft(8, '0').toUpperCase()}';

      // Ensure conversation exists
      final existingConvs = await db.query('conversations', where: 'id = ?', whereArgs: [convId]);
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
          : (statusByte == 0x03 ? MessageDeliveryStatus.failed : MessageDeliveryStatus.queued);

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

      final matched = await db.query('messages', where: 'packet_id = ?', whereArgs: [packetId]);
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
  }
}
