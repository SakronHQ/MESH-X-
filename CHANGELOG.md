# Changelog

All notable changes to the MESH-X project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
