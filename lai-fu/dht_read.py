import time
import adafruit_dht
import board

dht = adafruit_dht.DHT22(board.D4)
for _ in range(3):
    try:
        t = dht.temperature
        h = dht.humidity
        if t is not None and h is not None:
            print(f"{t:.1f} {h:.1f}")
            break
    except RuntimeError:
        time.sleep(2)
dht.exit()
