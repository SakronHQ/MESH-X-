# MESH-X: Offline LoRa Mesh Messaging Ecosystem

MESH-X is a decentralized, off-grid mobile communication ecosystem designed to enable resilient text messaging without internet connectivity, cellular networks, SIM cards, or central cloud servers.

---

## 1. High-Level Architecture

The system connects a mobile phone running a custom **Flutter** application to an **ESP32 DevKit V1** hardware node via **Bluetooth Low Energy (BLE)**. The ESP32 formats and packetizes data, transmitting it over long distances using a **Semtech SX1278 (RA-02)** LoRa transceiver (433 MHz band).

```
+-------------------+                 +-------------------+
|  Flutter App A    |                 |  Flutter App B    |
| (Riverpod/SQLite) |                 | (Riverpod/SQLite) |
+---------+---------+                 +---------+---------+
          |                                     ^
          | BLE GATT                            | BLE GATT
          v                                     |
+---------+---------+                 +---------+---------+
|   ESP32 Node A    |                 |   ESP32 Node B    |
|  (Firmware Core)  |                 |  (Firmware Core)  |
+---------+---------+                 +---------+---------+
          |                                     ^
          | SPI                                 | SPI
          v                                     |
+---------+---------+   433 MHz LoRa  +---------+---------+
|  SX1278 Radio A   | ~~~~~~~~~~~~~~~>|  SX1278 Radio B   |
+-------------------+      Air RF     +-------------------+
```

---

## 2. Repository Structure

```
MESH-X/
├── mesh_x_app/           # Flutter mobile application (Android & iOS)
├── mesh_x_firmware/      # C/C++ firmware for ESP32 DevKit V1 + SX1278
├── tools/                # RF airtime and compliance calculation scripts
│   └── airtime_calculator.py
├── docs/                 # Engineering specifications and protocol docs
│   ├── PROJECT_REPORT.md     # Academic-grade defense report & BoM
│   ├── FIELD_TEST_GUIDE.md   # 6-stage field deployment protocol
│   ├── AIRTIME_AUDIT.md      # Semtech ToA & 1% duty cycle compliance audit
│   ├── SYSTEM_ARCHITECTURE.md
│   ├── BLE_PROTOCOL.md
│   ├── RADIO_PROTOCOL.md
│   ├── MESSAGE_FORMAT.md
│   ├── SECURITY_MODEL.md
│   ├── HARDWARE_WIRING.md
│   ├── TEST_PLAN.md
│   └── IMPLEMENTATION_ROADMAP.md
├── PROJECT_PLAN.md       # Real-time project tracking (100% Completed)
├── CHANGELOG.md          # Release history (v1.0.0)
└── README.md             # This document
```

---

## 3. Hardware Requirements

- **Microcontroller**: 2× ESP32 DevKit V1 (30-pin or 36-pin)
- **LoRa Transceiver**: 2× Semtech SX1278 RA-02 (433 MHz)
- **Antennas**: 2× 433 MHz Tuned Antennas (Spring coil or SMA dipole)
- **Cables & Breadboards**: High-quality USB micro data cables, 3.3V logic wiring
- **Mobile Devices**: Android 8.0+ or iOS 13+ devices with Bluetooth 4.2+ support

---

## 4. Hardware Wiring & Connection Diagram

```
+------------------------+             +------------------------+
|    ESP32 DevKit V1     |             |   SX1278 RA-02 (433M)  |
|                        |             |                        |
|                 3V3 ---+------------>| VCC (3.3V ONLY!)       |
|                 GND ---+------------>| GND                    |
|             GPIO 18 ---+------------>| SCK                    |
|             GPIO 19 <--+-------------| MISO                   |
|             GPIO 23 ---+------------>| MOSI                   |
|              GPIO 5 ---+------------>| NSS / CS               |
|             GPIO 14 ---+------------>| RESET                  |
|             GPIO 26 <--+-------------| DIO0                   |
|                        |             |                        |
|                        |             | [Antenna Connected]    |
+------------------------+             +------------------------+
```

### Pin Mapping Table

| SX1278 RA-02 Pin | ESP32 Pin | Function / Description |
|---|---|---|
| **VCC** | **3V3** | **+3.3V DC (DO NOT connect to 5V/VIN!)** |
| **GND** | **GND** | Common Ground |
| **SCK** | **GPIO 18** | VSPI Clock |
| **MISO** | **GPIO 19** | VSPI MISO |
| **MOSI** | **GPIO 23** | VSPI MOSI |
| **NSS / CS** | **GPIO 5** | Chip Select |
| **RESET** | **GPIO 14** | Reset |
| **DIO0** | **GPIO 26** | RX/TX Done Interrupt |

> **CRITICAL**: Always connect a 433 MHz antenna before powering on the ESP32 with radio firmware. Operating without an antenna damages the RF power amplifier.

---

## 5. Quick Start & Prerequisites

- **Flutter**: Version 3.41+ with Dart 3.11+
- **Arduino CLI / ESP32 Core**: `esp32:esp32` v3.3.8+ (bundled with Arduino IDE or standalone)
- **Python**: Version 3.10+

Refer to [docs/HARDWARE_WIRING.md](docs/HARDWARE_WIRING.md) for electrical notes and [docs/IMPLEMENTATION_ROADMAP.md](docs/IMPLEMENTATION_ROADMAP.md) for roadmap details.


