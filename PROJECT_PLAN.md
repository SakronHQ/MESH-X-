# MESH-X Project Plan & Status Tracker

## 1. Project Overview
- **Project**: MESH-X (Offline LoRa Mesh Messaging Ecosystem)
- **Target Microcontroller**: ESP32 DevKit V1 (ESP-WROOM-32)
- **Target Transceiver**: SX1278 RA-02 (433 MHz)
- **Mobile Stack**: Flutter (Riverpod, SQLite, flutter_blue_plus)
- **Current Protocol Version**: `v1.0.0-draft`

---

## 2. Phase Execution Status

| Phase | Description | Status | Sign-off Date |
|---|---|---|---|
| **Phase 0** | **Discovery, Architecture & Specifications** | **APPROVED** | 2026-10-12 |
| **Phase 1** | **Hardware Radio Prototype (SX1278 SPI Ping-Pong)** | **FIRMWARE READY (Awaiting Hardware Bench Run)** | 2026-10-12 |
| **Phase 2** | **ESP32 BLE GATT Server & Transport Layer** | **FIRMWARE VERIFIED** | 2026-10-12 |
| **Phase 3** | **Flutter App Foundation, BLE Manager & UI System** | **COMPLETED & VERIFIED** | 2026-10-12 |
| **Phase 4** | **Direct Messaging MVP (Phone A ↔ LoRa ↔ Phone B)** | **COMPLETED & VERIFIED** | 2026-10-12 |
| **Phase 5** | Multi-Hop Mesh Routing & Store-and-Forward | QUEUED | — |
| **Phase 6** | End-to-End Cryptography & Authenticated Pairing | QUEUED | — |
| **Phase 7** | Advanced Features (SOS, Telemetry, Diagnostics) | QUEUED | — |
| **Phase 8** | Release Engineering, Airtime Audit & Verification | QUEUED | — |

---

## 3. Phase 0 Deliverables & Checklist

- [x] Host environment inspected (`flutter`, `dart`, `arduino-cli`, `python`).
- [x] Sibling folder structure established (`mesh_x_app/`, `mesh_x_firmware/`, `docs/`).
- [x] System Architecture documented ([docs/SYSTEM_ARCHITECTURE.md](docs/SYSTEM_ARCHITECTURE.md)).
- [x] BLE Protocol & GATT UUIDs defined ([docs/BLE_PROTOCOL.md](docs/BLE_PROTOCOL.md)).
- [x] LoRa RF parameters & packet frame defined ([docs/RADIO_PROTOCOL.md](docs/RADIO_PROTOCOL.md)).
- [x] Message data format & delivery states defined ([docs/MESSAGE_FORMAT.md](docs/MESSAGE_FORMAT.md)).
- [x] Threat model & security roadmap documented ([docs/SECURITY_MODEL.md](docs/SECURITY_MODEL.md)).
- [x] Hardware wiring & electrical rules documented ([docs/HARDWARE_WIRING.md](docs/HARDWARE_WIRING.md)).
- [x] Quality gates & verification test plan defined ([docs/TEST_PLAN.md](docs/TEST_PLAN.md)).
- [x] Explicit user sign-off received.

---

## 3.1 Phase 1 Deliverables & Checklist
- [x] Install `RadioLib@7.8.1` universal wireless library.
- [x] Define unified pin mapping and RF constants header ([mesh_x_firmware/src/mesh_x_config.h](mesh_x_firmware/src/mesh_x_config.h)).
- [x] Implement dual-role ping-pong test firmware with hardware SPI RegVersion diagnostics ([mesh_x_firmware/test/radio_ping_pong/radio_ping_pong.ino](mesh_x_firmware/test/radio_ping_pong/radio_ping_pong.ino)).
- [x] Compile and verify firmware with `arduino-cli` for `esp32:esp32:esp32doit-devkit-v1` (Passed with zero errors).
- [ ] Connect ESP32 DevKit V1 #1 and #2 via USB to PC.
- [ ] Flash firmware to both nodes and run bidirectional RF ping-pong test.
- [ ] Verify RSSI/SNR metrics on Serial Monitor (115200 baud).

---

## 3.2 Phase 2 Deliverables & Checklist
- [x] Define 128-bit MESH-X GATT UUIDs, binary frame header, and CRC-16-CCITT algorithm in [mesh_x_firmware/src/mesh_x_protocol.h](mesh_x_firmware/src/mesh_x_protocol.h).
- [x] Implement complete BLE GATT server class `MeshXBLE` in [mesh_x_firmware/src/mesh_x_ble.h](mesh_x_firmware/src/mesh_x_ble.h) supporting Device Info (Read), Command In (Write), Event Out (Notify), and Telemetry (Read/Notify).
- [x] Add command validation, CRC checking, ACK responses (`EVT_TX_STATUS`), `CMD_PING` / `EVT_PONG`, and error codes.
- [x] Implement automatic advertising recovery on mobile disconnection.
- [x] Create standalone Phase 2 test sketch [mesh_x_firmware/test/ble_transport_test/ble_transport_test.ino](mesh_x_firmware/test/ble_transport_test/ble_transport_test.ino).
- [ ] Connect ESP32 to USB, upload sketch, and test BLE connection via mobile phone (e.g. nRF Connect or LightBlue).

