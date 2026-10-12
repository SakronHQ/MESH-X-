enum BleConnectionStatus {
  disconnected,
  scanning,
  connecting,
  handshaking,
  connected,
  reconnecting,
  error;

  String get label {
    switch (this) {
      case BleConnectionStatus.disconnected:
        return 'Disconnected';
      case BleConnectionStatus.scanning:
        return 'Scanning for nodes...';
      case BleConnectionStatus.connecting:
        return 'Connecting...';
      case BleConnectionStatus.handshaking:
        return 'Verifying protocol...';
      case BleConnectionStatus.connected:
        return 'Connected';
      case BleConnectionStatus.reconnecting:
        return 'Reconnecting...';
      case BleConnectionStatus.error:
        return 'Connection Error';
    }
  }
}
