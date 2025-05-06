import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BleService {
  // ★ 1. 依你的 Arduino/Nordic 程式設定
  static const _deviceName   = 'petcare'; // 參考 advdata.addCompleteName("petcare")
  static const _serviceUuid  = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';
  static const _rxUuid       = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E'; // 寫指令
  static const _txUuid       = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E'; // 通知

  // ---- Streams ---------------------------------------------------------
  final _statusCtrl = StreamController<bool>.broadcast();
  Stream<bool> get statusStream => _statusCtrl.stream;

  final _dataCtrl = StreamController<Map<String, double>>.broadcast();
  Stream<Map<String, double>> get dataStream => _dataCtrl.stream;

  /// 新增：裝置「完整字串」回傳
  final _rawCtrl = StreamController<String>.broadcast();
  Stream<String> get rawStream => _rawCtrl.stream;

  // ---- 私有變數 ---------------------------------------------------------
  StreamSubscription<List<ScanResult>>? _scanSub;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _rxChar;
  BluetoothCharacteristic? _txChar;
  StreamSubscription<List<int>>? _txNotifySub;

  // ---- 外部 API ---------------------------------------------------------
  /// 掃描並自動連線
  Future<void> startScanAndConnect() async {
    // (A) 先確認藍牙權限 & 介面
    await _ensureAdapterIsOn();

    // (B) 開掃描
    FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 6),
      androidUsesFineLocation: true,
    );

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (r.device.name == _deviceName) {
          _log('找到裝置 ${r.device.remoteId}');
          FlutterBluePlus.stopScan();
          _scanSub?.cancel();
          _connect(r.device);
          break;
        }
      }
    });
  }

  /// 通用：寫入任意指令
  Future<void> sendCommand(String cmd) async {
    if (_rxChar == null) return;
    try {
      await _rxChar!.write(utf8.encode(cmd), withoutResponse: false);
      _log('>> 已送出指令: $cmd');
    } catch (e) {
      _log('寫入失敗 $e');
    }
  }

  /// （保留舊函式）查詢溫濕度
  Future<void> queryTemperatureHumidity() => sendCommand('查詢溫濕度');

  /// 關閉所有資源
  Future<void> dispose() async {
    _scanSub?.cancel();
    _txNotifySub?.cancel();
    if (_device != null) await _device!.disconnect();
    await _statusCtrl.close();
    await _dataCtrl.close();
    await _rawCtrl.close();
  }

  // ---- 核心流程 ---------------------------------------------------------
  Future<void> _connect(BluetoothDevice dev) async {
    _device = dev;
    try {
      await dev.connect(autoConnect: false, timeout: const Duration(seconds: 8));
    } catch (_) {
      // Already connected 會丟 IllegalState；忽略即可
    }
    _statusCtrl.add(true);

    // (1) 探索 Service & Characteristics
    final svcs = await dev.discoverServices();
    for (final s in svcs) {
      if (s.uuid.str == _serviceUuid.toLowerCase()) {
        for (final c in s.characteristics) {
          if (c.uuid.str == _rxUuid.toLowerCase()) _rxChar = c;
          if (c.uuid.str == _txUuid.toLowerCase()) _txChar = c;
        }
      }
    }
    if (_rxChar == null || _txChar == null) {
      _log('缺少 Rx/Tx characteristic，結束連線');
      await dev.disconnect();
      _statusCtrl.add(false);
      return;
    }

    // (2) 開啟 Tx notify
    await _txChar!.setNotifyValue(true);
    _txNotifySub = _txChar!.onValueReceived!.listen(_handleNotify);

    // (3) 連線後自動查詢一次
    await queryTemperatureHumidity();
  }

  void _handleNotify(List<int> value) {
    final text = utf8.decode(value);
    _rawCtrl.add(text); // ★ 推送原始字串給 UI

    // 嘗試解析：「濕度: 55.00%	溫度: 23.45°C」
    final reg = RegExp(r'濕度:\s*([\d.]+).*?溫度:\s*([\d.]+)');
    final m   = reg.firstMatch(text);
    if (m != null) {
      final hum  = double.parse(m.group(1)!);
      final temp = double.parse(m.group(2)!);
      _dataCtrl.add({'temperature': temp, 'humidity': hum});
      _log('收到 -> T=$temp, H=$hum');
    } else {
      _log('收到無法解析資料: $text');
    }
  }

  // ---- 小工具 -----------------------------------------------------------
  Future<void> _ensureAdapterIsOn() async {
    // === 1. 請求「位置權限」（Android 11↓ 掃描 BLE 必須） ===
    final status = await Permission.locationWhenInUse.request();
    if (!status.isGranted) {
      throw Exception('需要位置權限才能掃描藍芽裝置');
    }

    // === 2. 確保藍芽已打開 ===
    await FlutterBluePlus.turnOn(); // 顯示系統藍芽開啟對話框
    while (await FlutterBluePlus.adapterState.first !=
        BluetoothAdapterState.on) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  void _log(Object o) => print('[BleService] $o');
}
