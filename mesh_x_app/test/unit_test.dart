import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:mesh_x_app/core/constants/ble_constants.dart';
import 'package:mesh_x_app/core/utils/crc16.dart';
import 'package:mesh_x_app/features/device/domain/connection_state.dart';
import 'package:mesh_x_app/features/device/domain/device_info_model.dart';

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
  });
}
