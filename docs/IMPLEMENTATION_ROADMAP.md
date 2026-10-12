# MESH-X Implementation Roadmap (Phases 0–8)

This roadmap defines the sequential, gated path from initial discovery to a production-ready offline mesh ecosystem.

---

## Phase 0: Discovery, Architecture & Specifications *(CURRENT)*
- **Objective**: Establish toolchains, directory boundaries, protocol specifications, risk matrix, and ADRs.
- **Deliverables**:
  - `README.md`, `PROJECT_PLAN.md`, `CHANGELOG.md`
  - Specification suite in `docs/` (`SYSTEM_ARCHITECTURE.md`, `BLE_PROTOCOL.md`, `RADIO_PROTOCOL.md`, `MESSAGE_FORMAT.md`, `SECURITY_MODEL.md`, `HARDWARE_WIRING.md`, `TEST_PLAN.md`)
- **Exit Gate**: Explicit user review and sign-off.

---

## Phase 1: Hardware Radio Prototype
- **Objective**: Verify physical SPI wiring between ESP32 and SX1278 RA-02; validate 433 MHz RF transmit and receive capabilities.
- **Deliverables**:
  - ESP32 radio driver implementation using `RadioLib` or dedicated SX127x SPI driver.
  - Interactive test firmware: `test_radio_tx.ino` and `test_radio_rx.ino` / bidirectional ping-pong sketch.
  - Verification of register `0x42` (chip version), RSSI, SNR, and packet loss metrics.
- **Exit Gate**: Successful transmission and reception of at least 10 consecutive packets between the two hardware nodes.

---

## Phase 2: ESP32 BLE Transport Layer
- **Objective**: Build the BLE GATT server on ESP32 implementing the custom MESH-X service and characteristics.
- **Deliverables**:
  - BLE GATT service implementation with custom 128-bit UUIDs.
  - Command framing parser and Event Out notification publisher.
  - Disconnect handling, queue reset, and MTU negotiation support.
  - Bench test via standard BLE tool or script.
- **Exit Gate**: Reliable bidirectional exchange of framed command and event packets over BLE.

---

## Phase 3: Flutter Application Foundation
- **Objective**: Initialize the Flutter mobile client with Riverpod state architecture and BLE connection manager.
- **Deliverables**:
  - Clean Flutter project initialized in `mesh_x_app/`.
  - Dark-first design system with Hallmark token architecture.
  - BLE Scanner screen, connection state manager, and automatic reconnect with exponential backoff.
  - Device Diagnostics dashboard displaying real node metadata.
- **Exit Gate**: Mobile application successfully scans, connects, handshakes, and reads device telemetry from the physical ESP32.

---

## Phase 4: Direct Messaging MVP
- **Objective**: Achieve complete end-to-end direct text messaging: Phone A → ESP32 A → LoRa 433MHz → ESP32 B → Phone B.
- **Deliverables**:
  - SQLite database integration for conversation and message persistence.
  - Chat list view, conversation view, and message composer.
  - Message delivery lifecycle tracking (`QUEUED` → `TRANSMITTED` → `DELIVERED`).
  - Outbound retry handling for dropped packets.
- **Exit Gate**: Two physical smartphones exchange text messages over the air with correct delivery state transitions and local offline persistence.

---

## Phase 5: Multi-Hop Mesh Routing
- **Objective**: Extend communication beyond direct radio range through autonomous intermediate packet forwarding.
- **Deliverables**:
  - Firmware packet forwarding logic with TTL decrementing and loop prevention.
  - Rolling LRU ring buffer for duplicate suppression.
  - Randomized relay jitter and CAD collision mitigation.
  - Mesh network topology screen in the Flutter client.
- **Exit Gate**: Messages successfully reach destination node across an intermediate relay node with verified hop incrementation.

---

## Phase 6: Security & End-to-End Cryptography
- **Objective**: Protect private communications against eavesdropping, spoofing, and replay attacks.
- **Deliverables**:
  - Client-side key generation (X25519) and secure storage in Android Keystore / iOS Keychain.
  - ChaCha20-Poly1305 authenticated payload encryption.
  - Out-of-band contact public key exchange (QR code sharing).
  - Anti-replay timestamp and sequence validation.
- **Exit Gate**: Over-the-air packet payloads are cryptographically secure; modified or replayed packets are rejected.

---

## Phase 7: Advanced Features
- **Objective**: Expand capability for emergency and field operations.
- **Deliverables**:
  - Broadcast SOS composer with explicit user confirmation and countdown safety.
  - GPS coordinate attachment (using device location services when authorized).
  - Contact management, alias editing, and favorite nodes.
  - Battery voltage and radio health telemetry gauges.
- **Exit Gate**: Functional SOS broadcasts received by all peer nodes in the mesh.

---

## Phase 8: Hardening & Release Preparation
- **Objective**: Finalize quality assurance, airtime compliance, and platform builds.
- **Deliverables**:
  - Comprehensive static analysis and automated test passes.
  - Android APK and iOS archive build recipes.
  - Power consumption profiling and airtime duty-cycle audit.
  - Complete user operation guide and hardware troubleshooting manual.
- **Exit Gate**: Production-ready, deployable offline communication ecosystem.
