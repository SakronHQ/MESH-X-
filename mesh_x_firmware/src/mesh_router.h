#pragma once

#include <Arduino.h>

#define MESH_DUPLICATE_CACHE_SIZE 64
#define MESH_MAX_NEIGHBORS        16
#define MESH_DEFAULT_TTL          3

struct NeighborNode {
  uint32_t nodeId;
  uint8_t  hopDistance;
  int8_t   lastRssi;
  int8_t   lastSnr;
  uint32_t lastSeenTimestamp;
};

class MeshRouter {
public:
  MeshRouter() : m_cacheIndex(0), m_neighborCount(0) {
    memset(m_seenPacketIds, 0, sizeof(m_seenPacketIds));
    memset(m_neighbors, 0, sizeof(m_neighbors));
  }

  // Returns true if packet was already seen (duplicate), otherwise records it
  bool isDuplicate(uint32_t packetId) {
    if (packetId == 0) return false;

    for (size_t i = 0; i < MESH_DUPLICATE_CACHE_SIZE; ++i) {
      if (m_seenPacketIds[i] == packetId) {
        return true;
      }
    }

    // Add to circular buffer
    m_seenPacketIds[m_cacheIndex] = packetId;
    m_cacheIndex = (m_cacheIndex + 1) % MESH_DUPLICATE_CACHE_SIZE;
    return false;
  }

  // Update or insert a neighbor in the routing table
  void recordNeighbor(uint32_t nodeId, uint8_t hops, float rssi, float snr) {
    if (nodeId == 0) return;

    uint32_t nowSec = millis() / 1000;

    // Search existing
    for (size_t i = 0; i < m_neighborCount; ++i) {
      if (m_neighbors[i].nodeId == nodeId) {
        m_neighbors[i].hopDistance = hops;
        m_neighbors[i].lastRssi = (int8_t)rssi;
        m_neighbors[i].lastSnr = (int8_t)snr;
        m_neighbors[i].lastSeenTimestamp = nowSec;
        return;
      }
    }

    // Insert new
    if (m_neighborCount < MESH_MAX_NEIGHBORS) {
      m_neighbors[m_neighborCount].nodeId = nodeId;
      m_neighbors[m_neighborCount].hopDistance = hops;
      m_neighbors[m_neighborCount].lastRssi = (int8_t)rssi;
      m_neighbors[m_neighborCount].lastSnr = (int8_t)snr;
      m_neighbors[m_neighborCount].lastSeenTimestamp = nowSec;
      m_neighborCount++;
    } else {
      // Overwrite oldest
      size_t oldestIdx = 0;
      uint32_t oldestTime = m_neighbors[0].lastSeenTimestamp;
      for (size_t i = 1; i < MESH_MAX_NEIGHBORS; ++i) {
        if (m_neighbors[i].lastSeenTimestamp < oldestTime) {
          oldestTime = m_neighbors[i].lastSeenTimestamp;
          oldestIdx = i;
        }
      }
      m_neighbors[oldestIdx].nodeId = nodeId;
      m_neighbors[oldestIdx].hopDistance = hops;
      m_neighbors[oldestIdx].lastRssi = (int8_t)rssi;
      m_neighbors[oldestIdx].lastSnr = (int8_t)snr;
      m_neighbors[oldestIdx].lastSeenTimestamp = nowSec;
    }
  }

  size_t getNeighborCount() const { return m_neighborCount; }
  const NeighborNode* getNeighbors() const { return m_neighbors; }

private:
  uint32_t m_seenPacketIds[MESH_DUPLICATE_CACHE_SIZE];
  size_t   m_cacheIndex;

  NeighborNode m_neighbors[MESH_MAX_NEIGHBORS];
  size_t       m_neighborCount;
};
