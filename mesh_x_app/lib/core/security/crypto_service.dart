import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

abstract class KeyStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class MemoryKeyStorage implements KeyStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }
}

class CryptoService {
  static const String prefPrivateKeyHex = 'mesh_x_e2ee_private_key';
  static final _x25519 = X25519();
  static final _chacha20 = Chacha20.poly1305Aead();

  final KeyStorage _storage;
  SimpleKeyPair? _keyPair;

  CryptoService([KeyStorage? storage]) : _storage = storage ?? MemoryKeyStorage();

  /// Initialize and load or generate X25519 Identity Keypair
  Future<void> init() async {
    final savedHex = await _storage.read(prefPrivateKeyHex);

    if (savedHex != null && savedHex.length == 64) {
      final privateBytes = _hexToBytes(savedHex);
      _keyPair = await _x25519.newKeyPairFromSeed(privateBytes);
    } else {
      _keyPair = await _x25519.newKeyPair();
      final privateBytes = await _keyPair!.extractPrivateKeyBytes();
      await _storage.write(prefPrivateKeyHex, _bytesToHex(privateBytes));
    }
  }

  /// Get local public key as a 64-character hex string (32 bytes)
  Future<String> getMyPublicKeyHex() async {
    if (_keyPair == null) await init();
    final pubKey = await _keyPair!.extractPublicKey();
    return _bytesToHex(pubKey.bytes);
  }

  /// Format public key into a readable fingerprint: e.g. "1A2B:3C4D:5E6F:7A8B"
  Future<String> getMyFingerprint() async {
    final hex = await getMyPublicKeyHex();
    final upper = hex.toUpperCase();
    return '${upper.substring(0, 4)}:${upper.substring(4, 8)}:${upper.substring(8, 12)}:${upper.substring(12, 16)}';
  }

  /// Encrypt a plaintext message for a specific peer using X25519 + ChaCha20-Poly1305
  /// Returns binary wire payload containing [NONCE (12B)][CIPHERTEXT][MAC (16B)]
  Future<Uint8List> encryptPayload({
    required String plaintext,
    required String peerPublicKeyHex,
  }) async {
    if (_keyPair == null) await init();

    if (peerPublicKeyHex.length != 64) {
      throw ArgumentError('Invalid peer public key length. Expected 64 hex chars.');
    }

    final remotePubBytes = _hexToBytes(peerPublicKeyHex);
    final remotePublicKey = SimplePublicKey(remotePubBytes, type: KeyPairType.x25519);

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: _keyPair!,
      remotePublicKey: remotePublicKey,
    );

    // Frame with 4-byte replay-protection timestamp
    final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final textBytes = utf8.encode(plaintext);
    final plainWithTime = Uint8List(4 + textBytes.length);
    final bd = ByteData.sublistView(plainWithTime);
    bd.setUint32(0, nowEpoch, Endian.little);
    plainWithTime.setRange(4, 4 + textBytes.length, textBytes);

    // AEAD Encryption
    final secretBox = await _chacha20.encrypt(
      plainWithTime,
      secretKey: sharedSecret,
    );

    return Uint8List.fromList(secretBox.concatenation());
  }

  /// Decrypt a binary wire payload from a peer using X25519 + ChaCha20-Poly1305
  /// Throws if Poly1305 MAC check fails or payload is malformed
  Future<String> decryptPayload({
    required List<int> wireBytes,
    required String peerPublicKeyHex,
  }) async {
    if (_keyPair == null) await init();

    if (wireBytes.length < 28) {
      throw const FormatException('Ciphertext payload too short.');
    }

    if (peerPublicKeyHex.length != 64) {
      throw ArgumentError('Invalid peer public key length.');
    }

    final remotePubBytes = _hexToBytes(peerPublicKeyHex);
    final remotePublicKey = SimplePublicKey(remotePubBytes, type: KeyPairType.x25519);

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: _keyPair!,
      remotePublicKey: remotePublicKey,
    );

    final secretBox = SecretBox.fromConcatenation(
      wireBytes,
      nonceLength: _chacha20.nonceLength,
      macLength: _chacha20.macAlgorithm.macLength,
    );

    final decryptedBytes = await _chacha20.decrypt(
      secretBox,
      secretKey: sharedSecret,
    );

    if (decryptedBytes.length < 4) {
      throw const FormatException('Decrypted payload missing timestamp header.');
    }

    // Extract text content (skipping 4-byte timestamp)
    return utf8.decode(decryptedBytes.sublist(4));
  }

  static Uint8List _hexToBytes(String hex) {
    final clean = hex.replaceAll(':', '').replaceAll(' ', '').trim();
    final result = Uint8List(clean.length ~/ 2);
    for (int i = 0; i < clean.length; i += 2) {
      result[i ~/ 2] = int.parse(clean.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  static String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
