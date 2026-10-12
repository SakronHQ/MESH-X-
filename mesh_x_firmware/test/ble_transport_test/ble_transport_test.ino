/**
 * MESH-X Phase 2: ESP32 BLE Transport Layer Test
 * 
 * Target Hardware: ESP32 DevKit V1
 * Purpose:
 *   1. Starts MESH-X BLE GATT server with custom 128-bit UUIDs.
 *   2. Advertises as "MESH-X-[NodeID]".
 *   3. Handles Device Info read, Command In write, Event Out notify, and Telemetry notify.
 *   4. Supports binary framing, CRC-16-CCITT validation, and command acknowledgments.
 *   5. Automatic advertising resume upon disconnection.
 */

#include <Arduino.h>
#include "../../src/mesh_x_protocol.h"
#include "../../src/mesh_x_ble.h"

MeshXBLE ble;
uint32_t g_nodeId = 0;
uint32_t g_lastTelemetryUpdate = 0;
uint32_t g_simulatedMsgCounter = 0;

void handleMessageSubmitted(const uint8_t* payload, size_t len) {
  // Convert payload to String for serial logging
  String text = "";
  for (size_t i = 0; i < len; ++i) {
    text += (char)payload[i];
  }
  Serial.printf("[APP MSG] Received message from mobile app: \"%s\" (%d bytes)\n", text.c_str(), (int)len);
  Serial.println(F("[APP MSG] Ready for Radio TX queue routing."));
}

void printBanner() {
  Serial.println(F("\n========================================================"));
  Serial.println(F("         MESH-X PHASE 2: BLE TRANSPORT LAYER TEST       "));
  Serial.println(F("========================================================"));
  Serial.printf("Node ID          : 0x%08X (MESH-X-%06X)\n", g_nodeId, (unsigned int)(g_nodeId & 0xFFFFFF));
  Serial.printf("Service UUID     : %s\n", MESHX_SERVICE_UUID);
  Serial.printf("Device Info Char : %s (Read)\n", MESHX_CHAR_DEVICE_INFO_UUID);
  Serial.printf("Command In Char  : %s (Write)\n", MESHX_CHAR_COMMAND_IN_UUID);
  Serial.printf("Event Out Char   : %s (Notify)\n", MESHX_CHAR_EVENT_OUT_UUID);
  Serial.printf("Telemetry Char   : %s (Read/Notify)\n", MESHX_CHAR_TELEMETRY_UUID);
  Serial.println(F("--------------------------------------------------------"));
  Serial.println(F("Serial Commands:"));
  Serial.println(F("  [s] -> Simulate incoming LoRa RX message to Mobile App"));
  Serial.println(F("  [t] -> Trigger immediate Telemetry update"));
  Serial.println(F("  [?] -> Print this help menu"));
  Serial.println(F("========================================================\n"));
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  // Derive unique 32-bit Node ID from ESP32 factory MAC address
  uint64_t mac = ESP.getEfuseMac();
  g_nodeId = (uint32_t)(mac & 0xFFFFFFFF);

  printBanner();

  // Register app message callback
  ble.onMessageSubmitted(handleMessageSubmitted);

  // Start BLE GATT Server
  ble.begin(g_nodeId, "1.0.0");
}

void loop() {
  ble.loop();

  // Update telemetry every 5 seconds
  if (millis() - g_lastTelemetryUpdate >= 5000) {
    g_lastTelemetryUpdate = millis();
    uint32_t uptime = millis() / 1000;
    // Simulated radio stats for bench test (0 RSSI if no radio active)
    ble.updateTelemetry(-65, 8.5f, 0, uptime);
  }

  // Handle Serial inputs for testing
  if (Serial.available()) {
    char c = Serial.read();
    if (c == 's' || c == 'S') {
      if (ble.isConnected()) {
        g_simulatedMsgCounter++;
        String testMsg = "Hello from Node B #" + String(g_simulatedMsgCounter);
        Serial.printf("[SIMULATE] Sending RX message event to mobile: \"%s\"\n", testMsg.c_str());
        ble.sendRxMessage(0xB2C3D4E5, testMsg, -72.0f, 9.2f);
      } else {
        Serial.println(F("[SIMULATE] No mobile client connected via BLE. Connect phone first."));
      }
    } else if (c == 't' || c == 'T') {
      Serial.println(F("[TELEMETRY] Manual telemetry push triggered."));
      ble.updateTelemetry(-60, 9.0f, 1, millis() / 1000);
    } else if (c == '?') {
      printBanner();
    }
  }

  delay(20);
}
