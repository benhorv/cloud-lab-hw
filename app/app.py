from flask import Flask

app = Flask(__name__)

@app.route("/health")
def health():
    return "OK"

@app.route("/")
def index():
    return "Hello Cloud Lab OCR App!"

if __name__ == '__main__':
    app.run(host="0.0.0.0", port=5000)
