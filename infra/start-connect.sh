#!/bin/bash
set -e

echo "Copying custom properties file..."
cp /kafka/config/connect-distributed.properties.custom /kafka/config/connect-distributed.properties
cat /kafka/config/connect-distributed.properties

echo "Starting Kafka Connect in background..."
# Execute the original entrypoint script provided by the base image in the background
# This assumes /docker-entrypoint.sh is the correct script in debezium/connect:2.4
/docker-entrypoint.sh start &
CONNECT_PID=$!

echo "Kafka Connect started with PID: $CONNECT_PID"

echo "Waiting for Kafka Connect (localhost:8083) to become available..."

# Loop to check if the service is up
for i in {1..60}; do
  echo "Attempt $i: Checking Connect status..."
  # Use curl with fail-silent to check connectivity
  if curl -sf http://localhost:8083/ > /dev/null; then
    echo "Kafka Connect is up and running on port 8083!"
    # Optional: short wait after connect is up before tailing logs
    sleep 2 
    echo "Tailing Kafka Connect logs from /kafka/logs/connect.log (Press Ctrl+C to exit tail)..."
    # Use tail -f to follow logs, keeps the container running
    # If the log file doesn't exist initially, tail might wait.
    # Ensure logging is configured to write to this file.
    tail -f /kafka/logs/connect.log
    # Exit if tail exits (e.g., Ctrl+C)
    exit 0
  fi
  echo "Kafka Connect not yet available, waiting 5 seconds..."
  sleep 5
done

echo "ERROR: Kafka Connect did not become available on port 8083 after 300 seconds." >&2
exit 1 