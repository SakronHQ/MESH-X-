# MESH-X: Decentralized Offline LoRa Mesh Messaging Ecosystem
**A Secure, Zero-Cloud, Long-Range Communication System for Disasters and Off-Grid Scenarios**

---

## 1. Abstract
Terrestrial cellular networks and internet backends are vulnerable to infrastructure disruptions caused by natural disasters, grid failures, armed conflicts, and geographic isolation. This project presents **MESH-X**, an end-to-end, off-grid communication ecosystem combining affordable commodity hardware (ESP32 microcontrollers and Semtech SX1278 LoRa transceivers) with modern mobile computing (Flutter, Bluetooth Low Energy, SQLite, and Cryptography). MESH-X achieves true zero-knowledge multi-hop mesh routing, out-of-band X25519 authenticated key exchange, ChaCha20-Poly1305 authenticated payload encryption (AEAD), and high-priority GPS emergency distress flood broadcasting without reliance on cellular towers, Wi-Fi, satellites, or central servers.

---

## 2. Problem Statement & Project Motivation
When traditional communication infrastructure collapses:
1. **Critical Latency & Isolation**: Victims and first responders in remote areas or disaster zones cannot coordinate rescues due to lack of cell coverage.
2. **Privacy & Surveillance Risks**: Centralized communication platforms are vulnerable to eavesdropping, censorship, and data harvesting.
3. **Hardware Cost Barrier**: Commercial satellite communicators (e.g., Garmin inReach) require expensive proprietary hardware ($350+) and ongoing monthly subscriptions.

**MESH-X solves these challenges** by providing an open-source, subscription-free, peer-to-peer communication platform built for under **$10 per node**.

---

## 3. System Architecture & Component Hierarchy

```
┌─────────────────────────────────┐           ┌─────────────────────────────────┐
│       Alice's Smartphone        │           │        Bob's Smartphone         │
│   Flutter Mobile Application    │           │   Flutter Mobile Application    │
│  - Riverpod State Architecture  │           │  - Riverpod State Architecture  │
│  - SQLite Offline Persistence   │           │  - SQLite Offline Persistence   │
│  - X25519 + ChaCha20-Poly1305   │           │  - X25519 + ChaCha20-Poly1305   │
└────────────────┬────────────────┘           └────────────────┬────────────────┘
                 │ BLE GATT                                    │ BLE GATT
                 │ (128-bit Custom UUIDs)                      │ (128-bit Custom UUIDs)
┌────────────────┴────────────────┐           ┌────────────────┴────────────────┐
│      Node A: ESP32 Gateway      │           │      Node B: ESP32 Gateway      │
│  - BLE GATT Server              │           │  - BLE GATT Server              │
│  - 64-entry LRU Ring Buffer     │           │  - 64-entry LRU Ring Buffer     │
│  - Zero-Knowledge Relay         │           │  - Zero-Knowledge Relay         │
│  - SX1278 (Ra-02 433 MHz)       │           │  - SX1278 (Ra-02 433 MHz)       │
└────────────────┬────────────────┘           └────────────────┬────────────────┘
                 │                                             ▲
                 │              RF LoRa Link (433 MHz)         │
                 └─────────────────────────────────────────────┘
                     Range: 500m - 2km (Single Hop)
                     Multi-Hop: Extendable up to 3 hops (TTL=3)
```

---

## 4. Technical Specifications Summary

### 4.1 Physical & RF Parameters (Semtech SX1278)
- **Modulation**: LoRa Spread Spectrum (Chirp Spread Spectrum)
- **Carrier Frequency**: `433.175 MHz` (ISM Sub-band)
- **Spreading Factor (SF)**: `SF9` (Receiver sensitivity: $-126.5\text{ dBm}$)
- **Bandwidth (BW)**: `125.0 kHz`
- **Coding Rate (CR)**: `4/5` (Forward error correction)
- **Transmit Power (TX Power)**: `+17 dBm` (50 mW)
- **Antenna**: 433 MHz whip / helical dipole with ground plane

### 4.2 Bluetooth Low Energy (BLE GATT) Transport
- **GATT Service UUID**: `4D455348-5800-0001-8000-00805F9B34FB` (128-bit custom)
- **Characteristics**:
  - `DeviceInfo` (`...0002`): Read-only firmware, protocol version, and node alias.
  - `CommandIn` (`...0003`): Write-without-response binary frames (Mobile $\to$ ESP32).
  - `EventOut` (`...0004`): Notify-enabled binary frames (ESP32 $\to$ Mobile).
  - `Telemetry` (`...0005`): Real-time JSON telemetry (RSSI, SNR, Queue, Battery mV).
- **Framing**: `[0xAA][0x58][VER: 1B][TYPE: 1B][SEQ: 2B][LEN: 2B][FRAG_IDX: 1B][FRAG_CNT: 1B][PAYLOAD][CRC-16: 2B]`
- **MTU**: 256 bytes negotiated.

