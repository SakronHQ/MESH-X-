import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/telemetry_card.dart';
import 'ble_controller.dart';

class DeviceDashboardScreen extends ConsumerWidget {
  const DeviceDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bleState = ref.watch(bleControllerProvider);
    final controller = ref.read(bleControllerProvider.notifier);
    final deviceInfo = bleState.deviceInfo;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Node Dashboard'),
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 90),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (deviceInfo != null) ...[
                TelemetryCard(deviceInfo: deviceInfo),
                const SizedBox(height: 22),
              ],

              // Hardware Diagnostics Section
              const Text(
                'Link & Diagnostics',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.network_ping_rounded,
                              color: AppColors.accent,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Test BLE Link (Ping)',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Sends framed CMD_PING and awaits EVT_PONG',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () async {
                              HapticFeedback.lightImpact();
                              await controller.sendPing();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('CMD_PING sent to ESP32 gateway node'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text('Ping', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Auto-Reconnect',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        subtitle: const Text(
                          'Automatically restore link when node is in range',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        value: bleState.autoReconnect,
                        activeThumbColor: AppColors.accent,
                        onChanged: (val) {
                          HapticFeedback.selectionClick();
                          controller.toggleAutoReconnect(val);
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              const Text(
                'Device Actions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  controller.disconnect();
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.warning.withValues(alpha: 0.5), width: 1.2),
                ),
                icon: const Icon(Icons.link_off_rounded, size: 18, color: AppColors.warning),
                label: const Text('Disconnect Node', style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  controller.forgetDevice();
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.error.withValues(alpha: 0.5), width: 1.2),
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                label: const Text('Forget & Disconnect Node', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

