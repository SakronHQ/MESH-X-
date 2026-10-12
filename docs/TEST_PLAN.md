# MESH-X Verification & Test Plan

## 1. Overview
The MESH-X Test Plan enforces rigorous quality gates at each phase boundary. Code is never promoted to the next milestone without passing measurable acceptance criteria.

---

## 2. Quality Gates by Phase

### Phase 0: Discovery & Architecture Gate
- [x] Host environment validated (`flutter`, `dart`, `arduino-cli`, `esp32 core`).
- [x] Workspace structure verified (`mesh_x_app`, `mesh_x_firmware`, `docs`).
- [x] Protocol specifications locked with stable 128-bit UUIDs and binary framing.
- [ ] User approval received before source code generation.

### Phase 1: Hardware Radio Gate
- **Tool**: `arduino-cli compile --fqbn esp32:esp32:esp32doit-devkit-v1`
- **Criteria**:
  - SX1278 SPI registers readable (Version register `0x42` returns expected silicon revision `0x12`).
  - Node A transmits 10 ping packets; Node B receives at least 9 (packet loss <= 10% on bench).
  - RSSI and SNR values captured and displayed on serial monitor (115200 baud).

### Phase 2: BLE GATT Transport Gate
- **Criteria**:
  - ESP32 advertises MESH-X primary service UUID `4D455348-5800-0001-8000-00805F9B34FB`.
  - BLE test client reads Device Info characteristic successfully.
  - Submitting `CMD_PING` (`0x11`) via Command In triggers `EVT_PONG` (`0x83`) notification within 150 ms.
  - Link disconnection triggers graceful state reset on ESP32 without memory leakage.

### Phase 3: Flutter App Foundation Gate
- **Commands**:
  - `flutter analyze` passes with zero errors and zero warnings.
  - `flutter test` passes unit tests for state providers, framing parsers, and SQLite schema migrations.
- **Criteria**:
  - Device scanner discovers nearby MESH-X ESP32 nodes and displays accurate RSSI.
  - Successful BLE connection completes handshake and renders Device Dashboard with real hardware status.
  - Background disconnect/reconnect simulation succeeds without UI freeze.

### Phase 4: Direct Messaging MVP Gate
- **Criteria**:
  - End-to-end communication verified: Mobile A → Node A → LoRa → Node B → Mobile B.
  - Outbound message transitions: `QUEUED` → `TRANSMITTED` → `DELIVERED` within 1.5 seconds.
  - Message persists across Flutter application kill and relaunch.
  - Simulated radio packet drop triggers `FAILED` state and provides functional manual retry.

### Phase 5: Mesh Routing Gate
- **Criteria**:
  - Node A and Node C placed out of direct RF line-of-sight.
  - Intermediate Node B receives packet, decrements TTL from 3 to 2, and forwards.
  - Node C receives message and transmits ACK along the reverse route.
  - Duplicate packets received by intermediate nodes are suppressed.

### Phase 6: Security Hardening Gate
- **Criteria**:
  - Encrypted packets captured over the air reveal zero plaintext UTF-8 leakage.
  - Tampered ciphertext payload triggers authentication tag verification failure and is dropped.
  - Replayed packet with stale timestamp is discarded by receiver.

---

## 3. Automated Test Commands

### 3.1 Mobile App Static Analysis & Tests
```powershell
cd "d:\Uni Project\MESH-X\mesh_x_app"
flutter analyze
flutter test
```

### 3.2 Firmware Build Verification
```powershell
& "C:\Users\MRX\AppData\Local\Programs\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe" compile --fqbn esp32:esp32:esp32doit-devkit-v1 "d:\Uni Project\MESH-X\mesh_x_firmware\test\radio_ping_pong"
```
