# MESH-X Field Testing & Hardware Deployment Guide

## 1. Required Hardware Checklist (Bill of Materials)

To deploy and test an operational 2-node or 3-node MESH-X mesh network, prepare the following components:

| Item | Quantity (Per Node) | Purpose |
|---|---|---|
| **ESP32 DevKit V1** (WROOM-32, 30 or 38 Pin) | 1 | Microcontroller running BLE GATT server and Mesh Router |
| **SX1278 (Ra-02) 433 MHz Module** | 1 | Semtech LoRa spread-spectrum transceiver |
| **433 MHz Antenna** (Whip, Helical, or SMA) | 1 | **MANDATORY**: Never power transceiver without antenna! |
| **Micro-USB Cable** or **3.7V LiPo + TP4056** | 1 | Power supply (5V via USB or 3.7V regulated to 3.3V) |
| **DuPont Jumper Wires** (Female-to-Female) | 7 | SPI and GPIO connections |
| **Android Smartphone** (Android 8.0+, BLE 4.2+) | 1 (per user) | Runs MESH-X Flutter mobile application |

---

## 2. Hardware Wiring Quick Reference

Connect the ESP32 DevKit V1 to the SX1278 RA-02 module according to the following standard SPI pinout:

```
  ESP32 DevKit V1               SX1278 RA-02 (433 MHz)
 ┌────────────────┐            ┌──────────────────────┐
 │           3.3V ├────────────┤ VCC (3.3V ONLY!)     │
 │            GND ├────────────┤ GND                  │
 │          GPIO5 ├────────────┤ NSS / CS (Chip Select│
 │         GPIO18 ├────────────┤ SCK (SPI Clock)      │
 │         GPIO19 ├────────────┤ MISO (Master In)     │
 │         GPIO23 ├────────────┤ MOSI (Master Out)    │
 │         GPIO14 ├────────────┤ RST (Reset)          │
 │          GPIO2 ├────────────┤ DIO0 (Interrupt)     │
 └────────────────┘            └──────────────────────┘
```

> [!CAUTION]
> **ELECTRICAL WARNINGS**:
> 1. **Antenna Requirement**: Always attach a 433 MHz antenna before powering the ESP32. Transmitting without an antenna can reflect RF energy back into the power amplifier, causing permanent silicon damage.
> 2. **3.3V Power Line**: Connect RA-02 VCC strictly to the **3.3V** pin. Connecting to 5V (VIN) will destroy the SX1278 transceiver.
> 3. **Decoupling**: If experiencing brownout resets during transmission, solder a 100µF electrolytic capacitor across the 3.3V and GND pins near the module.

---

## 3. Firmware Flashing Instructions

The MESH-X firmware automatically provisions unique Node IDs by reading the hardware eFuse MAC address (`ESP.getEfuseMac()`). You can flash the exact same binary to every ESP32 node without modifying a single line of source code!

### Method A: Flashing via `arduino-cli` (Command Line)
1. Connect your ESP32 to your PC via USB.
2. Find the COM port (e.g. `COM3` on Windows or `/dev/ttyUSB0` on Linux):
   ```powershell
   arduino-cli board list
   ```
3. Compile and upload:
   ```powershell
   arduino-cli compile --fqbn esp32:esp32:esp32doit-devkit-v1 "mesh_x_firmware/main"
   arduino-cli upload -p COM3 --fqbn esp32:esp32:esp32doit-devkit-v1 "mesh_x_firmware/main"
   ```

### Method B: Flashing via Arduino IDE
1. Open `mesh_x_firmware/main/main.ino` in Arduino IDE.
2. Select Board: **DOIT ESP32 DEVKIT V1**.
3. Select your serial COM port.
4. Click **Upload** (or Ctrl+U).
5. Open Serial Monitor at **115200 baud**. You should observe the boot banner:
   ```text
   ========================================================
          MESH-X NODE FIRMWARE (Phase 5 Mesh Router)       
   ========================================================
   Local Node ID    : 0xA1B2C3D4 (MESH-X-B2C3D4)
   LoRa Frequency   : 433.175 MHz (SF9, BW 125.0kHz)
   [INIT] SX1278 LoRa transceiver initialized successfully.
   [BLE] Advertising started. Waiting for mobile app connection.
   ```

---

## 4. Mobile Application Installation

1. Connect your Android phone via USB with USB Debugging enabled.
2. Run in release mode:
   ```powershell
   flutter run --release
   ```
   Or install the built APK:
   ```powershell
   flutter build apk --release
   adb install build/app/outputs/flutter-apk/app-release.apk
   ```
3. Launch **MESH-X** on the phone. Grant Bluetooth and Location permissions when prompted.

---

## 5. Five-Stage Field Testing Protocol

