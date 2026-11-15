// ESP32 Arduino core BLE libraries; example for one trigger and a laser driver.
// Adapt these GPIO pins to your existing hardware. No magazine/reload logic here.
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <driver/rtc_io.h>
#include <esp_sleep.h>

// GPIO 33 is RTC-capable, so it can wake the ESP32 from deep sleep.
constexpr int TRIGGER_PIN = 33; // Button connects to 3.3 V, INPUT_PULLDOWN.
constexpr int LASER_PIN = 23;   // Control input of your existing laser driver.
constexpr unsigned long LASER_MS = 300; // How long the laser stays on after the trigger is pressed.
constexpr unsigned long DEBOUNCE_MS = 20; // Debounce time for the trigger button.
constexpr unsigned long IDLE_SLEEP_MS = 10UL * 60UL * 1000UL;
constexpr char SERVICE_UUID[] = "02f8b7a0-14b9-4e9e-9f6c-7d6054301000";
constexpr char TRIGGER_UUID[] = "02f8b7a0-14b9-4e9e-9f6c-7d6054301001";
BLECharacteristic* triggerCharacteristic;
volatile bool connected = false;
volatile bool advertiseAgain = false;
uint32_t sequence = 0;
unsigned long laserStarted = 0;
bool laserOn = false;
bool lastRaw = LOW;
bool stableButton = LOW;
unsigned long changedAt = 0;
unsigned long lastFiredAt = 0;
bool wakeShotPending = false;

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*) override {
    connected = true;
    Serial.println("[BLE] Client connected");
  }
  void onDisconnect(BLEServer*) override {
    connected = false;
    advertiseAgain = true;
    Serial.println("[BLE] Client disconnected");
  }
};

void setup() {
  Serial.begin(115200);
  const esp_sleep_wakeup_cause_t wakeupCause = esp_sleep_get_wakeup_cause();
  Serial.printf("\n[BOOT] Starting; wakeup cause: %d\n", static_cast<int>(wakeupCause));
  pinMode(TRIGGER_PIN, INPUT_PULLDOWN);
  lastRaw = digitalRead(TRIGGER_PIN);
  stableButton = lastRaw;
  changedAt = millis();
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
  Serial.println("[BLE] Advertising as Gunslinger-ESP32");
  lastFiredAt = millis();
  wakeShotPending = wakeupCause == ESP_SLEEP_WAKEUP_EXT0 && digitalRead(TRIGGER_PIN) == HIGH;
  if (wakeShotPending) {
    Serial.println("[TRIGGER] Wake shot pending BLE connection");
  }
}

void fire(unsigned long now) {
  digitalWrite(LASER_PIN, HIGH); // Laser is on BEFORE the notification.
  laserOn = true;
  laserStarted = now;
  lastFiredAt = now;
  ++sequence;
  uint8_t packet[6] = {1, 1,
    static_cast<uint8_t>(sequence), static_cast<uint8_t>(sequence >> 8),
    static_cast<uint8_t>(sequence >> 16), static_cast<uint8_t>(sequence >> 24)};
  if (connected) {
    triggerCharacteristic->setValue(packet, sizeof(packet));
    triggerCharacteristic->notify();
    Serial.printf("[SHOT] Sequence %lu; laser on, BLE notification requested\n",
                  static_cast<unsigned long>(sequence));
  } else {
    Serial.printf("[SHOT] Sequence %lu; laser on, no BLE client connected\n",
                  static_cast<unsigned long>(sequence));
  }
}

void sleepUntilTrigger() {
  digitalWrite(LASER_PIN, LOW);
  Serial.println("[SLEEP] Idle timeout; entering deep sleep until trigger");
  Serial.flush();
  rtc_gpio_pullup_dis(static_cast<gpio_num_t>(TRIGGER_PIN));
  rtc_gpio_pulldown_en(static_cast<gpio_num_t>(TRIGGER_PIN));
  esp_sleep_enable_ext0_wakeup(static_cast<gpio_num_t>(TRIGGER_PIN), HIGH);
  esp_deep_sleep_start();
}

void loop() {
  const unsigned long now = millis();
  if (advertiseAgain) {
    advertiseAgain = false;
    BLEDevice::startAdvertising();
    Serial.println("[BLE] Advertising restarted");
  }
  // The press that woke the ESP32 occurred before BLE could reconnect.
  if (wakeShotPending && connected && !laserOn) {
    wakeShotPending = false;
    Serial.println("[TRIGGER] Firing pending wake shot");
    fire(now);
  }
  const bool raw = digitalRead(TRIGGER_PIN);
  if (raw != lastRaw) { lastRaw = raw; changedAt = now; }
  if (now - changedAt >= DEBOUNCE_MS && raw != stableButton) {
    const bool triggerPulled = stableButton == LOW && raw == HIGH;
    stableButton = raw;
    if (triggerPulled && !laserOn) {
      fire(now);
    }
  }
  if (laserOn && now - laserStarted >= LASER_MS) {
    digitalWrite(LASER_PIN, LOW);
    laserOn = false;
    Serial.println("[LASER] Off");
  }
  if (!wakeShotPending && !laserOn && raw == LOW && now - lastFiredAt >= IDLE_SLEEP_MS) {
    sleepUntilTrigger();
  }
  delay(1);
}
