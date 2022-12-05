FROM python:3.8-slim 

WORKDIR /app

COPY api.py /app

RUN pip install --user flask

EXPOSE 5000

CMD ["python3", "/app/app.py"]