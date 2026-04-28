FROM python:3.12-slim
RUN apt-get update && apt-get install -y tesseract-ocr && rm -rf /var/lib/apt/lists/*
RUN pip install flask pytesseract pillow
WORKDIR /app
COPY app.py .
COPY templates/ templates/
CMD ["python", "-u", "app.py"]
