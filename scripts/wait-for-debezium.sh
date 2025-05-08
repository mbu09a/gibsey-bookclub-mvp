#!/bin/bash
# Script to wait for Debezium to be fully ready

echo "=== WAITING FOR DEBEZIUM ==="

# Check if Debezium container is running
if ! docker ps | grep -q gibsey-debezium; then
  echo "❌ Debezium container is not running!"
  echo "Start it with: docker compose -f infra/docker-compose.cdc.yml up -d"
  exit 1
fi

# Wait for Debezium API to respond
MAX_ATTEMPTS=30
attempt=0
echo "Waiting for Debezium API to respond..."

while [ $attempt -lt $MAX_ATTEMPTS ]; do
  if curl -s http://localhost:8083/ | grep -q "Kafka Connect"; then
    echo "✅ Debezium API is responding!"
    break
  fi
  attempt=$((attempt+1))
  echo "Attempt $attempt/$MAX_ATTEMPTS - Waiting for Debezium..."
  
  # Print recent logs to help diagnose issues
  if [ $((attempt % 5)) -eq 0 ]; then
    echo "Recent Debezium logs:"
    docker logs --tail 10 gibsey-debezium
  fi
  
  sleep 10
done

if [ $attempt -eq $MAX_ATTEMPTS ]; then
  echo "❌ Debezium did not respond after $MAX_ATTEMPTS attempts."
  echo "Check the logs: docker logs gibsey-debezium"
  exit 1
fi

# Check if connector plugins are available
echo "Checking for connector plugins..."
PLUGINS=$(curl -s http://localhost:8083/connector-plugins)
echo "$PLUGINS"

if echo "$PLUGINS" | grep -q "CassandraConnector"; then
  echo "✅ Cassandra connector plugin is available!"
else
  echo "❌ Cassandra connector plugin not found!"
  echo "You'll need to install the connector. Check Debezium logs for details."
  exit 1
fi

# Check existing connectors
echo "Checking for existing connectors..."
CONNECTORS=$(curl -s http://localhost:8083/connectors)
echo "Registered connectors: $CONNECTORS"

echo
echo "=== DEBEZIUM IS READY ==="
echo "The Debezium Connect API is now responding."
echo "You can proceed to register a connector with: ./scripts/create-connector.sh"