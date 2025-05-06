int sitting = 0;
int standing = 0;
int lying = 0;
int miss=0;
static unsigned long lastScan = 0;

#include <Arduino.h>
#include <Wire.h>
#include "BLEDevice.h"
#include "DHT.h"
#include <Adafruit_OLED_libraries/Adafruit_GFX.h>
#include <Adafruit_OLED_libraries/Adafruit_SSD1306.h>
//----model-------------------------------------------------------------------------------
#include <WiFi.h>
WiFiSSLClient client;
#include "StreamIO.h"
#include "VideoStream.h"
#include "RTSP.h"
#include "NNObjectDetection.h"
#include "VideoStreamOverlay.h"
#define amb82_CHANNEL 0
#define CHANNELNN 3
#define NNWIDTH  576
#define NNHEIGHT 320
VideoSetting config(VIDEO_VGA, CAM_FPS, VIDEO_H264_JPEG, 1);
VideoSetting configNN(NNWIDTH, NNHEIGHT, 10, VIDEO_RGB, 0);
NNObjectDetection ObjDet;
RTSP rtsp;
StreamIO videoStreamer(1, 1);
StreamIO videoStreamerNN(1, 1);
int rtsp_portnum;
uint32_t img_addr = 0;
uint32_t img_len = 0;
//----beacon----
unsigned long last = 0;
BLEAdvertData foundDevice;

void scanFunction(T_LE_CB_DATA* p_data)
{
    foundDevice.parseScanInfo(p_data);

    if (foundDevice.hasName() && foundDevice.getName() == String("R23110009")) {
        Serial.println("📡 有接到");
        Serial.print("距離上次時間(ms): ");
        Serial.println(millis() - last);
        last = millis();
        Serial.print("📶 RSSI: ");
        Serial.println(foundDevice.getRSSI());
    }
}
//----------------------------------------------------
char _lwifi_ssid[] = "九";
char _lwifi_pass[] = "zxcvbnmlp";
void initWiFi() {

  for (int i=0;i<2;i++) {
    WiFi.begin(_lwifi_ssid, _lwifi_pass);

    delay(1000);
    Serial.println("");
    Serial.print("Connecting to ");
    Serial.println(_lwifi_ssid);

    long int StartTime=millis();
    while (WiFi.status() != WL_CONNECTED) {
        delay(500);
        if ((StartTime+5000) < millis()) break;
    }

    if (WiFi.status() == WL_CONNECTED) {
      Serial.println("");
      Serial.println("STAIP address: ");
      Serial.println(WiFi.localIP());
      Serial.println("");

      break;
    }
  }
}

#ifndef __OBJECTCLASSLIST_H__
#define __OBJECTCLASSLIST_H__
struct ObjectDetectionItem {
    uint8_t index;
    const char* objectName;
    uint8_t filter;
};
ObjectDetectionItem itemList[3] = {
    {0, "lying", 1},
    {1, "sitting", 1},
    {2, "standing", 1},
};
#endif

void ODPostProcess(std::vector<ObjectDetectionResult> results) {
    sitting = 0;
    standing = 0;
    lying = 0;
    uint16_t im_h = config.height();
    uint16_t im_w = config.width();
    OSD.createBitmap(amb82_CHANNEL);
    if (ObjDet.getResultCount() > 0) {
        for (int i = 0; i < ObjDet.getResultCount(); i++) {
            int obj_type = results[i].type();
            if (itemList[obj_type].filter) {
                ObjectDetectionResult item = results[i];
                int xmin = (int)(item.xMin() * im_w);
                int xmax = (int)(item.xMax() * im_w);
                int ymin = (int)(item.yMin() * im_h);
                int ymax = (int)(item.yMax() * im_h);
                //printf("Item %d %s:\t%d %d %d %d\n\r", i, itemList[obj_type].objectName, xmin, xmax, ymin, ymax);
                OSD.drawRect(amb82_CHANNEL, xmin, ymin, xmax, ymax, 3, OSD_COLOR_WHITE);
                char text_str[20];
                snprintf(text_str, sizeof(text_str), "%s %d", itemList[obj_type].objectName, item.score());
                OSD.drawText(amb82_CHANNEL, xmin, ymin - OSD.getTextHeight(amb82_CHANNEL), text_str, OSD_COLOR_CYAN);
  Serial.println((String(String(itemList[obj_type].objectName))+String(", ")+String(item.score())+String(", ")+String(xmin)+String(", ")+String(ymin)+String(", ")+String(xmax)+String(", ")+String(ymax)+String(", ")+String((xmax-xmin))+String(", ")+String((ymax-ymin))));
  if ((String(itemList[obj_type].objectName)=="sitting")) {
    sitting = sitting + 1;
  }
  if ((String(itemList[obj_type].objectName)=="standing")) {
    standing = standing + 1;
  }
  if ((String(itemList[obj_type].objectName)=="lying")) {
    lying = lying + 1;
  }
            }
        }
    }
  //Serial.println((String("物件數：")+String(ObjDet.getResultCount())+String(", 坐著：")+String(sitting)+String(",站著：")+String(standing)+String(",躺著：")+String(lying)));
  
    OSD.update(amb82_CHANNEL);
}
//-----------------------------------------------------------------------------------------

