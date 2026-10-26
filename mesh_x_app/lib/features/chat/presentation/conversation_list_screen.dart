import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../device/presentation/ble_controller.dart';
import '../../sos/presentation/sos_alert_banner.dart';
import '../../sos/presentation/sos_composer_dialog.dart';
import '../../sos/presentation/sos_controller.dart';
import '../domain/conversation_model.dart';
import 'chat_controller.dart';
import 'chat_conversation_screen.dart';

class ConversationListScreen extends ConsumerWidget {
  const ConversationListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bleState = ref.watch(bleControllerProvider);
    final convsAsync = ref.watch(conversationsProvider);
    final activeSos = ref.watch(activeSosAlertProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.emergency_outlined,
                color: AppColors.error,
                size: 19,
              ),
            ),
            tooltip: 'Emergency SOS Distress Broadcast',
            onPressed: () {
              HapticFeedback.mediumImpact();
              showDialog(
                context: context,
                builder: (_) => const SosComposerDialog(),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16, left: 4),
            child: Center(
              child: StatusBadge(status: bleState.status),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (activeSos != null) SosAlertBanner(alert: activeSos),
          Expanded(
            child: convsAsync.when(
              data: (conversations) {
                if (conversations.isEmpty) {
                  return _buildEmptyState(context, ref);
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
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
                child: Text(
                  'Error loading conversations: $err',
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 60),
        child: FloatingActionButton(
          backgroundColor: AppColors.accent,
          foregroundColor: const Color(0xFF041017),
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onPressed: () {
            HapticFeedback.lightImpact();
            _showNewConversationDialog(context, ref);
          },
          child: const Icon(Icons.edit_note_rounded, size: 24),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 30,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No Conversations Yet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Broadcast channel and discovered node threads will appear here automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(180, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: () => _showNewConversationDialog(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Start Direct Chat', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationTile(BuildContext context, ConversationModel conv) {
    final isBroadcast = conv.id == 'broadcast';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatConversationScreen(conversation: conv),
            ),
          );
        },
        borderRadius: BorderRadius.circular(18),
        splashColor: AppColors.accent.withValues(alpha: 0.08),
        highlightColor: AppColors.surfaceHighlight.withValues(alpha: 0.4),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: isBroadcast
                      ? LinearGradient(
                          colors: [
                            AppColors.accent.withValues(alpha: 0.2),
                            AppColors.accentMuted.withValues(alpha: 0.1),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: isBroadcast ? null : AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isBroadcast
                        ? AppColors.accent.withValues(alpha: 0.3)
                        : AppColors.border,
                  ),
                ),
                child: Icon(
                  isBroadcast
                      ? Icons.cell_tower_rounded
                      : Icons.person_outline_rounded,
                  color: isBroadcast ? AppColors.accent : AppColors.textPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),

              // Content Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            conv.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (conv.lastMessageTimestamp != null)
                          Text(
                            _formatTimestamp(conv.lastMessageTimestamp!),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w500,
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
                              height: 1.3,
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
                                color: Color(0xFF041017),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: AppColors.border),
          ),
          title: const Text(
            'Direct Chat by Node ID',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the 32-bit hex Node ID of your peer (e.g. 0xA1B2C3D4):',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                decoration: const InputDecoration(
                  hintText: '0x12345678',
                  hintStyle: TextStyle(color: AppColors.textMuted),
                  prefixIcon: Icon(Icons.tag, size: 18, color: AppColors.accent),
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(120, 42),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
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

