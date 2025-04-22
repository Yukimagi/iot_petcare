import 'dart:async';
import 'dart:convert';
import 'dart:io';                   // ← 新增
import 'package:flutter/material.dart';
import 'mqtt_service.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Flutter Demo',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const SensorPage(),
      );
}

class SensorPage extends StatefulWidget {
  const SensorPage({super.key});
  @override
  State<SensorPage> createState() => _SensorPageState();
}

class _SensorPageState extends State<SensorPage> {
  final _mqtt = MqttService();
  String _statusText = '尚未連線';
  String _tcpTestResult = '尚未測試';   // 新增：TCP 測試結果
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

  // 新增：TCP 直連測試函式
  Future<void> _testBrokerTCP() async {
    setState(() => _tcpTestResult = '測試中...');
    try {
      final socket = await Socket.connect(
        '140.127.221.250', 
        1883, 
        timeout: const Duration(seconds: 5),
      );
      socket.destroy();
      setState(() => _tcpTestResult = '✅ 1883 可連線');
    } catch (e) {
      setState(() => _tcpTestResult = '❌ 無法連線: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DHT Uplink/Downlink')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // MQTT 連線狀態
            Text('MQTT 狀態: $_statusText'),
            const SizedBox(height: 8),
            // TCP 直連測試
            Row(
              children: [
                ElevatedButton(
                  onPressed: _testBrokerTCP,
                  child: const Text('測試 Broker TCP 1883'),
                ),
                const SizedBox(width: 12),
                Text(_tcpTestResult),
              ],
            ),

            const Divider(height: 32),

            // 顯示上行的溫濕度
            if (_temp != null && _hum != null) ...[
              Text('溫度: ${_temp!.toStringAsFixed(2)} °C'),
              Text('濕度: ${_hum!.toStringAsFixed(2)} %'),
            ] else
              const Text('等待上行資料…'),

            const Divider(height: 32),

            // 下行輸入框 + 按鈕
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
