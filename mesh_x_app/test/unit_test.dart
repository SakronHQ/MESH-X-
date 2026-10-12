import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:mesh_x_app/core/constants/ble_constants.dart';
import 'package:mesh_x_app/core/utils/crc16.dart';
import 'package:mesh_x_app/features/device/domain/connection_state.dart';
import 'package:mesh_x_app/features/device/domain/device_info_model.dart';
import 'package:mesh_x_app/features/chat/domain/message_model.dart';
import 'package:mesh_x_app/features/chat/domain/conversation_model.dart';

void main() {
  group('MESH-X Core Protocol & Domain Unit Tests', () {
    test('CRC-16-CCITT algorithm computes deterministically', () {
      final sample = Uint8List.fromList([0xAA, 0x58, 0x01, 0x11, 0x01, 0x00]);
      final crc1 = Crc16.compute(sample);
      final crc2 = Crc16.compute(sample);
      expect(crc1, equals(crc2));
      expect(crc1, isNonZero);
    });

    test('BleConstants UUIDs adhere to 128-bit format', () {
      expect(BleConstants.serviceUuid.length, equals(36));
      expect(BleConstants.charDeviceInfoUuid.length, equals(36));
      expect(BleConstants.charCommandInUuid.length, equals(36));
      expect(BleConstants.charEventOutUuid.length, equals(36));
      expect(BleConstants.charTelemetryUuid.length, equals(36));
    });

    test('MeshXDeviceInfo correctly parses firmware JSON format', () {
      final json = {
        'node_id': 0xA1B2C3D4,
        'fw': '1.0.0',
        'proto': 1,
        'name': 'MESH-X-B2C3D4',
        'rssi': -68,
        'snr': 9.5,
        'queue': 0,
        'uptime': 120,
      };

      final model = MeshXDeviceInfo.fromJson(json);
      expect(model.nodeId, equals(0xA1B2C3D4));
      expect(model.firmwareVersion, equals('1.0.0'));
      expect(model.protocolVersion, equals(1));
      expect(model.deviceName, equals('MESH-X-B2C3D4'));
      expect(model.rssi, equals(-68));
      expect(model.snr, equals(9.5));
      expect(model.uptimeSec, equals(120));
      expect(model.formattedNodeHex, equals('0xA1B2C3D4'));
    });

    test('BleConnectionStatus labels are human readable', () {
      expect(BleConnectionStatus.connected.label, equals('Connected'));
      expect(BleConnectionStatus.disconnected.label, equals('Disconnected'));
      expect(BleConnectionStatus.scanning.label, equals('Scanning for nodes...'));
    });

    test('MessageModel serialization and status transitions behave correctly', () {
      const msg = MessageModel(
        id: 'msg-1234',
        packetId: 998877,
        conversationId: '0xA1B2C3D4',
        senderNodeId: 0x11111111,
        recipientNodeId: 0x22222222,
        textContent: 'Hello over LoRa mesh!',
        deliveryStatus: MessageDeliveryStatus.queued,
        isIncoming: false,
        createdAt: 1700000000,
      );

      final map = msg.toMap();
      expect(map['delivery_status'], equals('QUEUED'));
      expect(map['is_incoming'], equals(0));

      final restored = MessageModel.fromMap(map);
      expect(restored.id, equals('msg-1234'));
      expect(restored.deliveryStatus, equals(MessageDeliveryStatus.queued));

      final delivered = restored.copyWith(deliveryStatus: MessageDeliveryStatus.delivered);
      expect(delivered.deliveryStatus, equals(MessageDeliveryStatus.delivered));
    });

    test('ConversationModel formatted peer hex handles broadcast properly', () {
      const broadcastConv = ConversationModel(
        id: 'broadcast',
        title: 'Public Mesh Broadcast',
        peerNodeId: 0xFFFFFFFF,
        createdAt: 1700000000,
        updatedAt: 1700000000,
      );
      expect(broadcastConv.formattedPeerHex, equals('BROADCAST'));

      const directConv = ConversationModel(
        id: '0x1A2B3C4D',
        title: 'Node 0x1A2B3C4D',
        peerNodeId: 0x1A2B3C4D,
        createdAt: 1700000000,
        updatedAt: 1700000000,
      );
      expect(directConv.formattedPeerHex, equals('0x1A2B3C4D'));
    });
  });
}
