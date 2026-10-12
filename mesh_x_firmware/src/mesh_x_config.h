#pragma once

#include <Arduino.h>

// =============================================================================
// MESH-X HARDWARE PIN ASSIGNMENTS (ESP32 DevKit V1 + SX1278 RA-02)
// =============================================================================
#define LORA_SCK       18   // VSPI SCK
#define LORA_MISO      19   // VSPI MISO
#define LORA_MOSI      23   // VSPI MOSI
#define LORA_CS        5    // VSPI Chip Select (NSS)
#define LORA_RST       14   // SX1278 Reset
#define LORA_DIO0      26   // Packet RX/TX Done Interrupt Line

// =============================================================================
// MESH-X RF PARAMETERS (433 MHz ISM Band)
// =============================================================================
#define LORA_FREQ          433.175  // Carrier frequency in MHz (verify RA-02 marking!)
#define LORA_BW            125.0    // Bandwidth in kHz (125.0 default)
#define LORA_SF            9        // Spreading Factor (6 - 12, 9 recommended for mesh balance)
#define LORA_CR            7        // Coding Rate denominator (7 means 4/7)
#define LORA_SYNC_WORD     0x12     // Custom Sync Word (0x12: private MESH-X network)
#define LORA_TX_POWER      14       // Transmit power in dBm (2 - 17 dBm)
#define LORA_PREAMBLE_LEN  8        // Preamble length in symbols
#define LORA_GAIN          0        // Automatic Gain Control (0 = auto)

// =============================================================================
// PROTOCOL CONSTANTS
// =============================================================================
#define MESH_MAGIC_BYTE    0x58     // 'X'
#define MESH_PROTO_VERSION 0x01
