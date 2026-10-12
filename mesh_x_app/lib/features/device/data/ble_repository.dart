import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/ble_constants.dart';
import '../../../core/utils/crc16.dart';
import '../domain/device_info_model.dart';

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

  int _cmdSeq = 0;

  BluetoothDevice? get connectedDevice => _connectedDevice;

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
    _connectedDevice = device;

    // Listen to connection state
    _connStateSubscription?.cancel();
    _connStateSubscription = device.connectionState.listen((state) {
      onStateChange?.call(state);
      if (state == BluetoothConnectionState.disconnected) {
        _cleanupCharacteristics();
      }
    });

    await device.connect(
      timeout: const Duration(seconds: 15),
      license: License.nonprofit,
    );

    // Request MTU up to 256 bytes
    try {
      await device.requestMtu(256);
    } catch (_) {
      // MTU negotiation unsupported or platform-constrained
    }

    // Discover services
    final services = await device.discoverServices();
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

    // Subscribe to Event Out notifications
    if (_eventOutChar != null) {
      await _eventOutChar!.setNotifyValue(true);
      _eventSubscription?.cancel();
      _eventSubscription = _eventOutChar!.onValueReceived.listen((data) {
        _handleRawEventFrame(data);
      });
    }

    // Subscribe to Telemetry notifications
    if (_telemetryChar != null) {
      await _telemetryChar!.setNotifyValue(true);
      _telemetrySubscription?.cancel();
      _telemetrySubscription = _telemetryChar!.onValueReceived.listen((data) {
        try {
          final jsonStr = utf8.decode(data);
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;
          _telemetryController.add(map);
        } catch (_) {}
      });
    }

    // Read Device Info
    MeshXDeviceInfo? deviceInfo;
    if (_deviceInfoChar != null) {
      final rawInfo = await _deviceInfoChar!.read();
      final infoJson = utf8.decode(rawInfo);
      final map = jsonDecode(infoJson) as Map<String, dynamic>;
      deviceInfo = MeshXDeviceInfo.fromJson(map);
    }

    // Remember connected device ID
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(BleConstants.prefLastDeviceId, device.remoteId.str);

    return deviceInfo;
  }

  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _cleanupCharacteristics();
      _connectedDevice = null;
    }
  }

  void _cleanupCharacteristics() {
    _eventSubscription?.cancel();
    _telemetrySubscription?.cancel();
    _connStateSubscription?.cancel();
    _cmdInChar = null;
    _eventOutChar = null;
    _telemetryChar = null;
    _deviceInfoChar = null;
  }

  Future<bool> sendCommand(int cmdType, [Uint8List? payload]) async {
    if (_cmdInChar == null) return false;

    final data = payload ?? Uint8List(0);
    final totalLen = 10 + data.length + 2; // Header (10) + Payload + CRC (2)
    final buffer = Uint8List(totalLen);
    final byteData = ByteData.sublistView(buffer);

    _cmdSeq++;
    // Header
    byteData.setUint8(0, BleConstants.magicByte0);
    byteData.setUint8(1, BleConstants.magicByte1);
    byteData.setUint8(2, BleConstants.protocolVersion);
    byteData.setUint8(3, cmdType);
    byteData.setUint16(4, _cmdSeq, Endian.little);
    byteData.setUint16(6, data.length, Endian.little);
    byteData.setUint8(8, 0); // fragIndex
    byteData.setUint8(9, 1); // fragCount

    if (data.isNotEmpty) {
      buffer.setRange(10, 10 + data.length, data);
    }

    final crc = Crc16.compute(buffer, 10 + data.length);
    byteData.setUint16(10 + data.length, crc, Endian.little);

    await _cmdInChar!.write(buffer, withoutResponse: true);
    return true;
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

  Future<String?> getSavedDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(BleConstants.prefLastDeviceId);
  }

  Future<void> forgetSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(BleConstants.prefLastDeviceId);
  }
}