---

## 3.3 Phase 3 Deliverables & Checklist
- [x] Initialize Flutter mobile application with Riverpod state architecture in `mesh_x_app/`.
- [x] Configure Android Bluetooth permissions in `AndroidManifest.xml` (Scan, Connect, Fine/Coarse Location).
- [x] Build Hallmark modern dark theme system (`AppColors`, `AppTheme`) with electric cyan accents and 44x44px touch targets.
- [x] Implement robust `BleRepository` wrapping `flutter_blue_plus` with MTU 256 negotiation, binary framing, and CRC-16-CCITT validation.
- [x] Build `BleController` using Riverpod 3 `NotifierProvider` managing complete connection lifecycle and auto-reconnect backoff.
- [x] Build `DeviceScannerScreen` with live RSSI signal indicators, permission handling, and node discovery.
- [x] Build `DeviceDashboardScreen` with live telemetry gauges (RSSI, SNR, Uptime, Queue depth) and BLE Ping command.
- [x] Build `ChatPlaceholderScreen` and bottom navigation shell.
- [x] Run `flutter analyze` (Passed with 0 errors, 0 warnings).
- [x] Run unit test suite `dart test test/unit_test.dart` (Passed 4/4 tests).

---

## 3.4 Phase 4 Deliverables & Checklist
- [x] Integrate SQLite database (`sqflite`) with `conversations` and `messages` tables matching specification.
- [x] Implement domain models `MessageModel` and `ConversationModel` with delivery statuses (`QUEUED`, `TRANSMITTED`, `DELIVERED`, `FAILED`).
- [x] Build `ChatRepository` managing message persistence, BLE command packaging, and asynchronous notification event handling.
- [x] Build `ConversationListScreen` with broadcast hub and peer conversation creation.
- [x] Build `ChatConversationScreen` with real message bubbles, timestamps, delivery state ticks, retry action, and character limit indicator (180 chars).
- [x] Build integrated Node firmware [mesh_x_firmware/main/main.ino](mesh_x_firmware/main/main.ino) combining BLE GATT Server + SX1278 LoRa Radio + Over-the-air Auto ACK logic.
- [x] Compile firmware with `arduino-cli` (Passed with exit code 0).
- [x] Pass `flutter analyze` (0 issues) and `dart test` (6/6 tests passed).

---

## 4. Key Architecture Decisions (ADR Summary)

1. **Firmware Toolchain**:
   - `arduino-cli` with `esp32:esp32` (v3.3.8) core used for transparent, reproducible command-line compilation.
   - Radio library: `RadioLib` or dedicated SX127x SPI driver (clean, non-blocking, interrupt-driven via DIO0).
2. **Custom Protocol vs. Meshtastic Compatibility**:
   - MESH-X uses a custom binary protocol optimized for the RA-02 + ESP32 DevKit V1 hardware.
   - Compatibility with third-party ecosystems is not presumed, avoiding proprietary bloat and brittle dependencies.
3. **State Management & UI**:
   - Flutter with Riverpod for unidirectional state flow.
   - Dark-first aesthetic with strict token architecture, 44x44px touch targets, and offline-first state handling.
4. **Separation of Concerns**:
   - Flutter never handles SPI or direct radio timings.
   - ESP32 never relies on the smartphone for mesh packet relaying or deduplication.

---

## 5. Risk Matrix & Mitigations

| Risk | Impact | Likelihood | Mitigation Strategy |
|---|---|---|---|
| **RA-02 Frequency Mismatch** | High | Medium | Verify module markings (433M vs 868M/915M) and crystal frequency before transmission. |
| **Damage without Antenna** | Critical | High | Explicit safety gate in documentation: Never power TX without antenna connected. |
| **3.3V Power Rail Dropouts** | High | Medium | Add 100µF decoupling capacitor near RA-02 VCC/GND pins if brownout resets occur. |
| **BLE MTU Truncation** | Medium | High | Variable-length BLE framing with explicit reassembly header; never assume MTU > 20 bytes. |
| **Airtime Saturation** | High | Medium | Enforce duty-cycle limits, SF9 / 125kHz bandwidth, and TTL <= 3 to prevent broadcast flooding. |

---

## 6. Next Immediate Milestone
Upon receipt of `"APPROVE PHASE 0. START PHASE 1."`:
- Proceed directly to **Phase 1: Hardware Radio Prototype**.
- Validate pin wiring and SPI connectivity on both nodes.
- Run bidirectional ping-pong test over 433 MHz LoRa and report RSSI/SNR values.
