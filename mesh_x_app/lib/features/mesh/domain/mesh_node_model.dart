class MeshNodeModel {
  final int nodeId;
  final String alias;
  final int hopDistance;
  final int lastRssi;
  final double lastSnr;
  final int lastSeenAt;
  final String? publicKey;
  final bool isVerified;

  const MeshNodeModel({
    required this.nodeId,
    required this.alias,
    required this.hopDistance,
    required this.lastRssi,
    required this.lastSnr,
    required this.lastSeenAt,
    this.publicKey,
    this.isVerified = false,
  });

  String get formattedNodeHex =>
      '0x${nodeId.toRadixString(16).padLeft(8, '0').toUpperCase()}';

  bool get isDirectNeighbor => hopDistance <= 1;

  bool get hasPublicKey => publicKey != null && publicKey!.isNotEmpty;

  String get fingerprint {
    if (!hasPublicKey || publicKey!.length < 16) return 'UNVERIFIED';
    final upper = publicKey!.toUpperCase();
    return '${upper.substring(0, 4)}:${upper.substring(4, 8)}:${upper.substring(8, 12)}:${upper.substring(12, 16)}';
  }

  String get relativeLastSeen {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final diff = now - lastSeenAt;
    if (diff < 5) return 'Just now';
    if (diff < 60) return '${diff}s ago';
    if (diff < 3600) return '${diff ~/ 60}m ago';
    return '${diff ~/ 3600}h ago';
  }

  MeshNodeModel copyWith({
    int? nodeId,
    String? alias,
    int? hopDistance,
    int? lastRssi,
    double? lastSnr,
    int? lastSeenAt,
    String? publicKey,
    bool? isVerified,
  }) {
    return MeshNodeModel(
      nodeId: nodeId ?? this.nodeId,
      alias: alias ?? this.alias,
      hopDistance: hopDistance ?? this.hopDistance,
      lastRssi: lastRssi ?? this.lastRssi,
      lastSnr: lastSnr ?? this.lastSnr,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      publicKey: publicKey ?? this.publicKey,
      isVerified: isVerified ?? this.isVerified,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'node_id': nodeId,
      'alias': alias,
      'hop_distance': hopDistance,
      'last_rssi': lastRssi,
      'last_snr': lastSnr,
      'last_seen_at': lastSeenAt,
      'public_key': publicKey,
      'is_verified': isVerified ? 1 : 0,
    };
  }

  factory MeshNodeModel.fromMap(Map<String, dynamic> map) {
    return MeshNodeModel(
      nodeId: map['node_id'] as int,
      alias: map['alias'] as String? ??
          'Node 0x${(map['node_id'] as int).toRadixString(16).padLeft(8, '0').toUpperCase()}',
      hopDistance: (map['hop_distance'] as int?) ?? 1,
      lastRssi: (map['last_rssi'] as int?) ?? -100,
      lastSnr: (map['last_snr'] as num?)?.toDouble() ?? 0.0,
      lastSeenAt: map['last_seen_at'] as int,
      publicKey: map['public_key'] as String?,
      isVerified: (map['is_verified'] as int? ?? 0) == 1,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MeshNodeModel &&
          runtimeType == other.runtimeType &&
          nodeId == other.nodeId &&
          alias == other.alias &&
          hopDistance == other.hopDistance &&
          lastRssi == other.lastRssi &&
          lastSnr == other.lastSnr &&
          lastSeenAt == other.lastSeenAt &&
          publicKey == other.publicKey &&
          isVerified == other.isVerified;

  @override
  int get hashCode =>
      nodeId.hashCode ^
      alias.hashCode ^
      hopDistance.hashCode ^
      lastRssi.hashCode ^
      lastSnr.hashCode ^
      lastSeenAt.hashCode ^
      publicKey.hashCode ^
      isVerified.hashCode;
}
