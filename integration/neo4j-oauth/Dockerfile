FROM python:3.12.12-slim
RUN pip install --no-cache-dir cryptography==50.0.2
COPY fixture.py /fixture.py
ENTRYPOINT ["python", "/fixture.py"]