#define SCREEN_WIDTH 128	  //設定OLED螢幕的寬度像素
#define SCREEN_HEIGHT 64	  //設定OLED螢幕的寬度像素
#define OLED_RESET -1 		  //Reset pin如果OLED上沒有RESET腳位,將它設置為-1

#define UART_SERVICE_UUID      "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

#define STRING_BUF_SIZE 100

BLEService UartService(UART_SERVICE_UUID);
BLECharacteristic Rx(CHARACTERISTIC_UUID_RX);
BLECharacteristic Tx(CHARACTERISTIC_UUID_TX);
BLEAdvertData advdata;
BLEAdvertData scndata;
bool notify = false;

String lastCommand = "";  // 儲存來自手機的最後一個命令

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);
bool OLEDStatus = true;

static const unsigned char PROGMEM str_1[]={		 //溫
0x00,0x08,0x43,0xFC,0x32,0x08,0x12,0x08,0x83,0xF8,0x62,0x08,0x22,0x08,0x0B,0xF8,
0x10,0x00,0x27,0xFC,0xE4,0xA4,0x24,0xA4,0x24,0xA4,0x24,0xA4,0x2F,0xFE,0x20,0x00
};
static const unsigned char PROGMEM str_2[]={		//度
0x01,0x00,0x00,0x84,0x3F,0xFE,0x22,0x20,0x22,0x20,0x3F,0xFC,0x22,0x20,0x22,0x20,
0x23,0xE0,0x20,0x00,0x2F,0xF8,0x24,0x10,0x22,0x60,0x41,0x80,0x86,0x60,0x38,0x0E
};

static const unsigned char PROGMEM str_3[]={		//濕
0x00,0x04,0x47,0xFE,0x34,0x04,0x17,0xFC,0x84,0x04,0x67,0xFC,0x21,0x08,0x0A,0x12,
0x17,0xBC,0x21,0x08,0xE2,0x52,0x27,0xDE,0x20,0x00,0x25,0x24,0x24,0x92,0x28,0x92
};

// ------------------ DHT 感測器設定 ------------------
#define DHTPIN 8         // DHT 資料腳位 (避免使用 I2C 腳位)
#define DHTTYPE DHT11    // DHT11 或 DHT22
DHT dht(DHTPIN, DHTTYPE);

// ------------------ LED 腳位定義 ------------------
#define GREEN_LED 18
#define RED_LED   19

// ------------------ 上傳間隔 (毫秒) ------------------
unsigned long previousMillis = 0;
const unsigned long interval = 1000; // 每 10 秒

// 暫存從 Serial Monitor 輸入的指令 (pass-through)
String dataFromSerial;

void writeCB (BLECharacteristic* chr, uint8_t connID) {
    if (chr->getDataLen() > 0) {
        String cmd = chr->readString();
        Serial.print("Received string: ");
        Serial.println(cmd);
        lastCommand = cmd;
    }
}

void notifCB (BLECharacteristic* chr, uint8_t connID, uint16_t cccd) {
    if (cccd & GATT_CLIENT_CHAR_CONFIG_NOTIFY) {
        printf("Notifications enabled on Characteristic %s for connection %d \n", chr->getUUID().str(), connID);
        notify = true;
    } else {
        printf("Notifications disabled on Characteristic %s for connection %d \n", chr->getUUID().str(), connID);
        notify = false;
    }
}

