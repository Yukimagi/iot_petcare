import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'mqtt_service.dart';
import 'ble_service.dart';

void main() => runApp(const MyApp());

/// ────────────────────────────────────────────────────────────────
/// 全域主題
/// ────────────────────────────────────────────────────────────────
class AppTheme {
  static final color  = Colors.deepPurple;
  static final scheme = ColorScheme.fromSeed(seedColor: color, brightness: Brightness.light);

  static ThemeData data = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF5F6FA),   // ★ 統一頁面底色
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(180, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
    ),
    appBarTheme: const AppBarTheme(centerTitle: true),
  );
}


/// ────────────────────────────────────────────────────────────────
/// 共用：帶陰影圓角卡片
/// ────────────────────────────────────────────────────────────────
class InfoCard extends StatelessWidget {
  const InfoCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

/// ────────────────────────────────────────────────────────────────
/// MyApp
/// ────────────────────────────────────────────────────────────────
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'IoT PetCare',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.data,
        home: const HomePage(),
      );
}

/// ────────────────────────────────────────────────────────────────
/// 首頁
/// ────────────────────────────────────────────────────────────────
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFB388FF), Color(0xFF7C4DFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'PetCare IoT',
                  style: TextStyle(
                    fontSize: 42,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 40),
                ElevatedButton.icon(
                  icon: const Icon(Icons.sensors, size: 28),
                  label: const Text('LoRa  Mode'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SensorPage()),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  icon: const Icon(Icons.bluetooth, size: 28),
                  label: const Text('BLE   Mode'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BlePage()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ────────────────────────────────────────────────────────────────
/// LoRa 頁面
/// ────────────────────────────────────────────────────────────────
class SensorPage extends StatefulWidget {
  const SensorPage({super.key});
  @override
  State<SensorPage> createState() => _SensorPageState();
}

class _SensorPageState extends State<SensorPage> {
  final _mqtt = MqttService();
  bool _connected = false;

  double? _temp, _hum;
  int? _sit, _stand, _lying;

  @override
  void initState() {
    super.initState();
    _mqtt.statusStream.listen((c) => setState(() => _connected = c));
    _mqtt.uplinkStream.listen((d) {
      setState(() {
        _temp = d['temperature'];
        _hum = d['humidity'];
        _sit = d['sitting'];
        _stand = d['standing'];
        _lying = d['lying'];
      });
    });
    _mqtt.connect();
  }

  @override
  void dispose() {
    _mqtt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusChip = Chip(
      label: Text(_connected ? '已連線' : '未連線'),
      avatar: Icon(
        _connected ? Icons.check_circle : Icons.cancel,
        color: _connected ? Colors.green : Colors.red,
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('LoRa 感測')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            InfoCard(child: Row(children: [const Text('MQTT 狀態 : '), statusChip])),
            InfoCard(
              child: _temp == null
                  ? const Text('等待上行資料…', style: TextStyle(fontSize: 18))
                  : Column(
                      children: [
                        _ValueRow(icon: Icons.thermostat, label: '溫度', value: '${_temp!.toStringAsFixed(2)} °C'),
                        const SizedBox(height: 8),
                        _ValueRow(icon: Icons.water_drop, label: '濕度', value: '${_hum!.toStringAsFixed(2)} %'),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _PostureBadge('坐', _sit),
                            _PostureBadge('站', _stand),
                            _PostureBadge('躺', _lying),
                          ],
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.history),
              label: const Text('查看歷史紀錄'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ────────────────────────────────────────────────────────────────
/// BLE 頁面
/// ────────────────────────────────────────────────────────────────
class BlePage extends StatefulWidget {
  const BlePage({super.key});
  @override
  State<BlePage> createState() => _BlePageState();
}

class _BlePageState extends State<BlePage> {
  final _ble = BleService();
  bool get _connected => _status == '已連線';
  String _status = '尚未連線';
  double? _temp, _hum;
  String _lastRaw = '';
  final _cmdCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ble.statusStream.listen((c) => setState(() => _status = c ? '已連線' : '未連線'));
    _ble.dataStream.listen((d) => setState(() {
          _temp = d['temperature'];
          _hum = d['humidity'];
        }));
    _ble.rawStream.listen((txt) => setState(() => _lastRaw = txt));
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
    return Scaffold(
      appBar: AppBar(title: const Text('BLE 控制')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            InfoCard(
              child: Row(
                children: [
                  const Text('BLE 狀態 : '),
                  Chip(
                    label: Text(_status),
                    avatar: Icon(
                      _connected ? Icons.check_circle : Icons.cancel,
                      color: _connected ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
            InfoCard(
              child: _temp == null
                  ? const Text('等待藍芽資料…', style: TextStyle(fontSize: 18))
                  : Column(
                      children: [
                        _ValueRow(icon: Icons.thermostat, label: '溫度', value: '${_temp!.toStringAsFixed(2)} °C'),
                        const SizedBox(height: 8),
                        _ValueRow(icon: Icons.water_drop, label: '濕度', value: '${_hum!.toStringAsFixed(2)} %'),
                      ],
                    ),
            ),
            InfoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _cmdCtrl,
                    decoration: const InputDecoration(
                      labelText: '輸入指令，例如「查詢溫濕度」',
                      border: OutlineInputBorder(),
                    ),
                    enabled: _connected,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: _connected
                          ? () {
                              final cmd = _cmdCtrl.text.trim();
                              if (cmd.isNotEmpty) _ble.sendCommand(cmd);
                            }
                          : null,
                      child: const Text('送出'),
                    ),
                  ),
                ],
              ),
            ),
            InfoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('最後回傳:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(
                    _lastRaw.isEmpty ? '（尚無資料）' : _lastRaw,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ────────────────────────────────────────────────────────────────
/// 歷史紀錄頁面
/// ────────────────────────────────────────────────────────────────
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

  Future<List<List<String>>> _loadCsv() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/petcare_history.csv');
    if (!await file.exists()) return [];
    final lines = await file.readAsLines();
    return lines.skip(1).map((e) => e.split(',')).toList().reversed.toList();
  }

  Future<void> _clearCsv() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/petcare_history.csv');
    if (await file.exists()) {
      await file.writeAsString('timestamp,temp,hum,sitting,standing,lying\n');
    }
    if (!mounted) return;
    setState(() => _recordsFuture = Future.value([]));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清空紀錄')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('歷史紀錄')),
      floatingActionButton: FloatingActionButton(
        tooltip: '清空紀錄',
        child: const Icon(Icons.delete_forever),
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('清空全部紀錄？'),
              content: const Text('此動作將無法復原！'),
              actions: [
                TextButton(child: const Text('取消'), onPressed: () => Navigator.pop(ctx, false)),
                TextButton(child: const Text('確定'), onPressed: () => Navigator.pop(ctx, true)),
              ],
            ),
          );
          if (ok == true) _clearCsv();
        },
      ),
      body: FutureBuilder<List<List<String>>>(
        future: _recordsFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data ?? [];
          if (rows.isEmpty) return const Center(child: Text('尚無紀錄'));
          return Scrollbar(                       // 🍥 方便拖曳
          thumbVisibility: true,                //   （可自行移除）
          child: SingleChildScrollView(         // ← 垂直滾動
            padding: const EdgeInsets.only(bottom: 80),
            child: SingleChildScrollView(       // ← 水平滾動
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('時間')),
                  DataColumn(label: Text('溫度')),
                  DataColumn(label: Text('濕度')),
                  DataColumn(label: Text('坐')),
                  DataColumn(label: Text('站')),
                  DataColumn(label: Text('躺')),
                ],
                rows: List.generate(rows.length, (i) {
                  final r  = rows[i];
                  final ts = DateTime.parse(r[0]).toLocal().toString().replaceFirst('.000', '');
                  return DataRow(cells: [
                    DataCell(Text('${rows.length - i}')),
                    DataCell(Text(ts)),
                    DataCell(Text('${r[1]}°C')),
                    DataCell(Text('${r[2]}%')),
                    DataCell(Text(r[3])),
                    DataCell(Text(r[4])),
                    DataCell(Text(r[5])),
                  ]);
                }),
              ),
            ),
          ),
        );

        },
      ),
    );
  }
}

/// ────────────────────────────────────────────────────────────────
/// 小工具：數值列 & 姿態 Badge
/// ────────────────────────────────────────────────────────────────
class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: AppTheme.color),
          const SizedBox(width: 6),
          Text('$label: ', style: const TextStyle(fontSize: 18)),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ],
      );
}

class _PostureBadge extends StatelessWidget {
  const _PostureBadge(this.label, this.count);
  final String label;
  final int? count;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          CircleAvatar(
            backgroundColor: AppTheme.color.withOpacity(0.15),
            child: Text(label, style: TextStyle(color: AppTheme.color, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 4),
          Text(count?.toString() ?? '-', style: const TextStyle(fontSize: 16)),
        ],
      );
}
