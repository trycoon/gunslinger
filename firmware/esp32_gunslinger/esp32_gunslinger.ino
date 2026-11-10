// ESP32 Arduino core BLE libraries; example for one trigger and a laser driver.
// Adapt these GPIO pins to your existing hardware. No magazine/reload logic here.
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

constexpr int TRIGGER_PIN = 18; // Button closes to ground, INPUT_PULLUP.
constexpr int LASER_PIN = 23;   // Control input of your existing laser driver.
constexpr unsigned long LASER_MS = 300;
constexpr char SERVICE_UUID[] = "02f8b7a0-14b9-4e9e-9f6c-7d6054301000";
constexpr char TRIGGER_UUID[] = "02f8b7a0-14b9-4e9e-9f6c-7d6054301001";
BLECharacteristic* triggerCharacteristic;
volatile bool connected = false;
volatile bool advertiseAgain = false;
uint32_t sequence = 0;
unsigned long laserStarted = 0;
bool laserOn = false;
bool lastRaw = HIGH;
bool stableButton = HIGH;
unsigned long changedAt = 0;

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*) override { connected = true; }
  void onDisconnect(BLEServer*) override {
    connected = false;
    advertiseAgain = true;
  }
};

void setup() {
  pinMode(TRIGGER_PIN, INPUT_PULLUP);
  pinMode(LASER_PIN, OUTPUT);
  digitalWrite(LASER_PIN, LOW);
  BLEDevice::init("Gunslinger-ESP32");
  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  BLEService* service = server->createService(SERVICE_UUID);
  triggerCharacteristic = service->createCharacteristic(TRIGGER_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  triggerCharacteristic->addDescriptor(new BLE2902());
  service->start();
  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  BLEDevice::startAdvertising();
}

void loop() {
  const unsigned long now = millis();
  if (advertiseAgain) {
    advertiseAgain = false;
    BLEDevice::startAdvertising();
  }
  const bool raw = digitalRead(TRIGGER_PIN);
  if (raw != lastRaw) { lastRaw = raw; changedAt = now; }
  if (now - changedAt >= 20 && raw != stableButton) {
    stableButton = raw;
    if (stableButton == LOW && !laserOn) {
      digitalWrite(LASER_PIN, HIGH); // Laser is on BEFORE the notification.
      laserOn = true;
      laserStarted = now;
      ++sequence;
      uint8_t packet[6] = {1, 1,
        static_cast<uint8_t>(sequence), static_cast<uint8_t>(sequence >> 8),
        static_cast<uint8_t>(sequence >> 16), static_cast<uint8_t>(sequence >> 24)};
      if (connected) {
        triggerCharacteristic->setValue(packet, sizeof(packet));
        triggerCharacteristic->notify();
      }
    }
  }
  if (laserOn && now - laserStarted >= LASER_MS) {
    digitalWrite(LASER_PIN, LOW);
    laserOn = false;
  }
  delay(1);
}
