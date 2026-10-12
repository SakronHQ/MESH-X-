class MeshXDeviceInfo {
  final int nodeId;
  final String firmwareVersion;
  final int protocolVersion;
  final String deviceName;
  final int rssi;
  final double snr;
  final int queueDepth;
  final int uptimeSec;

  const MeshXDeviceInfo({
    required this.nodeId,
    required this.firmwareVersion,
    required this.protocolVersion,
    required this.deviceName,
    this.rssi = 0,
    this.snr = 0.0,
    this.queueDepth = 0,
    this.uptimeSec = 0,
  });

  MeshXDeviceInfo copyWith({
    int? nodeId,
    String? firmwareVersion,
    int? protocolVersion,
    String? deviceName,
    int? rssi,
    double? snr,
    int? queueDepth,
    int? uptimeSec,
  }) {
    return MeshXDeviceInfo(
      nodeId: nodeId ?? this.nodeId,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      protocolVersion: protocolVersion ?? this.protocolVersion,
      deviceName: deviceName ?? this.deviceName,
      rssi: rssi ?? this.rssi,
      snr: snr ?? this.snr,
      queueDepth: queueDepth ?? this.queueDepth,
      uptimeSec: uptimeSec ?? this.uptimeSec,
    );
  }

  factory MeshXDeviceInfo.fromJson(Map<String, dynamic> json) {
    return MeshXDeviceInfo(
      nodeId: json['node_id'] as int? ?? 0,
      firmwareVersion: json['fw'] as String? ?? 'Unknown',
      protocolVersion: json['proto'] as int? ?? 1,
      deviceName: json['name'] as String? ?? 'MESH-X Node',
      rssi: json['rssi'] as int? ?? 0,
      snr: (json['snr'] as num?)?.toDouble() ?? 0.0,
      queueDepth: json['queue'] as int? ?? 0,
      uptimeSec: json['uptime'] as int? ?? 0,
    );
  }

  String get formattedNodeHex => '0x${nodeId.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}
