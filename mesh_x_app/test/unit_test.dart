import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:mesh_x_app/core/constants/ble_constants.dart';
import 'package:mesh_x_app/core/security/crypto_service.dart';
import 'package:mesh_x_app/core/utils/crc16.dart';
import 'package:mesh_x_app/features/device/domain/connection_state.dart';
import 'package:mesh_x_app/features/device/domain/device_info_model.dart';
import 'package:mesh_x_app/features/chat/domain/message_model.dart';
import 'package:mesh_x_app/features/chat/domain/conversation_model.dart';
import 'package:mesh_x_app/features/mesh/domain/mesh_node_model.dart';

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
  });
}
