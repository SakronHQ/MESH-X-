import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../device/presentation/ble_controller.dart';
import '../domain/conversation_model.dart';
import 'chat_controller.dart';
import 'chat_conversation_screen.dart';

class ConversationListScreen extends ConsumerWidget {
  const ConversationListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bleState = ref.watch(bleControllerProvider);
    final convsAsync = ref.watch(conversationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MESH-X Messages'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: StatusBadge(status: bleState.status),
            ),
          ),
        ],
      ),
      body: convsAsync.when(
        data: (conversations) {
          if (conversations.isEmpty) {
            return const Center(
              child: Text(
                'No conversations yet.\nBroadcast chat will appear once initialized.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: conversations.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final conv = conversations[index];
              return _buildConversationTile(context, conv);
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
        error: (err, _) => Center(
          child: Text('Error loading conversations: $err', style: const TextStyle(color: AppColors.error)),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        onPressed: () => _showNewConversationDialog(context, ref),
        child: const Icon(Icons.add_comment_outlined),
      ),
    );
  }

  Widget _buildConversationTile(BuildContext context, ConversationModel conv) {
    final isBroadcast = conv.id == 'broadcast';

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatConversationScreen(conversation: conv),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isBroadcast
                    ? AppColors.accent.withValues(alpha: 0.12)
                    : AppColors.surfaceElevated,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isBroadcast ? Icons.cell_tower : Icons.person_outline,
                color: isBroadcast ? AppColors.accent : AppColors.textPrimary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        conv.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (conv.lastMessageTimestamp != null)
                        Text(
                          _formatTimestamp(conv.lastMessageTimestamp!),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conv.lastMessageText ?? 'No messages yet',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      if (conv.unreadCount > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${conv.unreadCount}',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNewConversationDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Direct Chat by Node ID', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the 32-bit hex Node ID of your peer (e.g. 0xA1B2C3D4 or integer):',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  hintText: '0x12345678',
                  hintStyle: TextStyle(color: AppColors.textMuted),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              onPressed: () {
                final text = controller.text.trim();
                int? nodeId;
                if (text.startsWith('0x') || text.startsWith('0X')) {
                  nodeId = int.tryParse(text.substring(2), radix: 16);
                } else {
                  nodeId = int.tryParse(text);
                }
                if (nodeId != null) {
                  final hexStr = '0x${nodeId.toRadixString(16).padLeft(8, '0').toUpperCase()}';
                  final conv = ConversationModel(
                    id: hexStr,
                    title: 'Node $hexStr',
                    peerNodeId: nodeId,
                    createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                    updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                  );
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatConversationScreen(conversation: conv),
                    ),
                  );
                }
              },
              child: const Text('Start Chat'),
            ),
          ],
        );
      },
    );
  }

  String _formatTimestamp(int timestampSec) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampSec * 1000);
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$hour:$min';
  }
}
