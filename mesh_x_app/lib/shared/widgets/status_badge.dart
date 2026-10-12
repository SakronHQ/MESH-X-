import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../features/device/domain/connection_state.dart';

class StatusBadge extends StatelessWidget {
  final BleConnectionStatus status;

  const StatusBadge({super.key, required this.status});

  Color get _color {
    switch (status) {
      case BleConnectionStatus.connected:
        return AppColors.connected;
      case BleConnectionStatus.scanning:
        return AppColors.scanning;
      case BleConnectionStatus.connecting:
      case BleConnectionStatus.handshaking:
      case BleConnectionStatus.reconnecting:
        return AppColors.warning;
      case BleConnectionStatus.error:
        return AppColors.error;
      case BleConnectionStatus.disconnected:
        return AppColors.disconnected;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: _color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: TextStyle(
              color: _color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
