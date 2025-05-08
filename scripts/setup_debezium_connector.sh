#!/bin/bash
# Script to configure Debezium connector for Cassandra CDC
# Run this after the Cassandra, Kafka, and Debezium services are up

# First check the container logs to debug
echo "Checking Debezium container logs..."
docker logs gibsey-debezium

# Wait for Debezium Connect to be available
echo "Waiting for Debezium Connect to become available..."
attempts=0
max_attempts=60  # Increased to 60 attempts (5 minutes)
while [ $attempts -lt $max_attempts ]; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8083/ || echo "failed")
  
  if [ "$HTTP_CODE" = "200" ]; then
    echo "Debezium Connect is available!"
    break
  fi
  
  attempts=$((attempts+1))
  echo "Attempt $attempts/$max_attempts: Debezium Connect not yet available (HTTP code: $HTTP_CODE), waiting..."
  
  # Every 5 attempts, check the container status
  if [ $((attempts % 5)) -eq 0 ]; then
    echo "Container status:"
    docker ps -a | grep debezium
  fi
  
  sleep 5
done

if [ $attempts -eq $max_attempts ]; then
  echo "ERROR: Debezium Connect did not become available after $max_attempts attempts"
  echo "Checking final container state:"
  docker ps -a | grep debezium
  echo "Last 50 lines of logs:"
  docker logs gibsey-debezium --tail 50
  exit 1
fi

# Check available connectors
echo "Available connector plugins:"
curl -s http://localhost:8083/connector-plugins | jq

# Create the Cassandra connector with simpler config
echo "Creating Cassandra connector..."
RESPONSE=$(curl -X POST http://localhost:8083/connectors -H "Content-Type: application/json" -d '{
  "name": "gibsey-cassandra-connector",
  "config": {
    "connector.class": "io.debezium.connector.cassandra.CassandraConnector",
    "tasks.max": "1",
    "cassandra.hosts": "cassandra",
    "cassandra.port": "9042", 
    "cassandra.username": "cassandra",
    "cassandra.password": "cassandra",
    "cassandra.keyspace": "gibsey",
    "topic.prefix": "gibsey"
  }
}')

# Check response
echo "Connector creation response:"
echo "$RESPONSE"

# Check the connector status
echo "Checking connector status..."
sleep 2
curl -s http://localhost:8083/connectors/gibsey-cassandra-connector/status | jq

# List active connectors
echo "Active connectors:"
curl -s http://localhost:8083/connectors | jq

# Check Kafka topics to verify events are flowing
echo "Checking Kafka topics (should see gibsey.* topics):"
docker exec gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list