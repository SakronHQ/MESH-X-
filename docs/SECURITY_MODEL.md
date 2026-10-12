# MESH-X Security Model & Cryptographic Roadmap

## 1. Threat Model & Attack Vectors

In an open off-grid RF radio environment, any radio receiver in range can monitor or inject packets on 433 MHz.

### 1.1 Evaluated Threats
1. **Passive Eavesdropping**: Adversary sniffing raw 433 MHz LoRa packets over the air to read plaintext private messages.
2. **Packet Tampering & Injection**: Malicious actor modifying packet bytes or forging sender Node IDs.
3. **Replay Attacks**: Capturing a valid packet (e.g., an unlock or distress ping) and re-broadcasting it later to confuse recipients.
4. **Unauthorized BLE Access**: A rogue smartphone connecting to the ESP32 node via BLE and issuing commands or sniffing incoming notifications.
5. **Denial of Service / Airtime Flooding**: Deliberate transmission of garbage packets to saturate the 433 MHz channel.

---

## 2. Security Roadmap & Phased Implementation

To balance rapid prototyping with enterprise-grade security, security primitives are rolled out progressively:

| Development Stage | Transport Security | Payload Security | Identity Verification |
|---|---|---|---|
| **Phases 0–4 (MVP)** | CRC16 CCITT framing | Cleartext UTF-8 | 32-bit hardware Node ID |
| **Phase 5 (Mesh)** | CRC16 + Replay window | Cleartext UTF-8 | Node announcement checks |
| **Phase 6 (Security Hardening)** | BLE PIN / Authenticated Pairing | **Authenticated End-to-End Encryption (AEAD)** | Ed25519 / Curve25519 Key Pairs |

---

## 3. Cryptographic Primitives (Phase 6 Specification)

MESH-X adopts established, modern cryptographic standards rather than proprietary algorithms.

```
+-----------------------------------------------------------------------------+
|                         CRYPTOGRAPHIC SUITE                                 |
|                                                                             |
|  - Key Exchange:             X25519 (ECDH over Curve25519)                  |
|  - Authenticated Encryption: ChaCha20-Poly1305 (AEAD)                       |
|  - Identity & Signatures:    Ed25519 (Edwards-curve Digital Signature)      |
|  - Key Derivation:           HKDF-SHA256                                    |
+-----------------------------------------------------------------------------+
```

### 3.1 End-to-End Key Exchange
- Each MESH-X mobile client generates an X25519 key pair on initial startup.
- Public keys are shared out-of-band via QR code scan or periodic contact discovery announcements.
- Ephemeral shared secrets are derived using HKDF-SHA256.

### 3.2 Secure Local Key Storage
- **Android**: Android Keystore backed by hardware-backed TEE / StrongBox via `flutter_secure_storage`.
- **iOS**: Apple Keychain Services with `kSecAttrAccessibleAfterFirstUnlock`.
- **Rule**: Private keys never leave the phone. The ESP32 acts purely as a transport pipe and never inspects or decrypts private message payloads.

### 3.3 Replay Protection
- Outbound frames include a monotonically increasing 32-bit sequence number and UTC timestamp.
- Inbound frames falling outside a ±300 second acceptance window or repeating a seen sequence number are rejected before AEAD decryption.
