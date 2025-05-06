import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:path_provider/path_provider.dart';

class MqttService {
  // === MQTT 連線設定 ===
  final MqttServerClient _client =
      MqttServerClient('140.127.221.250', 'flutter_client');
  final String subTopic = 'GIOT-GW/UL/80029C1E38D2';
  final String pubTopic = 'GIOT-GW/DL/000080029c0ff65e';
  final String targetMac = '0000000020200014';

  // === CSV 檔案設定 ===
  static const _csvFileName = 'petcare_history.csv';

  // === Streams ===
  final _statusController = StreamController<bool>.broadcast();
  Stream<bool> get statusStream => _statusController.stream;

  final _uplinkController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get uplinkStream => _uplinkController.stream;

  // === 建構 ===
  MqttService() {
    _client.port = 1883;
    _client.logging(on: false);
    _client.keepAlivePeriod = 20;
    _client.onConnected = _onConnected;
    _client.onDisconnected = _onDisconnected;
    _client.onSubscribed = _onSubscribed;
  }

  // === 對外 API ===
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
      _statusController.add(false);
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
    _statusController.close();
    _uplinkController.close();
    _client.disconnect();
  }

  // === 私有回呼 ===
  void _onConnected() async {
    print('MQTT 已連線');
    _statusController.add(true);
    _client.subscribe(subTopic, MqttQos.atMostOnce);
    _client.updates?.listen(_onMessage);

    // 若 CSV 不存在，建立並加標題列
    final file = await _getCsvFile();
    if (!await file.exists()) {
      await file.writeAsString(
        'timestamp,temp,hum,sitting,standing,lying\n',
        mode: FileMode.write,
      );
    }
  }

  void _onDisconnected() {
    print('MQTT 已斷線');
    _statusController.add(false);
  }

  void _onSubscribed(String topic) => print('已訂閱主題：$topic');

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> c) async {
    final msg = c.first.payload as MqttPublishMessage;
    final payload =
        MqttPublishPayload.bytesToStringAsString(msg.payload.message);

    if (!payload.contains('"macAddr":"$targetMac"')) return;

    try {
      final data = json.decode(payload);
      final first = (data is List ? data.first : data) as Map<String, dynamic>;
      final hex = first['data'] as String; // 20 個 hex 字元

      if (hex.length != 20) {
        print('[Error] 上行長度錯誤：$hex');
        return;
      }

      final temp = int.parse(hex.substring(0, 4), radix: 16) / 100.0;
      final hum = int.parse(hex.substring(4, 8), radix: 16) / 100.0;
      final sitting = int.parse(hex.substring(8, 12), radix: 16);
      final standing = int.parse(hex.substring(12, 16), radix: 16);
      final lying = int.parse(hex.substring(16, 20), radix: 16);

      // 推送給 UI
      _uplinkController.add({
        'temperature': temp,
        'humidity': hum,
        'sitting': sitting,
        'standing': standing,
        'lying': lying,
      });

      // 追加到 CSV
      await _appendCsv(
        DateTime.now(),
        temp,
        hum,
        sitting,
        standing,
        lying,
      );
    } catch (e) {
      print('[Error] 解析失敗：$e');
    }
  }

  // === CSV I/O ===
  Future<File> _getCsvFile() async {
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
  ) async {
    final file = await _getCsvFile();
    final line =
        '${ts.toIso8601String()},$temp,$hum,$sit,$stand,$lie\n';
    await file.writeAsString(line, mode: FileMode.append);
  }
}
