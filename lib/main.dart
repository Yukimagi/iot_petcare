import 'dart:async';
import 'dart:convert';
import 'dart:io';                   // ← 新增
import 'package:flutter/material.dart';
import 'mqtt_service.dart';
import 'ble_service.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'IoT PetCare',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const HomePage(),
      );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PetCare IoT')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SensorPage()),
              ),
              child: const Text('LoRa        Mode'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BlePage()),
              ),
              child: const Text('BlueTooth Mode'),
            ),
          ],
        ),
      ),
    );
  }
}

// --- LoRa 頁面 (與先前 SensorPage 相同) ---
class SensorPage extends StatefulWidget {
  const SensorPage({super.key});
  @override
  State<SensorPage> createState() => _SensorPageState();
}

class _SensorPageState extends State<SensorPage> {
  final _mqtt = MqttService();
  String _statusText = '尚未連線';
  double? _temp, _hum;
  final _downlinkController = TextEditingController();
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _mqtt.statusStream.listen((connected) {
      setState(() {
        _connected = connected;
        _statusText = connected ? '已連線' : '未連線';
      });
    });
    _mqtt.uplinkStream.listen((data) {
      setState(() {
        _temp = data['temperature'];
        _hum = data['humidity'];
      });
    });
    _mqtt.connect();
  }

  @override
  void dispose() {
    _mqtt.dispose();
    _downlinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PetCare-LoRa')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MQTT 狀態: $_statusText'),
            const SizedBox(height: 12),
            if (_temp != null && _hum != null) ...[
              Text('溫度: ${_temp!.toStringAsFixed(2)} °C'),
              Text('濕度: ${_hum!.toStringAsFixed(2)} %'),
            ] else
              const Text('等待上行資料…'),
            const Divider(height: 32),
            TextField(
              controller: _downlinkController,
              decoration: const InputDecoration(
                labelText: '輸入下行代碼 (30 或 31)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _connected
                  ? () {
                      final code = _downlinkController.text.trim();
                      if (code == '30' || code == '31') {
                        _mqtt.sendDownlink(code);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('請輸入 30 或 31')),
                        );
                      }
                    }
                  : null,
              child: const Text('送出 Downlink'),
            ),
          ],
        ),
      ),
    );
  }
}

// --- 藍芽 頁面 ---
class BlePage extends StatefulWidget {
  const BlePage({super.key});
  @override
  State<BlePage> createState() => _BlePageState();
}

class _BlePageState extends State<BlePage> {
  final _ble = BleService();
  String _statusText = '尚未連線';
  double? _temp, _hum;
  StreamSubscription<void>? _queryTimer;            // ← 定時向裝置查詢

  @override
  void initState() {
    super.initState();
    _ble.statusStream.listen((connected) {
      setState(() => _statusText = connected ? '已連線' : '未連線');

            // 2. 連上後每 5 秒主動寫「查詢溫濕度」指令
      _queryTimer?.cancel();
      if (connected) {
        _queryTimer = Stream.periodic(const Duration(seconds: 5))
            .listen((_) => _ble.queryTemperatureHumidity());
      }
    });

    
    _ble.dataStream.listen((data) {
      setState(() {
        if (data.containsKey('temperature')) _temp = data['temperature'];
        if (data.containsKey('humidity')) _hum = data['humidity'];
      });
    });
    _ble.startScanAndConnect();
  }

  @override
  void dispose() {
    _ble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Petcare-BLE')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('BLE 狀態: $_statusText'),
            const SizedBox(height: 12),
            if (_temp != null) Text('溫度: ${_temp!.toStringAsFixed(2)} °C'),
            if (_hum != null) Text('濕度: ${_hum!.toStringAsFixed(2)} %'),
            if (_temp == null && _hum == null)
              const Text('等待藍芽資料…'),
          ],
        ),
      ),
    );
  }
}
