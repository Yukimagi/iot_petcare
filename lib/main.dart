import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

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
  Widget build(BuildContext context) => Scaffold(
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

// ────────────────────────────────────────────────────────────────
// LoRa 頁面
// ────────────────────────────────────────────────────────────────
class SensorPage extends StatefulWidget {
  const SensorPage({super.key});
  @override
  State<SensorPage> createState() => _SensorPageState();
}

class _SensorPageState extends State<SensorPage> {
  final _mqtt = MqttService();
  String _statusText = '尚未連線';

  double? _temp, _hum;
  int? _sit, _stand, _lying;

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
        _sit = data['sitting'];
        _stand = data['standing'];
        _lying = data['lying'];
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
  Widget build(BuildContext context) => Scaffold(
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
                const SizedBox(height: 8),
                Text('姿態 ≫ 坐著: $_sit, 站著: $_stand, 躺著: $_lying'),
              ] else
                const Text('等待上行資料…'),
              const Divider(height: 32),
              
              const SizedBox(height: 24),
              Center(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.history),
                  label: const Text('查看歷史紀錄'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HistoryPage()),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
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
  String _lastRaw = '';                     // 👈 新增：顯示最後一筆原始回傳
  final _cmdCtrl = TextEditingController(); // 👈 新增：輸入框

  @override
  void initState() {
    super.initState();

    // 1. 監聽連線狀態
    _ble.statusStream.listen((connected) {
      setState(() => _statusText = connected ? '已連線' : '未連線');
    });

    // 2. 監聽解析後的溫濕度
    _ble.dataStream.listen((data) {
      setState(() {
        if (data.containsKey('temperature')) _temp = data['temperature'];
        if (data.containsKey('humidity')) _hum = data['humidity'];
      });
    });

    // 3. 監聽原始字串
    _ble.rawStream.listen((txt) {
      setState(() => _lastRaw = txt);
    });

    _ble.startScanAndConnect();
  }

  @override
  void dispose() {
    _cmdCtrl.dispose();
    _ble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _statusText == '已連線';

    return Scaffold(
      appBar: AppBar(title: const Text('Petcare-BLE')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('BLE 狀態: $_statusText'),
            const SizedBox(height: 12),

            // ---- 解析後的數值 ----
            if (_temp != null) Text('溫度: ${_temp!.toStringAsFixed(2)} °C'),
            if (_hum != null)  Text('濕度: ${_hum!.toStringAsFixed(2)} %'),
            if (_temp == null && _hum == null)
              const Text('等待藍芽資料…'),

            const Divider(height: 32),

            // ---- 新增：輸入框 + 送出 ----
            TextField(
              controller: _cmdCtrl,
              decoration: const InputDecoration(
                labelText: '輸入指令，例如「查詢溫濕度」',
                border: OutlineInputBorder(),
              ),
              enabled: connected,
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: connected
                  ? () {
                      final cmd = _cmdCtrl.text.trim();
                      if (cmd.isEmpty) return;
                      _ble.sendCommand(cmd);
                    }
                  : null,
              child: const Text('送出指令'),
            ),

            const Divider(height: 32),

            // ---- 顯示回傳的原始字串 ----
            Text('最後回傳:'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(_lastRaw.isEmpty ? '（尚無資料）' : _lastRaw),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────
// 歷史紀錄頁面：讀取 / 清空 CSV
// ────────────────────────────────────────────────────────────────
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late Future<List<List<String>>> _recordsFuture;

  @override
  void initState() {
    super.initState();
    _recordsFuture = _loadCsv();
  }

  // ---------- 讀取 ----------
  Future<List<List<String>>> _loadCsv() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/petcare_history.csv');
    if (!await file.exists()) return [];
    final lines = await file.readAsLines();
    return lines.skip(1).map((e) => e.split(',')).toList().reversed.toList();
  }

  // ---------- 清空 ----------
  Future<void> _clearCsv() async {
    final dir  = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/petcare_history.csv');

    if (await file.exists()) {
      await file.writeAsString('timestamp,temp,hum,sitting,standing,lying\n');
    }

    if (!mounted) return;            // widget 仍存在才更新
    setState(() {                    // ← 改成大括號，不回傳任何值
      _recordsFuture = Future.value([]);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清空紀錄')),
    );
  }


  // ---------- UI ----------
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('歷史紀錄'),
          actions: [
            IconButton(
              tooltip: '清空紀錄',
              icon: const Icon(Icons.delete_forever),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('確認清空？'),
                    content: const Text('此動作將移除所有歷史紀錄！'),
                    actions: [
                      TextButton(
                        child: const Text('取消'),
                        onPressed: () => Navigator.pop(ctx, false),
                      ),
                      TextButton(
                        child: const Text('確定'),
                        onPressed: () => Navigator.pop(ctx, true),
                      ),
                    ],
                  ),
                );
                if (ok == true) _clearCsv();
              },
            ),
          ],
        ),
        body: FutureBuilder<List<List<String>>>(
          future: _recordsFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final records = snap.data ?? [];
            if (records.isEmpty) {
              return const Center(child: Text('尚無紀錄'));
            }
            return ListView.separated(
              itemCount: records.length,
              separatorBuilder: (_, __) => const Divider(height: 0),
              itemBuilder: (_, idx) {
                final r = records[idx];
                final ts = DateTime.parse(r[0])
                    .toLocal()
                    .toString()
                    .replaceFirst('.000', '');
                return ListTile(
                  leading: Text(
                    (records.length - idx).toString(),
                    style: const TextStyle(fontSize: 12),
                  ),
                  title: Text(ts),
                  subtitle: Text(
                      'T:${r[1]}°C  H:${r[2]}%  坐:${r[3]}  站:${r[4]}  躺:${r[5]}'),
                );
              },
            );
          },
        ),
      );
}
