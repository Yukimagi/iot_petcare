import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:path_provider/path_provider.dart';

class MqttService {
  // === MQTT 設定 ===
  final _client = MqttServerClient('140.127.221.250', 'flutter_client');
  final String subTopic = 'GIOT-GW/UL/80029C1E38D2';
  final String pubTopic = 'GIOT-GW/DL/000080029c0ff65e';
  final String targetMac = '0000000020200014';

  // === CSV 設定 ===
  static const _csvFileName = 'petcare_history.csv';

  // === Streams ===
  final _statusCtrl = StreamController<bool>.broadcast();
  Stream<bool> get statusStream => _statusCtrl.stream;

  final _uplinkCtrl = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get uplinkStream => _uplinkCtrl.stream;

  // === ctor ===
  MqttService() {
    _client.port = 1883;
    _client.logging(on: false);
    _client.keepAlivePeriod = 20;
    _client.onConnected = _onConnected;
    _client.onDisconnected = _onDisconnected;
    _client.onSubscribed = _onSubscribed;
  }

  // ─────────────────────────────────────────────────────────────
  /// 外部 API
  // ─────────────────────────────────────────────────────────────
  Future<void> connect() async {
    _client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier('flutter_client')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    try {
      await _client.connect();
    } catch (e) {
      print('MQTT connect error: $e');
      _client.disconnect();
      _statusCtrl.add(false);
    }
  }

  void sendDownlink(String code) {
    if (_client.connectionStatus?.state != MqttConnectionState.connected) {
      print('無法發佈：MQTT 尚未連線');
      return;
    }
    final msg = json.encode([
      {
        'macAddr': targetMac,
        'data': code,
        'extra': {'port': 2, 'txpara': '2'}
      }
    ]);
    final builder = MqttClientPayloadBuilder()..addString(msg);
    _client.publishMessage(pubTopic, MqttQos.atMostOnce, builder.payload!);
    print('下行已發佈：$msg');
  }

  void dispose() {
    _statusCtrl.close();
    _uplinkCtrl.close();
    _client.disconnect();
  }

  // ─────────────────────────────────────────────────────────────
  /// 連線回呼
  // ─────────────────────────────────────────────────────────────
  void _onConnected() async {
    print('MQTT 已連線');
    _statusCtrl.add(true);
    _client.subscribe(subTopic, MqttQos.atMostOnce);
    _client.updates?.listen(_onMessage);

    // 若檔案不存在 → 建立＋標題列
    final f = await _file;
    if (!await f.exists()) {
      await f.writeAsString(
        'timestamp,temp,hum,sitting,standing,lying,miss\n',
      );
    }
  }

  void _onDisconnected() {
    print('MQTT 已斷線');
    _statusCtrl.add(false);
  }

  void _onSubscribed(String topic) => print('已訂閱：$topic');

  // ─────────────────────────────────────────────────────────────
  /// 收到上行資料
  // ─────────────────────────────────────────────────────────────
  void _onMessage(List<MqttReceivedMessage<MqttMessage>> events) async {
    final msg = events.first.payload as MqttPublishMessage;
    final payload = MqttPublishPayload.bytesToStringAsString(msg.payload.message);

    if (!payload.contains('"macAddr":"$targetMac"')) return;

    try {
      final obj = json.decode(payload);
      final map = (obj is List ? obj.first : obj) as Map<String, dynamic>;
      final hex = map['data'] as String;           // 24 hex chars

      if (hex.length != 24) {
        print('[Error] 長度錯誤：$hex');
        return;
      }

      final temp    = int.parse(hex.substring(0,  4), radix: 16) / 100;
      final hum     = int.parse(hex.substring(4,  8), radix: 16) / 100;
      final sitting = int.parse(hex.substring(8, 12), radix: 16);
      final standing= int.parse(hex.substring(12,16), radix: 16);
      final lying   = int.parse(hex.substring(16,20), radix: 16);
      final miss    = int.parse(hex.substring(20,24), radix: 16); // 0=在家

      // 推送 UI
      _uplinkCtrl.add({
        'temperature': temp,
        'humidity'   : hum,
        'sitting'    : sitting,
        'standing'   : standing,
        'lying'      : lying,
        'miss'       : miss,
      });

      // 寫入 CSV
      await _appendCsv(DateTime.now(), temp, hum, sitting, standing, lying, miss);
    } catch (e) {
      print('[Error] 解析失敗：$e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  /// CSV I/O
  // ─────────────────────────────────────────────────────────────
  Future<File> get _file async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_csvFileName');
  }

  Future<void> _appendCsv(
    DateTime ts,
    double temp,
    double hum,
    int sit,
    int stand,
    int lie,
    int miss,
  ) async {
    final f = await _file;
    final line =
        '${ts.toIso8601String()},$temp,$hum,$sit,$stand,$lie,$miss\n';
    await f.writeAsString(line, mode: FileMode.append);
  }
}
