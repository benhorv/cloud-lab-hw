import os, uuid, json, io
from flask import Flask, request, redirect, send_file, render_template_string
from PIL import Image, ImageDraw
import pytesseract

app = Flask(__name__)
DATA_DIR = "/data"

TEMPLATE = """<!DOCTYPE html>
<html><head><title>OCR App</title></head><body>
<h1>OCR App</h1>
<form method="post" action="/upload" enctype="multipart/form-data">
  <input type="file" name="image" accept="image/*" required>
  <input type="text" name="description" placeholder="Description" required>
  <button type="submit">Upload</button>
</form>
<hr>
{% for e in entries %}
<div>
  <p><strong>{{ e.description }}</strong></p>
  <a href="/image/{{ e.id }}"><img src="/image/{{ e.id }}" height="200"></a>
  <p>Detected: {{ e.text }}</p>
</div><hr>
{% endfor %}
</body></html>"""

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
    return render_template_string(TEMPLATE, entries=load_entries())

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

    img = Image.open(img_path)
    data = pytesseract.image_to_data(img, output_type=pytesseract.Output.DICT)
    words = [
        {"text": w, "x": data["left"][i], "y": data["top"][i],
         "w": data["width"][i], "h": data["height"][i]}
        for i, w in enumerate(data["text"]) if w.strip()
    ]
    with open(os.path.join(entry_dir, "meta.json"), "w") as f:
        json.dump({"description": description, "words": words,
                   "text": " ".join(w["text"] for w in words), "ext": ext}, f)
    return redirect("/")

@app.route("/image/<eid>")
def serve_image(eid):
    entry_dir = os.path.join(DATA_DIR, eid)
    with open(os.path.join(entry_dir, "meta.json")) as f:
        meta = json.load(f)
    img = Image.open(os.path.join(entry_dir, f"image{meta['ext']}")).convert("RGB")
    draw = ImageDraw.Draw(img)
    for w in meta["words"]:
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
