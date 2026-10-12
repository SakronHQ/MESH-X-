/**
 * MESH-X Phase 1: Hardware Radio Prototype Test
 * Target Hardware: ESP32 DevKit V1 + SX1278 RA-02 (433 MHz)
 * 
 * Instructions:
 * 1. Connect ESP32 DevKit V1 to SX1278 RA-02 following docs/HARDWARE_WIRING.md.
 * 2. Connect 433 MHz antenna before powering.
 * 3. Open Serial Monitor at 115200 baud.
 * 4. This sketch runs on BOTH nodes!
 *    - By default, Node boots in RESPONDER mode (listens for pings and replies with pong).
 *    - To make a node an INITIATOR (sends periodic pings), type 'i' in Serial Monitor.
 *    - To switch back to RESPONDER, type 'r' in Serial Monitor.
 *    - To send a single manual ping, type 't' in Serial Monitor.
 */

#include <Arduino.h>
#include <SPI.h>
#include <RadioLib.h>
#include "../../src/mesh_x_config.h"

// Instantiate RadioLib SX1278 module
// Module(cs, irq/dio0, rst, gpio/dio1)
SX1278 radio = new Module(LORA_CS, LORA_DIO0, LORA_RST);

// State flags and variables
volatile bool operationDone = false;
bool isInitiator = false; // Default: Responder mode
uint32_t packetCounter = 0;
uint32_t lastPingTime = 0;
const uint32_t PING_INTERVAL_MS = 3500;
uint32_t lastPingSentTimestamp = 0;

// Interrupt Service Routine for DIO0
#if defined(ESP8266) || defined(ESP32)
  ICACHE_RAM_ATTR
#endif
void onDio0Triggered(void) {
  operationDone = true;
}

void printBanner() {
  Serial.println(F("\n=================================================="));
  Serial.println(F("         MESH-X PHASE 1: RADIO PROTOTYPE TEST      "));
  Serial.println(F("=================================================="));
  Serial.printf("Carrier Frequency : %.3f MHz\n", LORA_FREQ);
  Serial.printf("Bandwidth         : %.1f kHz\n", LORA_BW);
  Serial.printf("Spreading Factor  : SF%d\n", LORA_SF);
  Serial.printf("Coding Rate       : 4/%d\n", LORA_CR);
  Serial.printf("Sync Word         : 0x%02X\n", LORA_SYNC_WORD);
  Serial.printf("TX Power          : +%d dBm\n", LORA_TX_POWER);
  Serial.println(F("--------------------------------------------------"));
  Serial.println(F("Commands: [i] -> Set Initiator  |  [r] -> Set Responder"));
  Serial.println(F("          [t] -> Single Ping    |  [?] -> Help"));
  Serial.println(F("==================================================\n"));
}

void sendPacket(String payload) {
  operationDone = false;
  int16_t state = radio.startTransmit(payload);
  if (state == RADIOLIB_ERR_NONE) {
    // Wait for TX to complete
    uint32_t txStart = millis();
    while (!operationDone && (millis() - txStart < 1500)) {
      yield();
    }
    if (operationDone) {
      // Serial.println(F("DONE"));
    } else {
      Serial.println(F("[WARN] TX timeout waiting for DIO0 interrupt"));
    }
  } else {
    Serial.printf("[ERROR] Failed to start TX (code: %d)\n", state);
  }

  // Put radio back in non-blocking RX mode
  operationDone = false;
  radio.startReceive();
}

