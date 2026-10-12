# Changelog

All notable changes to the MESH-X project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8.0-phase7] - 2026-10-12
### Added
- Integrated `geolocator` for satellite GPS location acquisition in offline distress beacons.
- Created `SosAlertModel` with micro-degree E7 coordinates encoding, validation, and location helpers.
- Added `CMD_SUBMIT_SOS` (`0x14`), `OTA_PKT_SOS` (`0x04`), and `OTA_FLAG_SOS` (`0x08`) to ESP32 firmware.
- Added real-time LiPo battery voltage (`batteryMv`) monitoring to firmware telemetry JSON.
- Built `SosComposerDialog` with emergency category presets, live GPS satellite coordinate acquisition, and a 3-second hold-to-send safety trigger.
- Built `SosAlertBanner` featuring glowing emergency indicators, sender node ID, distress text, GPS coordinates copying, and dismiss trigger.
- Added emergency beacon action button to `ConversationListScreen` AppBar and dynamic SOS alert banner.
- Updated `TelemetryCard` and `DeviceDashboardScreen` with a battery gauge (voltage and percentage calculation) and transmission queue depth.
- Recompiled ESP32 firmware with `arduino-cli` (Exit code: 0, 89% flash, 13% RAM).
- Passed `flutter analyze` (0 issues) and expanded unit test suite to 14/14 passing tests (`dart test`).

## [0.7.0-phase6] - 2026-10-12
### Added
- Integrated `cryptography` and `qr_flutter` libraries for end-to-end encryption.
- Built `CryptoService` providing X25519 (Curve25519) keypair generation, public fingerprint formatting, and pluggable key storage.
- Implemented authenticated symmetric payload encryption with ChaCha20-Poly1305 AEAD and replay-protection timestamp headers.
- Updated ESP32 firmware (`mesh_x_ble.h` and `main.ino`) to pass raw encrypted wire payloads and packet flags (`OTA_FLAG_ENCRYPTED = 0x02`).
- Recompiled firmware with `arduino-cli` (Exit code: 0, 89% flash, 13% RAM).
- Upgraded SQLite database to version 3 adding `public_key` and `is_verified` to `nodes`, and `is_encrypted` to `messages`.
- Updated `ChatRepository` to automatically encrypt outbound messages when peer public key is known, and authenticate & decrypt inbound frames.
- Built `KeyExchangeDialog` featuring QR code sharing, fingerprint display, key copying, and contact public key activation.
- Added real-time E2EE status indicators in `ChatConversationScreen` and `MeshNodesScreen`.
- Passed `flutter analyze` (0 issues) and expanded unit test suite to 11/11 passing tests (`dart test`).

## [0.6.0-phase5] - 2026-10-12
### Added
- Implemented `MeshRouter` inline C++ header with a 64-entry LRU ring buffer for duplicate packet suppression and neighbor table tracking.
- Added `sendNodeDiscovered` event (`EVT_NODE_DISCOVERED` `0x84`) to `MeshXBLE` GATT server.
- Integrated autonomous multi-hop mesh forwarding in `mesh_x_firmware/main/main.ino` with TTL decrementing, hop count tracking, and randomized collision-avoidance jitter (50–200ms).
- Added periodic background presence broadcasting (`OTA_PKT_NODE_ANNOUNCE` every 60s) to discover neighbor nodes autonomously.
- Verified firmware compilation with `arduino-cli` (Exit code: 0, 89% flash, 13% RAM).
- Added SQLite `nodes` table and version 2 database migration in Flutter app.
- Created `MeshNodeModel` and `discoveredNodesProvider` for reactive mesh state.
- Built Hallmark-designed `MeshNodesScreen` displaying active topology metrics, direct vs relayed indicators, signal metrics (RSSI/SNR), relative timestamps, and one-tap direct chat.
- Added "Mesh Nodes" hub to `HomeNavigationScreen` bottom navigation bar.
- Passed `flutter analyze` (0 issues) and expanded unit test suite to 9/9 passing tests (`dart test`).

