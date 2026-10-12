class ConversationModel {
  final String id;
  final String title;
  final int peerNodeId;
  final String? lastMessageText;
  final int? lastMessageTimestamp;
  final int unreadCount;
  final bool isPinned;
  final int createdAt;
  final int updatedAt;

  const ConversationModel({
    required this.id,
    required this.title,
    required this.peerNodeId,
    this.lastMessageText,
    this.lastMessageTimestamp,
    this.unreadCount = 0,
    this.isPinned = false,
    required this.createdAt,
    required this.updatedAt,
  });

  ConversationModel copyWith({
    String? id,
    String? title,
    int? peerNodeId,
    String? lastMessageText,
    int? lastMessageTimestamp,
    int? unreadCount,
    bool? isPinned,
    int? createdAt,
    int? updatedAt,
  }) {
    return ConversationModel(
      id: id ?? this.id,
      title: title ?? this.title,
      peerNodeId: peerNodeId ?? this.peerNodeId,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageTimestamp: lastMessageTimestamp ?? this.lastMessageTimestamp,
      unreadCount: unreadCount ?? this.unreadCount,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'peer_node_id': peerNodeId,
      'last_message_text': lastMessageText,
      'last_message_timestamp': lastMessageTimestamp,
      'unread_count': unreadCount,
      'is_pinned': isPinned ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory ConversationModel.fromMap(Map<String, dynamic> map) {
    return ConversationModel(
      id: map['id'] as String,
      title: map['title'] as String,
      peerNodeId: map['peer_node_id'] as int,
      lastMessageText: map['last_message_text'] as String?,
      lastMessageTimestamp: map['last_message_timestamp'] as int?,
      unreadCount: map['unread_count'] as int? ?? 0,
      isPinned: (map['is_pinned'] as int? ?? 0) == 1,
      createdAt: map['created_at'] as int,
      updatedAt: map['updated_at'] as int,
    );
  }

  String get formattedPeerHex =>
      peerNodeId == 0xFFFFFFFF ? 'BROADCAST' : '0x${peerNodeId.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}
