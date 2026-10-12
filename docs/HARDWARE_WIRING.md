# MESH-X Hardware Wiring & Electrical Guide

## 1. Pin Mapping Specification

The Semtech SX1278 (AI-Thinker RA-02) communicates with the ESP32 DevKit V1 via the hardware **VSPI** peripheral.

| SX1278 RA-02 Pin | ESP32 DevKit V1 Pin | Pin Function / Description |
|---|---|---|
| **VCC** | **3V3** | **Power Supply (+3.3V DC ONLY). NEVER CONNECT TO 5V!** |
| **GND** | **GND** | Common Ground |
| **SCK** | **GPIO 18** | VSPI Serial Clock |
| **MISO** | **GPIO 19** | VSPI Master In Slave Out |
| **MOSI** | **GPIO 23** | VSPI Master Out Slave In |
| **NSS / CS** | **GPIO 5** | VSPI Chip Select (Active Low) |
| **RESET** | **GPIO 14** | Module Hardware Reset (Active Low) |
| **DIO0** | **GPIO 26** | Packet RX / TX Done Interrupt Line |
| *DIO1–DIO5* | *N/C* | Not Connected (Optional for FSK; unneeded for standard LoRa) |

---

## 2. Critical Safety & Electrical Rules

> [!CAUTION]
> ### 1. Power Supply Voltage Limit
> The SX1278 is rated strictly for **2.4V to 3.7V** (3.3V typical).
> Connecting RA-02 VCC to the ESP32 **VIN or 5V rail will immediately destroy the transceiver IC**.

> [!CAUTION]
> ### 2. Mandatory Antenna Connection
> **NEVER apply power to the ESP32 with firmware transmitting LoRa packets unless an appropriate 433 MHz antenna is securely attached to the RA-02 module.**
> Operating the RF transmitter without an antenna (open load) creates a high Voltage Standing Wave Ratio (VSWR), reflecting power back into the internal Power Amplifier (PA) and permanently burning out the RF frontend.

> [!TIP]
> ### 3. Power Decoupling & Brownout Prevention
> During LoRa packet transmission at maximum power (+17 to +20 dBm), the SX1278 draws brief current surges of **120–130 mA**.
> If your ESP32 brownout detector triggers or reboots during transmission, solder or insert a **100 µF electrolytic capacitor** (in parallel with a 100 nF ceramic capacitor) directly across the RA-02 VCC and GND pins.

---

## 3. Module Frequency Verification

AI-Thinker manufactures several RA series modules that look physically similar:
- **RA-01 / RA-02**: SX1278 chip, **433 MHz band** (410–525 MHz).
- **RA-01H / RA-02H**: SX1276 chip, **868 / 915 MHz band**.

### Verification Steps
1. Inspect the metal shield marking: Confirm it reads **Ai-Thinker RA-02** and shows `433MHz`.
2. Inspect the crystal resonator (visible under shield edge or PCB silk): Should indicate a 32.000 MHz reference.
3. Antenna Matching: Use an antenna tuned specifically for 433 MHz (e.g. 17.3 cm quarter-wave whip, spring coil, or tuned 433 MHz SMA rubber ducky). Using an 868/915 MHz antenna on a 433 MHz module severely limits range and causes impedance mismatch.
