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
    final color = _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: color.withValues(alpha: 0.28),
          width: 1,
        ),
        boxShadow: [
          if (status == BleConnectionStatus.connected)
            BoxShadow(
              color: color.withValues(alpha: 0.15),
              blurRadius: 8,
              spreadRadius: 1,
            ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 7),
          Text(
            status.label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

