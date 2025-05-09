FROM python:3.11-slim

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first to leverage Docker cache
COPY requirements.txt .
RUN /usr/local/bin/python -m pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Run the simple consumer script instead of the Faust app
CMD ["python", "simple_consumer.py"]