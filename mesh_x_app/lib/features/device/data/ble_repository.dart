import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/ble_constants.dart';
import '../../../core/utils/crc16.dart';
import '../domain/device_info_model.dart';
import '../domain/radio_config_model.dart';

class BleRepository {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _cmdInChar;
  BluetoothCharacteristic? _eventOutChar;
  BluetoothCharacteristic? _telemetryChar;
  BluetoothCharacteristic? _deviceInfoChar;

  StreamSubscription<BluetoothConnectionState>? _connStateSubscription;
  StreamSubscription<List<int>>? _eventSubscription;
  StreamSubscription<List<int>>? _telemetrySubscription;

  final _eventController = StreamController<List<int>>.broadcast();
  Stream<List<int>> get eventStream => _eventController.stream;

  final _telemetryController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get telemetryStream => _telemetryController.stream;

  final _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  int _cmdSeq = 0;
  int _negotiatedMtu = 23;
  Future<void> _writeChain = Future.value();

  BluetoothDevice? get connectedDevice => _connectedDevice;
  bool get isReady => _connectedDevice != null && _cmdInChar != null;

  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      final scanStatus = await Permission.bluetoothScan.request();
      final connectStatus = await Permission.bluetoothConnect.request();
      await Permission.locationWhenInUse.request();
      return (scanStatus.isGranted || scanStatus.isLimited) &&
          (connectStatus.isGranted || connectStatus.isLimited);
    }
    return true;
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    await requestPermissions();
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
    await FlutterBluePlus.startScan(
      withServices: [Guid(BleConstants.serviceUuid)],
      timeout: timeout,
    );
  }

  Future<void> stopScan() async {
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
  }

  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;

  Future<MeshXDeviceInfo?> connect(
    BluetoothDevice device, {
    void Function(BluetoothConnectionState)? onStateChange,
  }) async {
    // Reset any lingering or stale GATT connection before establishing a new one
    try {
      if (_connectedDevice != null && _connectedDevice!.remoteId != device.remoteId) {
        await _connectedDevice!.disconnect().timeout(const Duration(milliseconds: 500));
      }
      await device.disconnect().timeout(const Duration(milliseconds: 500));
    } catch (_) {}

    _cleanupCharacteristics();
    _connectedDevice = device;

    // Listen to connection state
    _connStateSubscription?.cancel();
    _connStateSubscription = device.connectionState.listen((state) {
      onStateChange?.call(state);
      if (state == BluetoothConnectionState.disconnected) {
        _cleanupCharacteristics();
      }
    });

    // Connect with autoConnect false and 8-second safety timeout
    await device.connect(
      timeout: const Duration(seconds: 8),
      autoConnect: false,
      license: License.nonprofit,
    );

    // Request balanced connection priority so Android does not kill BLE link in background
    try {
      await device.requestConnectionPriority(
        connectionPriorityRequest: ConnectionPriority.balanced,
      ).timeout(const Duration(seconds: 2));
    } catch (_) {}

    // Request MTU up to 256 bytes and store negotiated ATT MTU
    _negotiatedMtu = 23;
    try {
      final mtu = await device.requestMtu(256).timeout(const Duration(seconds: 2));
      if (mtu >= 23) _negotiatedMtu = mtu;
    } catch (_) {
      try {
        final cur = device.mtuNow;
        if (cur >= 23) _negotiatedMtu = cur;
      } catch (_) {}
    }

    // Discover services with 6-second timeout
    final services = await device.discoverServices().timeout(
      const Duration(seconds: 6),
      onTimeout: () => throw TimeoutException('GATT service discovery timed out'),
    );

    final targetService = services.firstWhere(
      (s) => s.uuid.toString().toUpperCase() == BleConstants.serviceUuid.toUpperCase(),
      orElse: () => throw Exception('MESH-X Service not found on device'),
    );

    // Locate characteristics
    for (final char in targetService.characteristics) {
      final uuidStr = char.uuid.toString().toUpperCase();
      if (uuidStr == BleConstants.charDeviceInfoUuid.toUpperCase()) {
        _deviceInfoChar = char;
      } else if (uuidStr == BleConstants.charCommandInUuid.toUpperCase()) {
        _cmdInChar = char;
      } else if (uuidStr == BleConstants.charEventOutUuid.toUpperCase()) {
        _eventOutChar = char;
      } else if (uuidStr == BleConstants.charTelemetryUuid.toUpperCase()) {
        _telemetryChar = char;
      }
    }

    // Subscribe to Event Out notifications with timeout
    if (_eventOutChar != null) {
      try {
        await _eventOutChar!.setNotifyValue(true).timeout(
          const Duration(seconds: 3),
        );
        _eventSubscription?.cancel();
        _eventSubscription = _eventOutChar!.onValueReceived.listen((data) {
          _handleRawEventFrame(data);
        });
      } catch (_) {}
    }

    // Subscribe to Telemetry notifications with timeout
    if (_telemetryChar != null) {
      try {
        await _telemetryChar!.setNotifyValue(true).timeout(
          const Duration(seconds: 3),
        );
        _telemetrySubscription?.cancel();
        _telemetrySubscription = _telemetryChar!.onValueReceived.listen((data) {
          try {
            final jsonStr = utf8.decode(data);
            final map = jsonDecode(jsonStr) as Map<String, dynamic>;
            _telemetryController.add(map);
          } catch (_) {}
        });
      } catch (_) {}
    }

    // Read Device Info with timeout and fallback
    MeshXDeviceInfo? deviceInfo;
    if (_deviceInfoChar != null) {
      try {
        final rawInfo = await _deviceInfoChar!.read().timeout(
          const Duration(seconds: 3),
        );
        final infoJson = utf8.decode(rawInfo);
        final map = jsonDecode(infoJson) as Map<String, dynamic>;
        deviceInfo = MeshXDeviceInfo.fromJson(map);
      } catch (_) {
        deviceInfo = MeshXDeviceInfo(
          nodeId: 0,
          firmwareVersion: '1.3.0',
          protocolVersion: 1,
          deviceName: device.platformName.isNotEmpty ? device.platformName : 'MESH-X Node',
        );
      }
    }

    // Remember connected device ID
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(BleConstants.prefLastDeviceId, device.remoteId.str);

    _connectionController.add(true);
    return deviceInfo;
  }

  Future<void> disconnect() async {
    _cleanupCharacteristics();
    _connectionController.add(false);
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect().timeout(const Duration(seconds: 2));
      } catch (_) {}
      _connectedDevice = null;
    }
  }

  void _cleanupCharacteristics() {
    _eventSubscription?.cancel();
    _telemetrySubscription?.cancel();
    _connStateSubscription?.cancel();
    _eventSubscription = null;
    _telemetrySubscription = null;
    _connStateSubscription = null;
    _cmdInChar = null;
    _eventOutChar = null;
    _telemetryChar = null;
    _deviceInfoChar = null;
    _negotiatedMtu = 23;
  }

  Future<bool> sendCommand(int cmdType, [Uint8List? payload]) {
    final completer = Completer<bool>();
    _writeChain = _writeChain.then((_) async {
      final ok = await _sendCommandInternal(cmdType, payload);
      if (!completer.isCompleted) completer.complete(ok);
    }).catchError((_) {
      if (!completer.isCompleted) completer.complete(false);
    });
    return completer.future;
  }

  Future<bool> _sendCommandInternal(int cmdType, [Uint8List? payload]) async {
    if (_cmdInChar == null || _connectedDevice == null) return false;

    final data = payload ?? Uint8List(0);
    _cmdSeq = (_cmdSeq + 1) & 0xFFFF;
    final seq = _cmdSeq;

    // Max ATT write payload = MTU - 3; BleFrameHeader (10B) + CRC16 (2B) = 12B overhead
    final maxFragData = max(8, _negotiatedMtu - 3 - 12);
    final fragCount = data.isEmpty ? 1 : (data.length / maxFragData).ceil();
    if (fragCount > 255) return false;

    final useWithoutResponse = !_cmdInChar!.properties.write;

    try {
      for (int fragIdx = 0; fragIdx < fragCount; fragIdx++) {
        if (_cmdInChar == null) return false;
        final start = fragIdx * maxFragData;
        final end = data.isEmpty ? 0 : min(start + maxFragData, data.length);
        final chunkLen = end - start;

        final buffer = Uint8List(10 + chunkLen + 2);
        final byteData = ByteData.sublistView(buffer);

        byteData.setUint8(0, BleConstants.magicByte0);
        byteData.setUint8(1, BleConstants.magicByte1);
        byteData.setUint8(2, BleConstants.protocolVersion);
        byteData.setUint8(3, cmdType);
        byteData.setUint16(4, seq, Endian.little);
        byteData.setUint16(6, data.length, Endian.little);
        byteData.setUint8(8, fragIdx);
        byteData.setUint8(9, fragCount);

        if (chunkLen > 0) {
          buffer.setRange(10, 10 + chunkLen, data, start);
        }

        final crc = Crc16.compute(buffer, 10 + chunkLen);
        byteData.setUint16(10 + chunkLen, crc, Endian.little);

        await _cmdInChar!
            .write(buffer, withoutResponse: useWithoutResponse)
            .timeout(const Duration(seconds: 3));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  void _handleRawEventFrame(List<int> raw) {
    if (raw.length < 12) return;
    final bytes = Uint8List.fromList(raw);
    final bd = ByteData.sublistView(bytes);

    // Validate magic
    if (bytes[0] != BleConstants.magicByte0 || bytes[1] != BleConstants.magicByte1) {
      return;
    }

    // Validate CRC
    final expectedCrc = Crc16.compute(bytes, bytes.length - 2);
    final receivedCrc = bd.getUint16(bytes.length - 2, Endian.little);
    if (expectedCrc != receivedCrc) {
      return;
    }

    _eventController.add(raw);
  }

  Future<bool> sendRadioConfig(RadioConfigModel config) async {
    await saveRadioConfig(config);
    return sendCommand(BleConstants.cmdSetRadioConfig, config.toBytes());
  }

  static const String prefRadioConfig = 'mesh_x_radio_config';

  Future<void> saveRadioConfig(RadioConfigModel config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefRadioConfig, jsonEncode(config.toMap()));
  }

  Future<RadioConfigModel> loadRadioConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(prefRadioConfig);
    if (jsonStr != null) {
      try {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        return RadioConfigModel.fromMap(map);
      } catch (_) {}
    }
    return const RadioConfigModel();
  }

  Future<String?> getSavedDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(BleConstants.prefLastDeviceId);
  }

  Future<void> forgetSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(BleConstants.prefLastDeviceId);
  }
}
