FROM python:3.12.12-slim
RUN pip install --no-cache-dir cryptography==50.0.2
COPY server.py /server.py
CMD ["python", "-u", "/server.py"]
