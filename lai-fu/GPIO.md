# Lai-Fu GPIO 裝置紀錄

> 節點：Lai-Fu-Hermes（Raspberry Pi 2 Model B，armv7l）
> 更新此檔案時請同步更新下方接線表與裝置清單。

---

## 接線總覽

| 實體腳位 (Board) | BCM GPIO | 功能/訊號 | 連接裝置 | 備註 |
|:---:|:---:|:---:|:---:|:---|
| 1 | — | 3.3V 電源 | DHT22 VCC | |
| 7 | GPIO4 | DATA | DHT22 DATA | 需 10kΩ 上拉電阻 |
| 9 | — | GND | DHT22 GND | |

---

## 已安裝裝置

### DHT22 — 溫濕度感測器

| 項目 | 內容 |
|------|------|
| 型號 | DHT22（AM2302）|
| 接線 | VCC→Pin1 / DATA→Pin7(GPIO4) / GND→Pin9 |
| 通訊 | 單線數位協定 |
| 函式庫 | `adafruit-circuitpython-dht` 4.0.12 |
| Python venv | `/home/ken/dht22-env/` |
| 讀取腳本 | `/home/ken/.local/bin/dht_read.py` |
| 整合 | `sys-monitor.sh`：室溫 > 30°C 發送 Telegram 告警 |
| 安裝日期 | 2026-06-04 |

---

## 待接裝置

### Arduino（規劃中）

| 項目 | 內容 |
|------|------|
| 型號 | 待定（建議 Arduino Nano 3.3V 版） |
| 連接方式 | USB Serial（最穩；3.3V 版省電位轉換） |
| 預計接線 | USB → Lai-Fu USB port |
| 主要用途 | 類比感測器擴充（ADC）/ 即時繼電器控制 / 硬體 Watchdog |
| 狀態 | ⏳ 等待硬體到位 |

> 接上後請補充：實際型號、USB 裝置路徑（`/dev/ttyUSB0` 或 `/dev/ttyACM0`）、通訊鮑率、已燒錄韌體說明。

---

## 空閒腳位（可用）

以下腳位目前未使用，可供後續擴充：

| BCM GPIO | 實體腳位 | 支援功能 |
|:---:|:---:|:---|
| GPIO17 | 11 | 數位 I/O |
| GPIO27 | 13 | 數位 I/O |
| GPIO22 | 15 | 數位 I/O |
| GPIO10 | 19 | SPI MOSI |
| GPIO9  | 21 | SPI MISO |
| GPIO11 | 23 | SPI SCLK |
| GPIO2  | 3  | I²C SDA（ADS1115 等 I²C 模組）|
| GPIO3  | 5  | I²C SCL（ADS1115 等 I²C 模組）|

---

## 注意事項

- RPi 2 GPIO 為 **3.3V 邏輯**，接 5V 裝置前必須加電位轉換器
- Arduino Uno/Mega 為 5V，**直接接 RPi GPIO 會損壞**；改用 Arduino Nano 3.3V 版或加 Level Shifter
- 若只需補 ADC（類比輸入），可用 **ADS1115 模組**（I²C，約 $2）取代整顆 Arduino
- 新增裝置後同步更新本檔「接線總覽」與「已安裝裝置」兩節
