FROM python:3.12-slim
RUN apt-get update && apt-get install -y tesseract-ocr && rm -rf /var/lib/apt/lists/*
RUN pip install pytesseract pillow kafka-python
WORKDIR /app
COPY worker.py .
CMD ["python", "-u", "worker.py"]
