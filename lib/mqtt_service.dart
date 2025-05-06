import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  final MqttServerClient _client =
      MqttServerClient('140.127.221.250', 'flutter_client');
  final String subTopic = 'GIOT-GW/UL/80029C1E38D2';
  final String pubTopic = 'GIOT-GW/DL/000080029c0ff65e';
  final String targetMac = '0000000020200014';//要改14

  // 將狀態也做成一個 Stream
  final _statusController = StreamController<bool>.broadcast();
  Stream<bool> get statusStream => _statusController.stream;

  final _uplinkController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get uplinkStream => _uplinkController.stream;

  MqttService() {
    _client.port = 1883;
    _client.logging(on: false);
    _client.keepAlivePeriod = 20;
    _client.onConnected = _onConnected;
    _client.onDisconnected = _onDisconnected;
    _client.onSubscribed = _onSubscribed;
  }

  Future<void> connect() async {
    // 每次都拿新狀態
    _client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier('flutter_client')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    try {
      await _client.connect();
    } catch (e) {
      print('MQTT connect error: $e');
      _client.disconnect();
      // 連線失敗也要推送狀態
      _statusController.add(false);
    }
  }

  void _onConnected() {
    print('MQTT 已連線');
    _statusController.add(true);             // ← 真正連線後才報「已連線」
    _client.subscribe(subTopic, MqttQos.atMostOnce);
    _client.updates?.listen(_onMessage);
  }

  void _onDisconnected() {
    print('MQTT 已斷線');
    _statusController.add(false);            // ← 斷線時報「未連線」
  }

  void _onSubscribed(String topic) {
    print('已訂閱主題：$topic');
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> c) {
    final msg = c.first.payload as MqttPublishMessage;
    final payload = MqttPublishPayload.bytesToStringAsString(
      msg.payload.message,
    );
    if (!payload.contains('"macAddr":"$targetMac"')) return;

    final data = json.decode(payload);
    final first = (data is List ? data.first : data) as Map<String, dynamic>;
    final hex = first['data'] as String;
    final temp = int.parse(hex.substring(0, 4), radix: 16) / 100.0;
    final hum = int.parse(hex.substring(4), radix: 16) / 100.0;

    _uplinkController.add({'temperature': temp, 'humidity': hum});
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
}
