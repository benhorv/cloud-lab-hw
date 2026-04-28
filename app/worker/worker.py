import os, json
from PIL import Image
import pytesseract
from kafka import KafkaConsumer

DATA_DIR = "/data"
KAFKA_BROKER = os.environ.get("KAFKA_BROKER", "kafka:9092")

def process(eid):
    entry_dir = os.path.join(DATA_DIR, eid)
    meta_path = os.path.join(entry_dir, "meta.json")
    with open(meta_path) as f:
        meta = json.load(f)

    img = Image.open(os.path.join(entry_dir, f"image{meta['ext']}"))
    data = pytesseract.image_to_data(img, output_type=pytesseract.Output.DICT)
    words = [
        {"text": w, "x": data["left"][i], "y": data["top"][i],
         "w": data["width"][i], "h": data["height"][i]}
        for i, w in enumerate(data["text"]) if w.strip()
    ]
    meta["words"] = words
    meta["text"] = " ".join(w["text"] for w in words)
    meta["status"] = "done"
    with open(meta_path, "w") as f:
        json.dump(meta, f)
    print(f"Processed {eid}: {len(words)} words", flush=True)

import time

while True:
    try:
        consumer = KafkaConsumer(
            "ocr-jobs",
            bootstrap_servers=KAFKA_BROKER,
            value_deserializer=lambda v: json.loads(v.decode()),
            auto_offset_reset="earliest",
            group_id="ocr-worker",
            api_version=(3, 0, 0)
        )
        break
    except Exception as e:
        print(f"Waiting for Kafka: {e}", flush=True)
        time.sleep(5)

print("OCR worker ready, waiting for jobs...", flush=True)
for msg in consumer:
    try:
        process(msg.value["id"])
    except Exception as e:
        print(f"Error processing {msg.value}: {e}", flush=True)
