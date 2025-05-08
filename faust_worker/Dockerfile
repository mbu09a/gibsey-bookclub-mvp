FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends gcc build-essential && rm -rf /var/lib/apt/lists/*

# Define python path explicitly
ENV PYTHON_EXEC=/usr/local/bin/python
# Explicitly add site-packages to PYTHONPATH
ENV PYTHONPATH=/usr/local/lib/python3.11/site-packages

# Copy requirements and install dependencies using explicit python path
COPY faust_worker/requirements.txt .
RUN ${PYTHON_EXEC} -m pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY faust_worker/ .

# Use absolute path to python interpreter
CMD ["/usr/local/bin/python", "app.py", "worker", "-l", "info"]