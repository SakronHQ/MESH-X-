import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../features/device/domain/device_info_model.dart';

class TelemetryCard extends StatelessWidget {
  final MeshXDeviceInfo deviceInfo;

  const TelemetryCard({super.key, required this.deviceInfo});

  @override
  Widget build(BuildContext context) {
    final batteryPct = deviceInfo.batteryPercentage.clamp(0, 100);
    final batteryColor = batteryPct > 40
        ? AppColors.connected
        : (batteryPct > 18 ? AppColors.warning : AppColors.error);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar: Device Name + Copyable Hex Chip
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 16, 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.25),
                      ),
                    ),
                    child: const Icon(Icons.router, color: AppColors.accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          deviceInfo.deviceName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'Firmware v${deviceInfo.firmwareVersion} • Proto v${deviceInfo.protocolVersion}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: deviceInfo.formattedNodeHex));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Node ID ${deviceInfo.formattedNodeHex} copied'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceHighlight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            deviceInfo.formattedNodeHex,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Icon(Icons.copy, size: 12, color: AppColors.accent),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: AppColors.border),

            // Battery Progress Gauge
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            batteryPct > 50
                                ? Icons.battery_charging_full
                                : (batteryPct > 20
                                    ? Icons.battery_5_bar
                                    : Icons.battery_alert),
                            size: 16,
                            color: batteryColor,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Battery Level',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '$batteryPct% (${deviceInfo.batteryVoltage.toStringAsFixed(2)} V)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: batteryColor,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: batteryPct / 100.0,
                      minHeight: 5,
                      backgroundColor: AppColors.surfaceElevated,
                      valueColor: AlwaysStoppedAnimation<Color>(batteryColor),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: AppColors.border),

            // 4 Grid Metrics
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildMetricItem(
                      label: 'Radio RSSI',
                      value: '${deviceInfo.rssi} dBm',
                      icon: Icons.wifi_tethering,
                      valueColor: deviceInfo.rssi > -80
                          ? AppColors.connected
                          : (deviceInfo.rssi > -105
                              ? AppColors.warning
                              : AppColors.error),
                    ),
                  ),
                  Container(width: 1, height: 36, color: AppColors.border),
                  Expanded(
                    child: _buildMetricItem(
                      label: 'Radio SNR',
                      value: '${deviceInfo.snr.toStringAsFixed(1)} dB',
                      icon: Icons.graphic_eq,
                      valueColor: AppColors.textPrimary,
                    ),
                  ),
                  Container(width: 1, height: 36, color: AppColors.border),
                  Expanded(
                    child: _buildMetricItem(
                      label: 'Tx Queue',
                      value: '${deviceInfo.queueDepth} pkts',
                      icon: Icons.alt_route,
                      valueColor: deviceInfo.queueDepth > 10
                          ? AppColors.warning
                          : AppColors.textPrimary,
                    ),
                  ),
                  Container(width: 1, height: 36, color: AppColors.border),
                  Expanded(
                    child: _buildMetricItem(
                      label: 'Uptime',
                      value: _formatUptime(deviceInfo.uptimeSec),
                      icon: Icons.timer_outlined,
                      valueColor: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricItem({
    required String label,
    required String value,
    required IconData icon,
    required Color valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _formatUptime(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    if (m < 60) return '${m}m';
    final h = m ~/ 60;
    final remM = m % 60;
    return '${h}h ${remM}m';
  }
}