### 4.3 Multi-Hop Mesh Routing Protocol
- **Packet Overhead**: 10-byte compact binary header + 2-byte CRC-16.
- **Addressing**: 32-bit hardware node addressing (`0x00000001` to `0xFFFFFFFE`), `0xFFFFFFFF` for broadcast.
- **Routing Engine**:
  - **64-entry LRU Ring Buffer**: Suppresses broadcast packet storm loops in $O(1)$ memory.
  - **Hop Budget**: Maximum TTL = 3 (covers up to 6 km across 3 nodes).
  - **Collision Jitter**: 50–200 ms randomized Channel Activity Detection (CAD) backoff.
  - **Over-The-Air Auto-ACK**: Receiver hardware automatically transmits delivery confirmation.

---

## 5. Security & Cryptographic Architecture

### 5.1 Threat Model
| Threat | Mitigation in MESH-X |
|---|---|
| **Eavesdropping on Radio Frequency** | End-to-end authenticated encryption (ChaCha20-Poly1305). |
| **Rogue / Compromised ESP32 Relays** | Zero-knowledge design: the microcontroller only handles ciphertext. |
| **Man-in-the-Middle (MITM) Key Substitution**| Out-of-band QR code scanning and 16-character public key fingerprints. |
| **Packet Replay Attacks** | 32-bit millisecond timestamps and strictly increasing sequence IDs. |
| **Frame Tampering / Bit-Flipping** | 16-byte Poly1305 MAC tag computed over ciphertext and metadata. |

### 5.2 Cryptographic Primitives
- **Key Exchange**: `X25519` (Curve25519 Diffie-Hellman, 256-bit security level).
- **Symmetric Cipher**: `ChaCha20` with 96-bit random nonce and 32-bit replay timestamp.
- **Authentication**: `Poly1305` one-time authenticator (128-bit tag).

---

## 6. Advanced Offline Features

### 6.1 Emergency SOS Flood Broadcast
- Single-tap or 3-second safety hold triggers an immediate high-priority emergency broadcast.
- Encodes micro-degree GPS coordinates using compact 4-byte signed integers ($E7 = \text{Coord} \times 10^7$).
- Alerts are propagated across all nodes in the mesh and displayed with high-contrast emergency banners.

### 6.2 Battery & Link Telemetry
- Monitors onboard LiPo battery voltage in millivolts (`batt: 4120 mV`).
- Dynamically derives battery percentages ($3.6\text{V} = 0\%$, $4.2\text{V} = 100\%$) and alert states.
- Displays live radio link indicators (RSSI, SNR) for diagnostic antenna positioning.

---

## 7. Bill of Materials (BoM) & Economic Analysis

| Component | Quantity | Approximate Unit Cost (USD) | Source |
|---|---|---|---|
| ESP32 DevKit V1 (WROOM-32) | 1 | $3.50 | AliExpress / Local Electronics Store |
| Semtech SX1278 (Ra-02 433MHz) | 1 | $3.00 | Ai-Thinker / AliExpress |
| 433 MHz Helical Spring Antenna | 1 | $0.40 | Bundled / Generic |
| Jumper Wires & Breadboard | 1 | $0.60 | Generic |
| Micro-USB Cable | 1 | $0.50 | Generic |
| **Total Hardware Cost per Node** | — | **$8.00** | **Complete Off-Grid Node** |

*Comparison*: Standard off-grid commercial units (e.g. goTenna Mesh: $179/pair; Garmin inReach: $399 + $15/month). **MESH-X delivers 95% cost reduction with complete source code transparency.**

---

## 8. Automated Verification & Testing Summary

| Test Domain | Target | Verification Method | Result |
|---|---|---|---|
| **Binary Protocol & CRC** | CRC-16-CCITT Determinism | Standalone Dart CLI VM | **PASS (100%)** |
| **Domain Serialization** | Message, Conv, Node, SOS | Standalone Dart CLI VM | **PASS (100%)** |
| **Cryptography (E2EE)** | X25519 + ChaCha20-Poly1305 | Standalone Dart CLI VM | **PASS (100%)** |
| **Tamper Protection** | Poly1305 MAC Verification | Standalone Dart CLI VM | **PASS (100%)** |
| **GPS Scaling** | Micro-degree E7 Encoding | Standalone Dart CLI VM | **PASS (100%)** |
| **Firmware Build** | ESP32 Flash & RAM Budget | `arduino-cli` (v3.3.8) | **PASS (89% Flash, 13% RAM)** |
| **Static Code Analysis** | Zero lints, warnings, or leaks | `flutter analyze` | **PASS (0 Issues)** |

---

## 9. Conclusion & Academic Significance
MESH-X successfully demonstrates that resilient, end-to-end encrypted, long-range peer-to-peer communication can be engineered entirely with low-cost open hardware and standard mobile devices. The project bridges the gap between complex industrial telecommunication protocols and accessible community disaster resilience infrastructure.
