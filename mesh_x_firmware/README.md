# MESH-X ESP32 Firmware

This directory contains the C/C++ firmware for ESP32 DevKit V1 microcontrollers interfacing with Semtech SX1278 RA-02 LoRa modules.

## Target Hardware
- **MCU**: ESP32 DevKit V1 (ESP-WROOM-32)
- **Radio**: Semtech SX1278 (AI-Thinker RA-02, 433 MHz)
- **SPI Interface**: VSPI (SCK 18, MISO 19, MOSI 23, CS 5, RST 14, DIO0 26)

## Toolchain & Build Environment
- **Core**: `esp32:esp32` (v3.3.8)
- **CLI**: `arduino-cli` 1.4.1 (or Arduino IDE 2.x)

```powershell
# Example compile command:
& "C:\Users\MRX\AppData\Local\Programs\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe" compile --fqbn esp32:esp32:esp32doit-devkit-v1 <sketch_path>
```

Implementation will commence in **Phase 1: Hardware Radio Prototype**.
Do not place Flutter Dart source files inside this directory.
