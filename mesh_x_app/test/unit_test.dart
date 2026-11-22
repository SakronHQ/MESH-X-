import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:mesh_x_app/core/constants/ble_constants.dart';
import 'package:mesh_x_app/core/security/crypto_service.dart';
import 'package:mesh_x_app/core/utils/crc16.dart';
import 'package:mesh_x_app/features/device/domain/connection_state.dart';
import 'package:mesh_x_app/features/device/domain/device_info_model.dart';
import 'package:mesh_x_app/features/chat/domain/message_model.dart';
import 'package:mesh_x_app/features/chat/domain/conversation_model.dart';
import 'package:mesh_x_app/features/device/domain/radio_config_model.dart';
import 'package:mesh_x_app/core/utils/geo_utils.dart';
import 'package:mesh_x_app/features/mesh/domain/mesh_node_model.dart';
import 'package:mesh_x_app/features/sos/domain/sos_alert_model.dart';

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
      expect(
          BleConnectionStatus.scanning.label, equals('Scanning for nodes...'));
    });

    test(
        'MessageModel serialization and status transitions behave correctly',
        () {
      const msg = MessageModel(
        id: 'msg-1234',
        packetId: 998877,
        conversationId: '0xA1B2C3D4',
        senderNodeId: 0x11111111,
        recipientNodeId: 0x22222222,
        textContent: 'Hello over LoRa mesh!',
        deliveryStatus: MessageDeliveryStatus.queued,
        isIncoming: false,
        isEncrypted: true,
        createdAt: 1700000000,
      );

      final map = msg.toMap();
      expect(map['delivery_status'], equals('QUEUED'));
      expect(map['is_incoming'], equals(0));
      expect(map['is_encrypted'], equals(1));

      final restored = MessageModel.fromMap(map);
      expect(restored.id, equals('msg-1234'));
      expect(restored.deliveryStatus, equals(MessageDeliveryStatus.queued));
      expect(restored.isEncrypted, isTrue);

      final delivered =
          restored.copyWith(deliveryStatus: MessageDeliveryStatus.delivered);
      expect(delivered.deliveryStatus, equals(MessageDeliveryStatus.delivered));
    });

    test('ConversationModel formatted peer hex handles broadcast properly',
        () {
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

    test('MeshNodeModel correctly maps properties and computes hop metrics',
        () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final directNode = MeshNodeModel(
        nodeId: 0xDEADBEEF,
        alias: 'Node 0xDEADBEEF',
        hopDistance: 1,
        lastRssi: -72,
        lastSnr: 8.5,
        lastSeenAt: now,
        publicKey: '0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF',
        isVerified: true,
      );

      expect(directNode.formattedNodeHex, equals('0xDEADBEEF'));
      expect(directNode.isDirectNeighbor, isTrue);
      expect(directNode.hasPublicKey, isTrue);
      expect(directNode.fingerprint, equals('0123:4567:89AB:CDEF'));
      expect(directNode.relativeLastSeen, equals('Just now'));

      final multiHopNode = directNode.copyWith(hopDistance: 3);
      expect(multiHopNode.isDirectNeighbor, isFalse);
      expect(multiHopNode.hopDistance, equals(3));

      final map = directNode.toMap();
      expect(map['public_key'], equals('0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF'));
      expect(map['is_verified'], equals(1));

      final fromDb = MeshNodeModel.fromMap(map);
      expect(fromDb.nodeId, equals(0xDEADBEEF));
      expect(fromDb.lastRssi, equals(-72));
      expect(fromDb.lastSnr, equals(8.5));
      expect(fromDb.hasPublicKey, isTrue);
      expect(fromDb.isVerified, isTrue);
    });

    test('Mesh Router 64-entry LRU ring buffer suppresses duplicates', () {
      final cache = <int>[];
      const cacheSize = 64;

      bool isDuplicate(int packetId) {
        if (cache.contains(packetId)) return true;
        if (cache.length >= cacheSize) {
          cache.removeAt(0); // Evict oldest
        }
        cache.add(packetId);
        return false;
      }

      // First time seen -> not duplicate
      expect(isDuplicate(0x1000), isFalse);
      // Second time seen -> duplicate!
      expect(isDuplicate(0x1000), isTrue);

      // Fill cache with 64 new packets
      for (int i = 1; i <= 64; i++) {
        expect(isDuplicate(0x2000 + i), isFalse);
      }

      // 0x1000 should now have been evicted
      expect(isDuplicate(0x1000), isFalse);
    });

    test('Mesh Multi-hop TTL decrement and hop count relay rules', () {
      // Rule 1: Packet with TTL > 1 can be relayed
      int ttl = 3;
      int hopCount = 0;
      bool canRelay = ttl > 1;
      expect(canRelay, isTrue);

      // After relay
      ttl--;
      hopCount++;
      expect(ttl, equals(2));
      expect(hopCount, equals(1));

      // Rule 2: Packet with TTL == 1 cannot be relayed further
      ttl = 1;
      canRelay = ttl > 1;
      expect(canRelay, isFalse);
    });

    test('E2EE CryptoService generates keypair, encrypts and decrypts with ChaCha20-Poly1305', () async {
      final alice = CryptoService(MemoryKeyStorage());
      await alice.init();
      final alicePub = await alice.getMyPublicKeyHex();
      final aliceFingerprint = await alice.getMyFingerprint();

      expect(alicePub.length, equals(64));
      expect(aliceFingerprint.split(':').length, equals(4));

      final bob = CryptoService(MemoryKeyStorage());
      await bob.init();
      final bobPub = await bob.getMyPublicKeyHex();

      const secretMsg = 'Confidential RF Mesh Packet 123';
      final ciphertext = await alice.encryptPayload(
        plaintext: secretMsg,
        peerPublicKeyHex: bobPub,
      );

      // Verify wire payload format: Nonce (12B) + Timestamp (4B) + Ciphertext + Poly1305 MAC (16B)
      expect(ciphertext.length, greaterThan(secretMsg.length + 28));

      // Bob decrypts
      final decrypted = await bob.decryptPayload(
        wireBytes: ciphertext,
        peerPublicKeyHex: alicePub,
      );
      expect(decrypted, equals(secretMsg));
    });

    test('E2EE CryptoService detects packet tampering via Poly1305 authentication failure', () async {
      final alice = CryptoService(MemoryKeyStorage());
      await alice.init();
      final alicePub = await alice.getMyPublicKeyHex();

      final bob = CryptoService(MemoryKeyStorage());
      await bob.init();
      final bobPub = await bob.getMyPublicKeyHex();

      final ciphertext = await alice.encryptPayload(
        plaintext: 'Tamper proof message',
        peerPublicKeyHex: bobPub,
      );

      // Alter one byte in ciphertext
      final tampered = List<int>.from(ciphertext);
      tampered[14] ^= 0x55;

      expect(
        () => bob.decryptPayload(wireBytes: tampered, peerPublicKeyHex: alicePub),
        throwsA(anything),
      );
    });

    test('MeshXDeviceInfo parses battery voltage and computes percentage', () {
      final json1 = {
        'node_id': 0x12345678,
        'fw': '1.3.0',
        'proto': 1,
        'name': 'MESH-X-345678',
        'batt': 4200,
      };
      final dev1 = MeshXDeviceInfo.fromJson(json1);
      expect(dev1.batteryMv, equals(4200));
      expect(dev1.batteryVoltage, equals(4.2));
      expect(dev1.batteryPercentage, equals(100));

      final json2 = {
        'node_id': 0x12345678,
        'batt': 3900,
      };
      final dev2 = MeshXDeviceInfo.fromJson(json2);
      expect(dev2.batteryVoltage, equals(3.9));
      expect(dev2.batteryPercentage, equals(50));

      final json3 = {
        'node_id': 0x12345678,
        'batt': 3500,
      };
      final dev3 = MeshXDeviceInfo.fromJson(json3);
      expect(dev3.batteryPercentage, equals(0));
    });

    test('SosAlertModel serialization and location helpers behave correctly', () {
      const alert = SosAlertModel(
        packetId: 0x55AA1122,
        senderNodeId: 0xA1B2C3D4,
        latitude: 23.7749123,
        longitude: 90.3995456,
        distressMessage: '🚑 Medical Emergency - Injured hiker',
        timestamp: 1700000000,
        rssi: -65,
        snr: 10.2,
      );

      expect(alert.formattedNodeHex, equals('0xA1B2C3D4'));
      expect(alert.hasLocation, isTrue);
      expect(alert.locationString, equals('23.77491, 90.39955'));

      final map = alert.toMap();
      expect(map['packet_id'], equals(0x55AA1122));
      expect(map['sender_node_id'], equals(0xA1B2C3D4));
      expect(map['distress_message'], contains('Medical Emergency'));

      final fromMap = SosAlertModel.fromMap(map);
      expect(fromMap, equals(alert));

      const noLocAlert = SosAlertModel(
        packetId: 1,
        senderNodeId: 0x11111111,
        distressMessage: 'Distress without GPS',
        timestamp: 1700000000,
      );
      expect(noLocAlert.hasLocation, isFalse);
      expect(noLocAlert.locationString, equals('No GPS Location Attached'));
    });

    test('Emergency SOS wire format encodes and decodes micro-degree E7 coordinates', () {
      const packetId = 0x1234ABCD;
      const lat = 23.7749123;
      const lon = 90.3995456;
      const distressText = 'Search & Rescue needed';

      // Encode wire payload: [PACKET_ID: 4B][LAT_E7: 4B][LON_E7: 4B][TEXT]
      final textBytes = Uint8List.fromList(utf8.encode(distressText));
      final wireBytes = Uint8List(4 + 4 + 4 + textBytes.length);
      final bd = ByteData.sublistView(wireBytes);
      bd.setUint32(0, packetId, Endian.little);
      bd.setInt32(4, (lat * 10000000).round(), Endian.little);
      bd.setInt32(8, (lon * 10000000).round(), Endian.little);
      wireBytes.setRange(12, 12 + textBytes.length, textBytes);

      expect(wireBytes.length, equals(12 + distressText.length));

      // Decode wire payload on receiver
      final rxBd = ByteData.sublistView(wireBytes);
      final rxPktId = rxBd.getUint32(0, Endian.little);
      final rxLatE7 = rxBd.getInt32(4, Endian.little);
      final rxLonE7 = rxBd.getInt32(8, Endian.little);
      final rxText = utf8.decode(wireBytes.sublist(12));

      expect(rxPktId, equals(packetId));
      expect(rxLatE7 / 10000000.0, closeTo(lat, 0.0000001));
      expect(rxLonE7 / 10000000.0, closeTo(lon, 0.0000001));
      expect(rxText, equals(distressText));
    });

    test('BleConstants packet flags define broadcast and encryption bitmasks', () {
      expect(BleConstants.flagReqAck, equals(0x01));
      expect(BleConstants.flagEncrypted, equals(0x02));
      expect(BleConstants.flagBroadcast, equals(0x04));
      expect(BleConstants.flagSos, equals(0x08));

      // Test routing decision logic
      int broadcastFlags = BleConstants.flagBroadcast;
      bool isBroadcast = (broadcastFlags & BleConstants.flagBroadcast) != 0;
      String convId = isBroadcast ? 'broadcast' : '0x12345678';
      expect(convId, equals('broadcast'));

      int unicastFlags = BleConstants.flagReqAck | BleConstants.flagEncrypted;
      bool isUnicastBroadcast = (unicastFlags & BleConstants.flagBroadcast) != 0;
      String unicastConvId = isUnicastBroadcast ? 'broadcast' : '0x12345678';
      expect(unicastConvId, equals('0x12345678'));
    });

    test('KeyExchangeDialog URI scheme parses pub parameter correctly', () {
      const qrData = 'meshx://key?id=0xA1B2C3D4&pub=0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF';
      final uri = Uri.parse(qrData);
      expect(uri.scheme, equals('meshx'));
      expect(uri.queryParameters['id'], equals('0xA1B2C3D4'));
      final pub = uri.queryParameters['pub'];
      expect(pub, isNotNull);
      expect(pub!.length, equals(64));
      expect(RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(pub), isTrue);

      // Verify non-hex rejection
      final nonHexKey = 'A' * 63 + 'Z'; // 63 valid hex + 1 non-hex character (Z)
      expect(nonHexKey.length, equals(64));
      expect(RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(nonHexKey), isFalse);

      // Verify node ID parsing with and without 0x prefix
      int? parseNodeId(String s) {
        if (s.startsWith('0x') || s.startsWith('0X')) {
          return int.tryParse(s.substring(2), radix: 16);
        }
        return int.tryParse(s) ?? int.tryParse(s, radix: 16);
      }

      expect(parseNodeId('0xA1B2C3D4'), equals(0xA1B2C3D4));
      expect(parseNodeId('A1B2C3D4'), equals(0xA1B2C3D4));
      expect(parseNodeId('123456'), equals(123456));
      expect(parseNodeId('invalid_node'), isNull);
    });

    test('RadioConfigModel encodes to binary wire format and decodes accurately', () {
      const config = RadioConfigModel(
        frequencyMhz: 433.775,
        spreadingFactor: 11,
        bandwidthKhz: 250.0,
        codingRate: 8,
        txPowerDbm: 17,
      );

      final bytes = config.toBytes();
      expect(bytes.length, equals(9));

      // Verify Little-Endian frequency in kHz (433775 = 0x00069E6F)
      final bd = ByteData.sublistView(bytes);
      expect(bd.getUint32(0, Endian.little), equals(433775));
      expect(bytes[4], equals(11)); // SF
      expect(bd.getUint16(5, Endian.little), equals(250)); // BW kHz
      expect(bytes[7], equals(8)); // CR
      expect(bytes[8], equals(17)); // TX power

      final restored = RadioConfigModel.fromBytes(bytes);
      expect(restored.frequencyMhz, closeTo(433.775, 0.001));
      expect(restored.spreadingFactor, equals(11));
      expect(restored.bandwidthKhz, equals(250.0));
      expect(restored.codingRate, equals(8));
      expect(restored.txPowerDbm, equals(17));
    });

    test('RadioConfigModel toMap and fromMap serialization round-trips correctly', () {
      const original = RadioConfigModel(
        frequencyMhz: 433.375,
        spreadingFactor: 8,
        bandwidthKhz: 250.0,
        codingRate: 6,
        txPowerDbm: 16,
      );
      final map = original.toMap();
      final restored = RadioConfigModel.fromMap(map);
      expect(restored, equals(original));
      expect(restored.frequencyMhz, equals(433.375));
      expect(restored.spreadingFactor, equals(8));
      expect(restored.bandwidthKhz, equals(250.0));
      expect(restored.codingRate, equals(6));
      expect(restored.txPowerDbm, equals(16));
    });

    test('RadioConfigModel clamps out-of-range parameters defensively', () {
      const outOfBounds = RadioConfigModel(
        frequencyMhz: 433.175,
        spreadingFactor: 15, // Max is 12
        bandwidthKhz: 125.0,
        codingRate: 10, // Max is 8
        txPowerDbm: 25, // Max is 20
      );

      final bytes = outOfBounds.toBytes();
      expect(bytes[4], equals(12)); // Clamped to SF12
      expect(bytes[7], equals(8));  // Clamped to CR8
      expect(bytes[8], equals(20)); // Clamped to 20 dBm
    });

    test('RadioConfigModel Time-on-Air estimation produces realistic values and handles edge cases', () {
      const fastConfig = RadioConfigModel(spreadingFactor: 7, bandwidthKhz: 250.0);
      const longRangeConfig = RadioConfigModel(spreadingFactor: 12, bandwidthKhz: 125.0);

      final fastToA = fastConfig.estimateTimeToAirMs(payloadBytes: 32);
      final longRangeToA = longRangeConfig.estimateTimeToAirMs(payloadBytes: 32);

      expect(fastToA, greaterThan(0));
      expect(longRangeToA, greaterThan(fastToA));
      expect(fastConfig.speedModeDescription, contains('Fast'));
      expect(longRangeConfig.speedModeDescription, contains('Extreme'));

      // Zero-byte and negative-byte payload boundaries
      final zeroPayloadToA = fastConfig.estimateTimeToAirMs(payloadBytes: 0);
      expect(zeroPayloadToA, greaterThan(0));
      expect(zeroPayloadToA, lessThanOrEqualTo(fastToA));

      // Large payload
      final largePayloadToA = fastConfig.estimateTimeToAirMs(payloadBytes: 240);
      expect(largePayloadToA, greaterThan(fastToA));
    });

    test('Tactical radar angle calculation is robust against negative Node IDs', () {
      const negativeNodeId = -123456789;
      final angleDeg = ((negativeNodeId.abs() * 37) % 360).toDouble();
      expect(angleDeg, greaterThanOrEqualTo(0.0));
      expect(angleDeg, lessThan(360.0));
    });

    test('GeoUtils computes deterministic Haversine distance and bearing', () {
      // Coordinate 1: Dhaka, Bangladesh (23.8103, 90.4125)
      // Coordinate 2: Gazipur, Bangladesh (23.9999, 90.4203) (~21 km north)
      final distance = GeoUtils.computeDistanceMeters(23.8103, 90.4125, 23.9999, 90.4203);
      expect(distance, greaterThan(20000));
      expect(distance, lessThan(23000));

      final bearing = GeoUtils.computeBearingDegrees(23.8103, 90.4125, 23.9999, 90.4203);
      expect(bearing, closeTo(2.0, 5.0)); // Mostly directly North (~2 degrees)

      // Distance formatting helper
      expect(GeoUtils.formatDistance(450), equals('450 m'));
      expect(GeoUtils.formatDistance(3250), equals('3.3 km'));

      // Log-distance RSSI path loss estimate
      final distClose = GeoUtils.estimateDistanceMetersFromRssi(-50);
      final distFar = GeoUtils.estimateDistanceMetersFromRssi(-110);
      expect(distClose, lessThan(distFar));
      expect(distClose, greaterThan(0));
    });

    test('LoRa Micro-Image fragmentation and reassembly works deterministically', () {
      // Simulate raw micro-JPEG bytes (~1.5 KB)
      final dummyBytes = Uint8List.fromList(List.generate(1500, (i) => (i * 7) % 256));
      final base64String = base64Encode(dummyBytes);

      const chunkSize = 140;
      final totalChunks = (base64String.length / chunkSize).ceil();
      const imageId = 'A7';

      // 1. Fragmentation
      final transmittedChunks = <String>[];
      for (int i = 0; i < totalChunks; i++) {
        final start = i * chunkSize;
        final end = (start + chunkSize > base64String.length) ? base64String.length : start + chunkSize;
        final slice = base64String.substring(start, end);
        final chunkText =
            'IMG:$imageId:${i.toRadixString(16).padLeft(2, '0')}:${totalChunks.toRadixString(16).padLeft(2, '0')}:$slice';
        transmittedChunks.add(chunkText);
      }

      expect(transmittedChunks.length, equals(totalChunks));
      expect(transmittedChunks.every((c) => c.startsWith('IMG:A7:')), isTrue);

      // 2. Reassembly simulation (even if chunks arrive out of order)
      final reassembledMap = <int, String>{};
      final shuffledIndices = List.generate(totalChunks, (i) => i)..shuffle();

      String? finalReassembled;
      for (final idx in shuffledIndices) {
        final packet = transmittedChunks[idx];
        final parts = packet.split(':');
        final chunkIdx = int.parse(parts[2], radix: 16);
        final numChunks = int.parse(parts[3], radix: 16);
        final data = parts.sublist(4).join(':');

        reassembledMap[chunkIdx] = data;
        if (reassembledMap.length == numChunks) {
          final sorted = List.generate(numChunks, (i) => reassembledMap[i]!);
          finalReassembled = sorted.join();
        }
      }

      expect(finalReassembled, isNotNull);
      expect(finalReassembled, equals(base64String));
      final decodedBytes = base64Decode(finalReassembled!);
      expect(decodedBytes, equals(dummyBytes));
    });
  });
}
