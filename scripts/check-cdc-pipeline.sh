#!/bin/bash
# Check if the CDC pipeline is working correctly

echo "=== CHECKING CDC PIPELINE STATUS ==="

# Step 1: Check all containers
echo "Step 1: Checking if all containers are running..."
docker ps | grep -E 'gibsey-cassandra|gibsey-kafka|gibsey-debezium|gibsey-faust-worker'

# Step 2: Check Debezium API
echo -e "\nStep 2: Checking Debezium API..."
if curl -s http://localhost:8083/ | grep -q "version"; then
  echo "✅ Debezium API is responding"
else
  echo "❌ Debezium API is not responding"
  echo "Check container logs: docker logs gibsey-debezium"
  exit 1
fi

# Step 3: Check registered connectors
echo -e "\nStep 3: Checking registered connectors..."
CONNECTORS=$(curl -s http://localhost:8083/connectors)
echo "Registered connectors: $CONNECTORS"

# Step 4: Check for Cassandra test tables
echo -e "\nStep 4: Checking Cassandra tables..."
if docker exec gibsey-cassandra cqlsh -e "DESCRIBE KEYSPACE gibsey;" 2>/dev/null | grep -q "test_cdc"; then
  echo "✅ Test tables exist in Cassandra"
else
  echo "❌ Test tables don't exist"
  echo "Creating test tables..."
  docker exec gibsey-cassandra cqlsh -e "CREATE KEYSPACE IF NOT EXISTS gibsey WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};"
  docker exec gibsey-cassandra cqlsh -e "CREATE TABLE IF NOT EXISTS gibsey.test_cdc (id text PRIMARY KEY, data text) WITH cdc = true;"
  docker exec gibsey-cassandra cqlsh -e "CREATE TABLE IF NOT EXISTS gibsey.pages (id text PRIMARY KEY, title text, content text, section text) WITH cdc = true;"
fi

# Step 5: Insert test data
echo -e "\nStep 5: Inserting test data..."
TEST_ID=$(date +%s)
docker exec gibsey-cassandra cqlsh -e "INSERT INTO gibsey.test_cdc (id, data) VALUES ('check-$TEST_ID', 'CDC test at $(date)');"
docker exec gibsey-cassandra cqlsh -e "SELECT * FROM gibsey.test_cdc WHERE id='check-$TEST_ID';"

# Step 6: Check Kafka topics
echo -e "\nStep 6: Checking Kafka topics..."
TOPICS=$(docker exec gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list | grep gibsey)
echo "Topics with 'gibsey' prefix:"
echo "$TOPICS"

# Step 7: Check Faust worker logs
echo -e "\nStep 7: Checking Faust worker logs..."
docker logs --tail 20 gibsey-faust-worker | grep -E "Received event|Operation|Table|Stargate"

echo
echo "=== CDC PIPELINE REPORT ==="
if [[ -z "$CONNECTORS" || "$CONNECTORS" == "[]" ]]; then
  echo "❌ No connectors are registered with Debezium."
  echo "Run the connector creation script:"
  echo "    ./scripts/create-connector.sh"
  echo
  echo "If that fails, you may need to fix the Debezium setup first:"
  echo "    ./scripts/fix-debezium.sh"
else
  echo "Connector(s) registered: $CONNECTORS"
  
  if [[ "$TOPICS" == *"test_cdc"* || "$TOPICS" == *"pages"* ]]; then
    echo "✅ CDC topics found in Kafka. Pipeline is working!"
  else
    echo "❌ No CDC-specific topics found yet."
    echo "This might be because:"
    echo "1. The connector is still initializing (wait 5 minutes)"
    echo "2. The connector is misconfigured"
    echo "3. Debezium is having issues"
    echo
    echo "Check the connector status with:"
    echo "curl -s http://localhost:8083/connectors/postgres-connector/status"
  fi
fi

echo
echo "If you need to set up the CDC pipeline, follow these steps:"
echo "1. ./scripts/fix-debezium.sh    (Fixes the Debezium container setup)"
echo "2. ./scripts/create-connector.sh (Creates the temporary PostgreSQL connector)"
echo
echo "NOTE: This is a temporary setup with a PostgreSQL connector instead of"
echo "the Cassandra connector. In production, you would need to download"
echo "the correct Cassandra connector JAR file to the Debezium container."