## [0.5.0-phase4] - 2026-10-12
### Added
- Integrated local SQLite database (`sqflite`) for offline-first message and conversation storage.
- Implemented `MessageModel` and `ConversationModel` with strict delivery lifecycle (`QUEUED`, `TRANSMITTED`, `DELIVERED`, `FAILED`).
- Created `ChatRepository` managing SQLite persistence, BLE command packing, and asynchronous event notifications.
- Built `ConversationListScreen` with broadcast hub and direct peer conversation creator.
- Built `ChatConversationScreen` with message bubbles, timestamps, delivery state ticks, retry action, and 180-character limit counter.
- Implemented integrated ESP32 firmware bridge `mesh_x_firmware/main/main.ino` combining BLE GATT Server with SX1278 LoRa transceiver and over-the-air auto-ACK replies.
- Compiled firmware with `arduino-cli` (Exit code: 0).
- Passed `flutter analyze` (0 issues) and `dart test` (6/6 tests passed).

## [0.4.0-phase3] - 2026-10-12
### Added
- Initialized Flutter mobile application architecture in `mesh_x_app/` with Riverpod 3 (`NotifierProvider`).
- Added Hallmark modern dark theme design system (`AppColors`, `AppTheme`) with electric cyan accents and 44x44px touch targets.
- Created `BleRepository` with MTU 256 negotiation, binary framing, and CRC-16-CCITT packet validation.
- Built `BleController` for reactive connection state management, scanning, and automatic reconnection.
- Built `DeviceScannerScreen` with live RSSI signal indicators and node discovery.
- Built `DeviceDashboardScreen` with hardware telemetry monitoring (RSSI, SNR, Uptime) and BLE link Ping.
- Configured Android BLE permissions in `AndroidManifest.xml`.
- Verified clean static analysis (`flutter analyze` - 0 issues) and passing unit test suite (`dart test` - 4/4 passed).

## [0.3.0-phase2] - 2026-10-12
### Added
- Created `mesh_x_firmware/src/mesh_x_protocol.h` defining 128-bit custom MESH-X GATT UUIDs, binary frame header, and CRC-16-CCITT algorithm.
- Implemented modular `MeshXBLE` class in `mesh_x_firmware/src/mesh_x_ble.h` supporting Device Info, Command In, Event Out, and Telemetry characteristics.
- Added command validation, binary CRC checking, command ACKs, and ping-pong responsiveness.
- Created `mesh_x_firmware/test/ble_transport_test/ble_transport_test.ino` for end-to-end BLE transport testing.
- Verified successful firmware compilation for `esp32:esp32:esp32doit-devkit-v1` with `arduino-cli`.

## [0.2.0-phase1] - 2026-10-12
### Added
- Integrated `RadioLib@7.8.1` for SX1278 transceiver communication.
- Hardware configuration header `mesh_x_firmware/src/mesh_x_config.h` with VSPI pin assignments and 433 MHz RF parameters.
- Dual-role radio prototype sketch `mesh_x_firmware/test/radio_ping_pong/radio_ping_pong.ino` supporting dynamic Initiator/Responder mode switching and RegVersion (0x12) hardware diagnostic checks.
- Verified successful firmware compilation for `esp32:esp32:esp32doit-devkit-v1` via `arduino-cli`.

## [0.1.0-phase0] - 2026-10-12
### Added
- Phase 0 discovery, toolchain audit, and environment inspection (`Flutter 3.41.1`, `Dart 3.11.0`, `arduino-cli 1.4.1`, `ESP32 core 3.3.8`).
- Root workspace separation: `mesh_x_app/`, `mesh_x_firmware/`, `docs/`.
- System architecture specification (`docs/SYSTEM_ARCHITECTURE.md`).
- BLE GATT protocol definition and UUID specifications (`docs/BLE_PROTOCOL.md`).
- LoRa physical parameters and over-the-air packet format (`docs/RADIO_PROTOCOL.md`).
- Message data format, schemas, and state machine (`docs/MESSAGE_FORMAT.md`).
- Threat model and cryptographic roadmap (`docs/SECURITY_MODEL.md`).
- Hardware wiring table, electrical safety rules, and antenna warnings (`docs/HARDWARE_WIRING.md`).
- Quality gates and verification test plan (`docs/TEST_PLAN.md`).
- Master implementation roadmap (`docs/IMPLEMENTATION_ROADMAP.md`).
- Master `PROJECT_PLAN.md` and initial changelog.
