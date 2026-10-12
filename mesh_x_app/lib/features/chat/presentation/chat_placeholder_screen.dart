import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../device/domain/connection_state.dart';
import '../../device/presentation/ble_controller.dart';

class ChatPlaceholderScreen extends ConsumerWidget {
  const ChatPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bleState = ref.watch(bleControllerProvider);
    final isConnected = bleState.status == BleConnectionStatus.connected;

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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: isConnected
                      ? AppColors.connected.withValues(alpha: 0.1)
                      : AppColors.surfaceElevated,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isConnected ? Icons.chat_bubble_outline : Icons.cloud_off,
                  size: 34,
                  color: isConnected ? AppColors.connected : AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isConnected
                    ? 'Node Ready for Messaging'
                    : 'Radio Node Disconnected',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isConnected
                    ? 'Connected to ${bleState.deviceInfo?.deviceName ?? 'ESP32'}. End-to-end SQLite messaging and conversation UI is scheduled for Phase 4.'
                    : 'Pair with your ESP32 node via the "Hardware" tab to enable off-grid LoRa messaging.',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
