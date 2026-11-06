FROM python:3.12.12-slim
RUN pip install --no-cache-dir cryptography==50.0.2
COPY prepare.py /prepare.py
COPY seed.py /seed.py
ENTRYPOINT ["python", "/prepare.py"]