void setup() {
 
  Serial.begin(115200);        // 設定硬體串列埠速率
  Serial3.begin(115200);       // 設定 Serial3 與 EK 板通訊
  initWiFi();
  delay(1000);
//--------model----------------------------------------------------------------
  config.setBitrate(2 * 1024 * 1024);
  Camera.configVideoChannel(amb82_CHANNEL, config);
  Camera.configVideoChannel(CHANNELNN, configNN);
  Camera.videoInit();
  rtsp.configVideo(config);
  rtsp.begin();
  rtsp_portnum = rtsp.getPort();
  ObjDet.configVideo(configNN);
  ObjDet.setResultCallback(ODPostProcess);
  ObjDet.modelSelect(OBJECT_DETECTION, CUSTOMIZED_YOLOV4TINY, NA_MODEL, NA_MODEL);
  ObjDet.begin();
  videoStreamer.registerInput(Camera.getStream(amb82_CHANNEL));
  videoStreamer.registerOutput(rtsp);
  if (videoStreamer.begin() != 0) {
      Serial.println("StreamIO link start failed");
  }
  Camera.channelBegin(amb82_CHANNEL);
  videoStreamerNN.registerInput(Camera.getStream(CHANNELNN));
  videoStreamerNN.setStackSize();
  videoStreamerNN.setTaskPriority();
  videoStreamerNN.registerOutput(ObjDet);
  if (videoStreamerNN.begin() != 0) {
      Serial.println("StreamIO link start failed");
  }
  Camera.channelBegin(CHANNELNN);
  OSD.configVideo(amb82_CHANNEL, config);
  OSD.begin();

  //使用自訂yolo模型於SD卡載入，須開啟內建Arduino IDE選擇模型來源為SD卡後燒錄。
  //--------------------------------------------------------------------------------------

  advdata.addFlags();
  advdata.addCompleteName("petcare");
  scndata.addCompleteServices(BLEUUID(UART_SERVICE_UUID));

  Rx.setWriteProperty(true);
  Rx.setWritePermissions(GATT_PERM_WRITE);
  Rx.setWriteCallback(writeCB);
  Rx.setBufferLen(STRING_BUF_SIZE);
  Tx.setReadProperty(true);
  Tx.setReadPermissions(GATT_PERM_READ);
  Tx.setNotifyProperty(true);
  Tx.setCCCDCallback(notifCB);
  Tx.setBufferLen(STRING_BUF_SIZE);

  UartService.addCharacteristic(Rx);
  UartService.addCharacteristic(Tx);

  BLE.init();
  BLE.configAdvert()->setAdvData(advdata);
  BLE.configAdvert()->setScanRspData(scndata);
  BLE.configServer(1);
  BLE.addService(UartService);
//--beacon----------
  BLE.configScan()->setScanMode(GAP_SCAN_MODE_ACTIVE);    // Active mode requests for scan response packets
  BLE.configScan()->setScanInterval(200);                 // Start a scan every 500ms
  BLE.configScan()->setScanWindow(200);                   // Each scan lasts for 250ms
  BLE.configScan()->updateScanParams();
  // Provide a callback function to process scan data.
  // If no function is provided, default BLEScan::printScanInfo is used
  BLE.setScanCallback(scanFunction);
  //BLE.beginCentral(0);
//----------------------------
  //BLE.beginPeripheral();

  Serial.println("sip reset");
  Serial3.write("sip reset");    // 初始化
  while (Serial3.available() <= 0) {}
  Serial.println(Serial3.readString());
  delay(1000);

  Serial.println("mac join abp");   // 設定 join mode
  Serial3.write("mac join abp");
  while (Serial3.available() <= 0) {}
  Serial.println(Serial3.readString());
  delay(1000);
  Serial.println("==============");

  // 初始化 DHT 感測器
  dht.begin();

  if(!display.begin(SSD1306_SWITCHCAPVCC,0x3c)) {      	//設定位址為 0x3c
    Serial.println(F("SSD1306 allocation falled"));   		 	//F(字串):將字串儲存在fash並非在RAM
    OLEDStatus = false;		   							//開啟OLED失敗
  } 

  // 初始化 LED 腳位
  pinMode(GREEN_LED, OUTPUT);
  pinMode(RED_LED, OUTPUT);
  digitalWrite(GREEN_LED, LOW);
  digitalWrite(RED_LED, LOW);

  Serial.println("=== Arduino Mega: DHT -> EK board, Downlink -> LED ===");
}
int i=0;
void loop() {

  //----beacon-------
  //BLE.configScan()->startScan(1000); // 每次掃描 1 秒
  // delay(500); // 避免過度呼叫，500ms 足夠
  //if(millis() - last > 30000){
  //  miss=1;
  //  Serial.println("WARNING!!!!!!!!!!");
  //}
  //else{
  //  miss=0;
  //}

  
  if (millis() - lastScan > 60000) {  // 每 3 秒啟動一次 scan
    BLE.beginCentral(0);
    Serial.println("central");
    BLE.configScan()->startScan(1000);  // scan 100ms
    lastScan = millis();
  }
  if(millis() - last > 300000){
    miss=1;
    Serial.println("WARNING!!!!!!!!!!");
  }
  else{
    miss=0;
  }
  // delay(5000);
  
  BLE.beginPeripheral();
  //----------------
  // ----------------------------------------------------------------------
  // A) 透過 Serial Monitor 輸入指令，pass-through 給 EK 板
  // ----------------------------------------------------------------------
  if (Serial.available()) {
    dataFromSerial = Serial.readString();  // 讀取使用者輸入的字串
    dataFromSerial.trim();
    if (dataFromSerial.length() > 0) {
      Serial3.println(dataFromSerial);
      while (Serial3.available() <= 0) {}
      String resp = Serial3.readString();
      Serial.println(resp);
    }
  }

  // ----------------------------------------------------------------------
  // B) 定期 (每 10 秒) 讀取 DHT 感測器，並上傳 (uplink)
  // ----------------------------------------------------------------------
  float h = dht.readHumidity();
  float t = dht.readTemperature();
  unsigned long currentMillis = millis();
  if (currentMillis - previousMillis >= interval) {
    previousMillis = currentMillis;

    
    if (isnan(h) || isnan(t)) {
      Serial.println("Failed to read from DHT sensor!");
    } else {
      // 將溫度、濕度乘以 100 取得整數 (保留兩位小數)
      int16_t tempScaled = (int16_t)(t * 100);
      int16_t humScaled  = (int16_t)(h * 100);

      // 轉成 16 進位字串，前 4 碼溫度、後 4 碼濕度 (共 8 碼)
      //char payload[9];
      //sprintf(payload, "%04X%04X", (uint16_t)tempScaled, (uint16_t)humScaled);

      uint16_t objCount = ObjDet.getResultCount();
      uint16_t sit = sitting;
      uint16_t stand = standing;
      uint16_t lie = lying;
      uint16_t m = miss;

      // 建立 payload：溫度(4碼)+濕度(4碼)+坐(4碼)+站(4碼)+躺(4碼) = 共20碼
      char payload[25]; // 20 + 1 為 null terminator
      sprintf(payload, "%04X%04X%04X%04X%04X%04X",
              (uint16_t)tempScaled,
              (uint16_t)humScaled,
              sit,
              stand,
              lie,
              m);

      // uplink 指令 (範例: "mac tx uncnf 2 006400C8")
      //if(i<100){//測試100次的成功次數
      String cmd = "mac tx ucnf 2 ";
      cmd += payload;

      Serial.print("[Uplink]:  ");
      Serial.print(i);
      i=i+1;
      Serial.println();
      Serial.println(cmd);

      Serial.println((String("物件數：")+String(ObjDet.getResultCount())+String(", 坐著：")+String(sitting)+String(",站著：")+String(standing)+String(",躺著：")+String(lying)));
      //String statusMsg = String("物件數：") + String(ObjDet.getResultCount()) +
      //                 String(", 坐著：") + String(sitting) +
      //                 String(", 站著：") + String(standing) +
      //                 String(", 躺著：") + String(lying);

      // 傳送到 EK 板，改用 c_str() 轉換為 C 字串
      Serial3.write(cmd.c_str());
      //}

      // 等待回應 (阻塞式)
      while(!Serial3.available()>0){}
      String resp = Serial3.readString();
      Serial.print("[Response] ");
      Serial.println(resp);



      //Serial3.write(statusMsg.c_str());
    }
  }
  // ----------------------------------------------------------------------
  // B) OLED顯示
  // ----------------------------------------------------------------------
   
  Serial.print(F("Humidity: "));
  Serial.print(h);
  Serial.print(F("%  Temperature: "));
  Serial.print(t);
  Serial.println(F("°C "));

  if(OLEDStatus==true) {
    display.clearDisplay();   		//清除緩衝區資料
    display.setTextColor(WHITE, BLACK); 	//設定白字黑底
    display.drawBitmap(0,	0,	str_1,	16,	16,	WHITE);		//溫,位置(  0,0)字型大小16*16顏色白色
    display.drawBitmap(18,	0,	str_2,	16,	16,	WHITE);		//度,位置(18,0)字型大小16*16顏色白色
    display.setTextSize(2);  	 	//設定字型大小為2
    display.setCursor(35,0);     			//設定起始點位置(38,0)
    display.print(": ");		
    display.println(t);
    //display.println("°C");

    display.drawBitmap(0,	30,	str_3,	16,	16,	WHITE);		//溫,位置(  0,0)字型大小16*16顏色白色
    display.drawBitmap(18,	30,	str_2,	16,	16,	WHITE);		//度,位置(18,0)字型大小16*16顏色白色
    display.setTextSize(2);  	 	//設定字型大小為2
    display.setCursor(35, 30);     			//設定起始點位置(38,0)
    display.print(": ");		
    display.println(h); 
    //display.println("%");   
    display.display();   	

  }

  // ----------------------------------------------------------------------
  // C) BLE
  // ----------------------------------------------------------------------
  if (lastCommand == "查詢溫濕度") {
    lastCommand = "";  // 重設命令避免重複傳送

    if (isnan(h) || isnan(t)) {
        Serial.println("讀取 DHT 感測器失敗！");
        return;
    }

    String msg = ("濕度: " + String(h) + "%\t" + "溫度: " + String(t) + "°C");

    Tx.writeString(msg);

    if (BLE.connected(0) && notify) {
        Tx.notify(0);  // 正確的呼叫方式，帶入 connID = 0
        Serial.println("通知已發送！");
    } else {
        Serial.println("尚未啟用 notify 或尚未連線！");
    }
  }
  if (lastCommand == "查詢姿態") {
    lastCommand = "";  // 重設命令避免重複傳送


    //String msg1 = ("濕度: " + String(h) + "%\t" + "溫度: " + String(t) + "°C");
    String msg1 = ("物件數："+String(ObjDet.getResultCount())+", 坐著："+String(sitting)+",站著："+String(standing)+",躺著："+String(lying));

    Tx.writeString(msg1);

    if (BLE.connected(0) && notify) {
        Tx.notify(0);  // 正確的呼叫方式，帶入 connID = 0
        Serial.println("通知已發送！");
    } else {
        Serial.println("尚未啟用 notify 或尚未連線！");
    }
  }
  if (lastCommand == "查詢狀態") {
    lastCommand = "";  // 重設命令避免重複傳送


    //String msg1 = ("濕度: " + String(h) + "%\t" + "溫度: " + String(t) + "°C");
    
    if(miss==0){
      Tx.writeString("還在哦");
    }
    else{
      Tx.writeString("不見了");
    }
    

    if (BLE.connected(0) && notify) {
        Tx.notify(0);  // 正確的呼叫方式，帶入 connID = 0
        Serial.println("通知已發送！");
    } else {
        Serial.println("尚未啟用 notify 或尚未連線！");
    }
  }
  // ----------------------------------------------------------------------
  // C) 非阻塞式檢查 Serial3 是否有其他資料
  // ----------------------------------------------------------------------
  if (Serial3.available()) {
    String r = Serial3.readString();
    Serial.print("[Serial3 async] ");
    Serial.println(r);
    // 控制 LED（根據下行資料中的 "mac_rx" 與 "30" 或 "31"）
    if (r.indexOf("mac rx") >= 0 && r.indexOf("30") >= 0) {
      //digitalWrite(GREEN_LED, HIGH);
      //digitalWrite(RED_LED, LOW);
      Serial.println("Downlink -> 30 => Green LED ON");
    }
    else if (r.indexOf("mac rx") >= 0 && r.indexOf("31") >= 0) {
      //digitalWrite(GREEN_LED, LOW);
      //digitalWrite(RED_LED, HIGH);
      Serial.println("Downlink -> 31 => Red LED ON");
    }
  }



  //delay(1000);
}
