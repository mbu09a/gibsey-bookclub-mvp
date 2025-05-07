FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Command will be specified in docker-compose
CMD ["python", "app.py", "worker", "-l", "info"]