### Stage 1: Benchtop Near-Field Verification (Distance: 1–3 Meters)
- **Goal**: Confirm BLE GATT handshake, bidirectional LoRa communication, and OTA delivery ACKs.
- **Procedure**:
  1. Turn on Node A and Node B on the workbench.
  2. Pair Phone A with Node A, and Phone B with Node B via the "Hardware Node" tab.
  3. Send a text message from Phone A to Phone B's Node ID.
- **Pass Criteria**:
  - Message status transitions: `QUEUED` $\to$ `TRANSMITTED` $\to$ `DELIVERED` (double checkmark).
  - RSSI on received packet: $-40\text{ to } -65\text{ dBm}$.

### Stage 2: Indoor Penetration Test (Distance: 20–50 Meters, Through 2–3 Concrete Walls)
- **Goal**: Measure 433 MHz RF penetration inside modern residential/academic buildings.
- **Procedure**:
  1. Leave Node A inside a laboratory or room.
  2. Carry Node B down hallways and behind two concrete/brick walls.
  3. Send 10 consecutive messages of 50 characters each.
- **Pass Criteria**:
  - Packet delivery rate: $\ge 90\%$.
  - Expected RSSI: $-85\text{ to } -105\text{ dBm}$; SNR: $+2\text{ to } +8\text{ dB}$.

### Stage 3: Outdoor Line-of-Sight (LoS) Range Test (Distance: 500m – 2km)
- **Goal**: Validate maximum single-hop radio range in open air.
- **Procedure**:
  1. Position Node A on an elevated location (e.g. 2nd-floor balcony or rooftop).
  2. Walk Node B along a direct line-of-sight path outdoors.
  3. Send test pings at 250m, 500m, 1km, and 1.5km.
- **Pass Criteria**:
  - Successful bidirectional delivery at $\ge 1\text{ km}$ under direct LoS.
  - Expected RSSI at 1 km: $-110\text{ to } -122\text{ dBm}$; SNR: $-4\text{ to } -8\text{ dB}$.

### Stage 4: Multi-Hop Mesh Relay Test (3 Nodes)
- **Goal**: Verify autonomous packet forwarding with TTL decrementing and loop suppression.
- **Setup**:
  - Node A (Sender) $\leftrightarrow$ Node B (Relay) $\leftrightarrow$ Node C (Receiver).
  - Place Node A and Node C so far apart that they cannot hear each other directly ($\text{RSSI} < -127\text{ dBm}$). Place Node B in the middle.
- **Procedure**:
  1. Send a direct message from Phone A addressed to Node C.
- **Pass Criteria**:
  - Node B forwards the packet (Hop Count = 1, TTL = 2).
  - Phone C receives the message from Node A with indicator `Hops: 2`.
  - Serial monitor on Node B confirms: `[ROUTER] Relaying packet 0x...`.

### Stage 5: End-to-End Cryptography & Tamper Test
- **Goal**: Verify ChaCha20-Poly1305 zero-knowledge authenticated encryption.
- **Procedure**:
  1. Scan Bob's public key QR code on Alice's device.
  2. Send an encrypted message from Alice to Bob.
- **Pass Criteria**:
  - Node A and Node B serial logs show only encrypted binary ciphertext.
  - Bob's app displays the message with the green padlock icon `🔒 E2EE Verified`.
  - If any packet bit is modified in transit, the message is rejected with a MAC failure warning.

### Stage 6: Emergency SOS Flood Broadcast Test
- **Goal**: Verify emergency distress broadcasting and GPS coordinate telemetry.
- **Procedure**:
  1. On Phone A, press the emergency SOS beacon in the app bar.
  2. Select "Medical Emergency", allow GPS acquisition, and hold the trigger for 3 seconds.
- **Pass Criteria**:
  - All nodes in the mesh receive the flood broadcast regardless of address.
  - High-contrast red `SosAlertBanner` appears immediately on Phone B and Phone C displaying GPS coordinates and sender Node ID.

---

## 6. Signal Quality Reference Guide

Use the RSSI and SNR values shown on the MESH-X screen to diagnose radio links:

| Link Quality | RSSI (dBm) | SNR (dB) | Status & Behavior |
|---|---|---|---|
| **Excellent** | $> -80$ | $> +8$ | Ultra-low packet error rate; instantaneous delivery. |
| **Good** | $-80\text{ to } -100$ | $+2\text{ to } +8$ | Reliable communication through walls and foliage. |
| **Fair** | $-100\text{ to } -115$ | $-3\text{ to } +2$ | Occasional packet loss; auto-retry mechanism may engage. |
| **Marginal** | $-115\text{ to } -124$ | $-8\text{ to } -3$ | Maximum single-hop range; keep antennas strictly vertical. |
| **Link Down** | $< -125$ | $< -12.5$ | Out of range; reposition node or insert an intermediate relay node. |
