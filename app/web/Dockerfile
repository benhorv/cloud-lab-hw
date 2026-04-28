FROM python:3.12-slim
RUN pip install flask pillow kafka-python
WORKDIR /app
COPY app.py .
COPY templates/ templates/
CMD ["python", "-u", "app.py"]
