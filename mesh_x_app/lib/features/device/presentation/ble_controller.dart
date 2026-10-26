import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/ble_constants.dart';
import '../data/ble_repository.dart';
import '../domain/connection_state.dart';
import '../domain/device_info_model.dart';

final bleRepositoryProvider = Provider<BleRepository>((ref) {
  return BleRepository();
});

class BleState {
  final BleConnectionStatus status;
  final MeshXDeviceInfo? deviceInfo;
  final List<ScanResult> scanResults;
  final bool isScanning;
  final String? errorMessage;
  final bool autoReconnect;

  const BleState({
    this.status = BleConnectionStatus.disconnected,
    this.deviceInfo,
    this.scanResults = const [],
    this.isScanning = false,
    this.errorMessage,
    this.autoReconnect = true,
  });

  BleState copyWith({
    BleConnectionStatus? status,
    MeshXDeviceInfo? deviceInfo,
    List<ScanResult>? scanResults,
    bool? isScanning,
    String? errorMessage,
    bool? autoReconnect,
  }) {
    return BleState(
      status: status ?? this.status,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      scanResults: scanResults ?? this.scanResults,
      isScanning: isScanning ?? this.isScanning,
      errorMessage: errorMessage,
      autoReconnect: autoReconnect ?? this.autoReconnect,
    );
  }

  bool get isConnected => status == BleConnectionStatus.connected;
}

class BleController extends Notifier<BleState> {
  BleRepository get _repository => ref.read(bleRepositoryProvider);
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<Map<String, dynamic>>? _telemetrySub;
  Timer? _reconnectTimer;
  AppLifecycleListener? _lifecycleListener;
  bool _isConnecting = false;

  @override
  BleState build() {
    ref.onDispose(() {
      _reconnectTimer?.cancel();
      _lifecycleListener?.dispose();
      _scanSub?.cancel();
      _telemetrySub?.cancel();
    });

    Future.microtask(() {
      _init();
    });

    return const BleState();
  }

  void _init() {
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        if (state.status == BleConnectionStatus.disconnected && state.autoReconnect) {
          _scheduleAutoReconnect(delay: const Duration(milliseconds: 600));
        }
      },
    );

    _scanSub = _repository.scanResults.listen((results) {
      final filtered = results.where((r) {
        final name = r.advertisementData.advName;
        return name.startsWith('MESH-X-') ||
            r.advertisementData.serviceUuids.any((u) =>
                u.toString().toUpperCase() == BleConstants.serviceUuid.toUpperCase());
      }).toList();
      state = state.copyWith(scanResults: filtered);
    });

    _telemetrySub = _repository.telemetryStream.listen((data) {
      if (state.deviceInfo != null) {
        final updated = state.deviceInfo!.copyWith(
          rssi: data['rssi'] as int? ?? state.deviceInfo!.rssi,
          snr: (data['snr'] as num?)?.toDouble() ?? state.deviceInfo!.snr,
          queueDepth: data['queue'] as int? ?? state.deviceInfo!.queueDepth,
          uptimeSec: data['uptime'] as int? ?? state.deviceInfo!.uptimeSec,
          batteryMv: data['batt'] as int? ?? state.deviceInfo!.batteryMv,
        );
        state = state.copyWith(deviceInfo: updated);
      }
    });

    // Check saved device for auto-connect with a brief debounce
    _scheduleAutoReconnect(delay: const Duration(milliseconds: 800));
  }

  void _scheduleAutoReconnect({Duration delay = const Duration(seconds: 4)}) {
    _reconnectTimer?.cancel();
    if (!state.autoReconnect) return;
    _reconnectTimer = Timer(delay, () {
      if (state.status == BleConnectionStatus.disconnected ||
          state.status == BleConnectionStatus.error) {
        checkAutoReconnect();
      }
    });
  }

  Future<void> checkAutoReconnect() async {
    if (!state.autoReconnect || _isConnecting) return;
    final savedId = await _repository.getSavedDeviceId();
    if (savedId != null &&
        (state.status == BleConnectionStatus.disconnected ||
            state.status == BleConnectionStatus.error)) {
      state = state.copyWith(status: BleConnectionStatus.reconnecting);
      try {
        final device = BluetoothDevice.fromId(savedId);
        await connect(device);
      } catch (e) {
        state = state.copyWith(
          status: BleConnectionStatus.disconnected,
          errorMessage: 'Auto-reconnect failed. Tap to scan.',
        );
      }
    }
  }

  Future<void> startScan() async {
    _reconnectTimer?.cancel();
    state = state.copyWith(
      isScanning: true,
      status: BleConnectionStatus.scanning,
      errorMessage: null,
      scanResults: [],
    );

    try {
      await _repository.startScan();
    } catch (e) {
      state = state.copyWith(
        isScanning: false,
        status: BleConnectionStatus.disconnected,
        errorMessage: 'Failed to start scan: $e',
      );
    }
  }

  Future<void> stopScan() async {
    await _repository.stopScan();
    state = state.copyWith(
      isScanning: false,
      status: state.status == BleConnectionStatus.scanning
          ? BleConnectionStatus.disconnected
          : state.status,
    );
  }

  Future<void> connect(BluetoothDevice device) async {
    if (_isConnecting ||
        state.status == BleConnectionStatus.connecting ||
        state.status == BleConnectionStatus.handshaking) {
      return;
    }
    _isConnecting = true;
    _reconnectTimer?.cancel();

    await stopScan();
    state = state.copyWith(
      status: BleConnectionStatus.connecting,
      errorMessage: null,
    );

    try {
      state = state.copyWith(status: BleConnectionStatus.handshaking);
      final info = await _repository.connect(
        device,
        onStateChange: (connState) {
          if (connState == BluetoothConnectionState.disconnected) {
            state = state.copyWith(
              status: BleConnectionStatus.disconnected,
              deviceInfo: null,
            );
            if (state.autoReconnect) {
              _scheduleAutoReconnect(delay: const Duration(seconds: 4));
            }
          }
        },
      );

      state = state.copyWith(
        status: BleConnectionStatus.connected,
        deviceInfo: info,
      );
    } catch (e) {
      state = state.copyWith(
        status: BleConnectionStatus.error,
        errorMessage: 'Connection failed: $e',
      );
      if (state.autoReconnect) {
        _scheduleAutoReconnect(delay: const Duration(seconds: 6));
      }
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    await _repository.disconnect();
    state = state.copyWith(
      status: BleConnectionStatus.disconnected,
      deviceInfo: null,
    );
  }

  Future<void> forgetDevice() async {
    _reconnectTimer?.cancel();
    await disconnect();
    await _repository.forgetSavedDevice();
  }

  Future<void> sendPing() async {
    await _repository.sendCommand(BleConstants.cmdPing);
  }

  void toggleAutoReconnect(bool enabled) {
    state = state.copyWith(autoReconnect: enabled);
    if (enabled && state.status == BleConnectionStatus.disconnected) {
      _scheduleAutoReconnect(delay: const Duration(milliseconds: 500));
    } else if (!enabled) {
      _reconnectTimer?.cancel();
    }
  }
}

final bleControllerProvider = NotifierProvider<BleController, BleState>(BleController.new);
