import os, uuid, json, io
from flask import Flask, request, redirect, send_file, render_template
from PIL import Image, ImageDraw
from kafka import KafkaProducer

app = Flask(__name__)
DATA_DIR = "/data"
KAFKA_TOPIC = "ocr-jobs"

KAFKA_BROKER = os.environ.get("KAFKA_BROKER", "kafka:9092")
_producer = None

def get_producer():
    global _producer
    if _producer is None:
        _producer = KafkaProducer(
            bootstrap_servers=KAFKA_BROKER,
            value_serializer=lambda v: json.dumps(v).encode(),
            api_version=(3, 9, 0)
        )
    return _producer

def load_entries():
    if not os.path.exists(DATA_DIR):
        return []
    entries = []
    for eid in os.listdir(DATA_DIR):
        p = os.path.join(DATA_DIR, eid, "meta.json")
        if os.path.exists(p):
            with open(p) as f:
                m = json.load(f)
            m["id"] = eid
            entries.append(m)
    return entries

@app.route("/")
def index():
    return render_template("index.html", entries=load_entries())

@app.route("/upload", methods=["POST"])
def upload():
    img_file = request.files["image"]
    description = request.form["description"]
    eid = str(uuid.uuid4())
    entry_dir = os.path.join(DATA_DIR, eid)
    os.makedirs(entry_dir)
    ext = os.path.splitext(img_file.filename)[1] or ".png"
    img_path = os.path.join(entry_dir, f"image{ext}")
    img_file.save(img_path)

    with open(os.path.join(entry_dir, "meta.json"), "w") as f:
        json.dump({"description": description, "ext": ext,
                   "status": "pending", "text": "", "words": []}, f)

    get_producer().send(KAFKA_TOPIC, {"id": eid})
    get_producer().flush()
    return redirect("/")

@app.route("/image/<eid>")
def serve_image(eid):
    entry_dir = os.path.join(DATA_DIR, eid)
    with open(os.path.join(entry_dir, "meta.json")) as f:
        meta = json.load(f)
    img = Image.open(os.path.join(entry_dir, f"image{meta['ext']}")).convert("RGB")
    draw = ImageDraw.Draw(img)
    for w in meta.get("words", []):
        draw.rectangle([w["x"], w["y"], w["x"]+w["w"], w["y"]+w["h"]], outline="red", width=2)
    buf = io.BytesIO()
    img.save(buf, format="JPEG")
    buf.seek(0)
    return send_file(buf, mimetype="image/jpeg")

@app.route("/health")
def health():
    return "OK"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
