import 'package:flutter/material.dart';
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (deviceInfo != null) ...[
                TelemetryCard(deviceInfo: deviceInfo),
                const SizedBox(height: 20),
              ],

              // Hardware Diagnostics Section
              const Text(
                'Link & Diagnostics',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.network_ping, color: AppColors.accent, size: 20),
                      ),
                      title: const Text('Test BLE Link (Ping)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: const Text('Sends framed CMD_PING and awaits EVT_PONG', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      trailing: ElevatedButton(
                        onPressed: () async {
                          await controller.sendPing();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('CMD_PING sent to ESP32 node'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                        child: const Text('Ping', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto-Reconnect', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: const Text('Automatically reconnect when in range', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      value: bleState.autoReconnect,
                      activeThumbColor: AppColors.accent,
                      onChanged: (val) => controller.toggleAutoReconnect(val),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              const Text(
                'Device Actions',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => controller.disconnect(),
                icon: const Icon(Icons.link_off, size: 18, color: AppColors.warning),
                label: const Text('Disconnect Node', style: TextStyle(color: AppColors.warning)),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => controller.forgetDevice(),
                icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                label: const Text('Forget & Disconnect Node', style: TextStyle(color: AppColors.error)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
