import 'dart:async';
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

  @override
  BleState build() {
    _init();
    ref.onDispose(() {
      _scanSub?.cancel();
      _telemetrySub?.cancel();
    });
    return const BleState();
  }

  void _init() {
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

    // Check saved device for auto-connect
    checkAutoReconnect();
  }

  Future<void> checkAutoReconnect() async {
    if (!state.autoReconnect) return;
    final savedId = await _repository.getSavedDeviceId();
    if (savedId != null && state.status == BleConnectionStatus.disconnected) {
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
              checkAutoReconnect();
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
    }
  }

  Future<void> disconnect() async {
    await _repository.disconnect();
    state = state.copyWith(
      status: BleConnectionStatus.disconnected,
      deviceInfo: null,
    );
  }

  Future<void> forgetDevice() async {
    await disconnect();
    await _repository.forgetSavedDevice();
  }

  Future<void> sendPing() async {
    await _repository.sendCommand(BleConstants.cmdPing);
  }

  void toggleAutoReconnect(bool enabled) {
    state = state.copyWith(autoReconnect: enabled);
  }
}

final bleControllerProvider = NotifierProvider<BleController, BleState>(BleController.new);