void setup() {
  Serial.begin(115200);
  delay(1000); // Allow USB Serial to enumerate

  printBanner();

  // 1. Initialize VSPI explicitly with defined pin mappings
  Serial.println(F("[INIT] Initializing VSPI bus..."));
  SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_CS);

  // 2. Hardware diagnostic: Verify SX1278 Silicon Revision Register (0x42)
  // RegVersion for SX1278 must return 0x12
  pinMode(LORA_CS, OUTPUT);
  digitalWrite(LORA_CS, LOW);
  SPI.transfer(0x42 & 0x7F); // Read RegVersion
  uint8_t chipVersion = SPI.transfer(0x00);
  digitalWrite(LORA_CS, HIGH);

  Serial.printf("[DIAG] SX1278 RegVersion (0x42) read: 0x%02X\n", chipVersion);
  if (chipVersion == 0x12) {
    Serial.println(F("[SUCCESS] Silicon Version 0x12 verified! SPI wiring is valid."));
  } else if (chipVersion == 0x00 || chipVersion == 0xFF) {
    Serial.println(F("[CRITICAL ERROR] SPI communication failed! Value is 0x00 or 0xFF."));
    Serial.println(F("  Check your wiring: SCK=18, MISO=19, MOSI=23, CS=5, 3V3 power, GND."));
  } else {
    Serial.printf("[WARNING] Unexpected chip version: 0x%02X (expected 0x12 for SX1278)\n", chipVersion);
  }

  // 3. Initialize RadioLib with MESH-X parameters
  Serial.print(F("[INIT] Initializing SX1278 radio transceiver... "));
  int16_t state = radio.begin(
    LORA_FREQ,
    LORA_BW,
    LORA_SF,
    LORA_CR,
    LORA_SYNC_WORD,
    LORA_TX_POWER,
    LORA_PREAMBLE_LEN,
    LORA_GAIN
  );

  if (state == RADIOLIB_ERR_NONE) {
    Serial.println(F("SUCCESS!"));
  } else {
    Serial.printf("FAILED! (RadioLib error code: %d)\n", state);
    Serial.println(F("Halting execution. Verify hardware connections and restart."));
    while (true) { delay(1000); }
  }

  // 4. Attach DIO0 interrupt handler
  radio.setDio0Action(onDio0Triggered, RISING);

  // 5. Start listening for incoming packets
  Serial.println(F("[RADIO] Radio listening for incoming packets..."));
  Serial.println(F("[MODE] Default role: RESPONDER (Waiting for incoming PINGs)\n"));
  radio.startReceive();
}

void loop() {
  // Handle Serial user commands
  if (Serial.available()) {
    char cmd = Serial.read();
    if (cmd == 'i' || cmd == 'I') {
      isInitiator = true;
      Serial.println(F("\n>>> SWITCHED TO: INITIATOR MODE (Sending periodic PINGs) <<<"));
      lastPingTime = 0; // Trigger immediate ping
    } else if (cmd == 'r' || cmd == 'R') {
      isInitiator = false;
      Serial.println(F("\n>>> SWITCHED TO: RESPONDER MODE (Listening for PINGs) <<<"));
      radio.startReceive();
    } else if (cmd == 't' || cmd == 'T') {
      Serial.println(F("\n>>> Triggering single manual PING <<<"));
      packetCounter++;
      String msg = "MESH-X:PING:" + String(packetCounter);
      lastPingSentTimestamp = millis();
      sendPacket(msg);
    } else if (cmd == '?') {
      printBanner();
    }
  }

  // Handle Radio Events (DIO0 interrupt triggered)
  if (operationDone) {
    operationDone = false;

    String rxStr;
    int16_t readState = radio.readData(rxStr);

    if (readState == RADIOLIB_ERR_NONE) {
      float rssi = radio.getRSSI();
      float snr = radio.getSNR();
      float freqErr = radio.getFrequencyError();

      Serial.println(F("--------------------------------------------------"));
      Serial.printf("[RX] Received: \"%s\"\n", rxStr.c_str());
      Serial.printf("     RSSI: %.1f dBm | SNR: %.2f dB | Freq Error: %.1f Hz\n", rssi, snr, freqErr);

      if (rxStr.startsWith("MESH-X:PING:")) {
        String seq = rxStr.substring(12);
        Serial.printf("[EVENT] PING #%s received! Sending PONG reply...\n", seq.c_str());
        delay(60); // Short turnaround guard delay
        String pongReply = "MESH-X:PONG:" + seq;
        sendPacket(pongReply);
        Serial.println(F("[EVENT] PONG reply transmitted."));
      } else if (rxStr.startsWith("MESH-X:PONG:")) {
        String seq = rxStr.substring(12);
        uint32_t rtt = millis() - lastPingSentTimestamp;
        Serial.printf("[SUCCESS] PONG #%s received! Round-Trip Time (RTT): %u ms\n", seq.c_str(), rtt);
      }
      Serial.println(F("--------------------------------------------------\n"));
    } else if (readState == RADIOLIB_ERR_CRC_MISMATCH) {
      Serial.println(F("[ERROR] Packet received with CRC mismatch (corrupted RF frame)!"));
    } else {
      Serial.printf("[WARN] Radio read returned code: %d\n", readState);
    }

    // Return to receive mode
    radio.startReceive();
  }

  // If Initiator mode is active, transmit PING periodically
  if (isInitiator && (millis() - lastPingTime >= PING_INTERVAL_MS)) {
    lastPingTime = millis();
    packetCounter++;
    String pingMsg = "MESH-X:PING:" + String(packetCounter);
    Serial.printf("[TX INITIATOR] Sending PING #%u ...\n", packetCounter);
    lastPingSentTimestamp = millis();
    sendPacket(pingMsg);
  }

  yield();
}
