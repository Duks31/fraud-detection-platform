FROM python:3.10-slim

WORKDIR /app

RUN pip install --no-cache-dir streamlit requests

COPY dashboard.py .

EXPOSE 8501

CMD ["streamlit", "run", "dashboard.py", "--server.port=8501", "--server.address=0.0.0.0"]