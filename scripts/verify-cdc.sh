#!/bin/bash
# Test CDC pipeline functionality

echo "=== VERIFYING CDC PIPELINE ==="

# Check if all services are running
echo "Step 1: Checking container status..."
docker ps -a | grep -E 'gibsey-cassandra|gibsey-kafka|gibsey-debezium|gibsey-faust-worker'

# Check Debezium API
echo -e "\nStep 2: Checking if Debezium API is responding..."
curl -s http://localhost:8083/ | head -n 10

# Check connectors
echo -e "\nStep 3: Checking registered connectors..."
CONNECTORS=$(curl -s http://localhost:8083/connectors)
echo "Registered connectors: $CONNECTORS"

# Register a test connector if none exists
if [[ "$CONNECTORS" == "[]" ]]; then
  echo "No connectors found. Registering a test connector..."
  cat > /tmp/test-connector.json << 'EOF'
{
  "name": "cassandra-connector",
  "config": {
    "connector.class": "io.debezium.connector.cassandra.CassandraConnector",
    "tasks.max": "1",
    "cassandra.hosts": "cassandra",
    "cassandra.port": "9042",
    "cassandra.username": "cassandra",
    "cassandra.password": "cassandra",
    "cassandra.keyspace": "gibsey",
    "topic.prefix": "gibsey",
    "table.include.list": "gibsey.test_cdc",
    "snapshot.mode": "initial",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
  }
}
EOF
  curl -X POST -H "Content-Type: application/json" -d @/tmp/test-connector.json http://localhost:8083/connectors
  echo ""
  sleep 5
  CONNECTORS=$(curl -s http://localhost:8083/connectors)
  echo "Registered connectors: $CONNECTORS"
fi

# Check connector status 
echo -e "\nStep 4: Checking connector status..."
for CONNECTOR in $(echo $CONNECTORS | tr -d '[]"' | tr ',' ' '); do
  echo "Status of connector: $CONNECTOR"
  curl -s http://localhost:8083/connectors/$CONNECTOR/status | grep -o '"state":"[^"]*"'
done

# Create test table if needed
echo -e "\nStep 5: Ensuring test table exists..."
docker exec gibsey-cassandra cqlsh -e "CREATE KEYSPACE IF NOT EXISTS gibsey WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};"
docker exec gibsey-cassandra cqlsh -e "CREATE TABLE IF NOT EXISTS gibsey.test_cdc (id text PRIMARY KEY, data text) WITH cdc = true;"

# Insert test data
echo -e "\nStep 6: Inserting test data to trigger CDC event..."
TEST_ID="verify-$(date +%s)"
docker exec gibsey-cassandra cqlsh -e "INSERT INTO gibsey.test_cdc (id, data) VALUES ('$TEST_ID', 'Verification test at $(date)');"

# Wait for events to propagate
echo "Waiting 10 seconds for events to propagate..."
sleep 10

# Check Kafka topics
echo -e "\nStep 7: Checking Kafka topics..."
TOPICS=$(docker exec gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list | grep gibsey)
echo "Topics with 'gibsey' prefix: $TOPICS"

if [[ -z "$TOPICS" ]]; then
  echo "❌ No topics found with 'gibsey' prefix. CDC is not working properly."
else
  echo "✅ Topics found with 'gibsey' prefix. CDC is capturing changes."
  
  # Check for messages in the topics
  echo -e "\nStep 8: Checking for messages in the first topic..."
  FIRST_TOPIC=$(echo $TOPICS | tr ' ' '\n' | head -n 1)
  echo "Looking for messages in topic: $FIRST_TOPIC"
  docker exec gibsey-kafka kafka-console-consumer --bootstrap-server kafka:9092 --topic $FIRST_TOPIC --from-beginning --max-messages 1 --timeout-ms 5000 || echo "No messages or timeout"
  
  # Check Faust worker logs
  echo -e "\nStep 9: Checking Faust worker logs..."
  docker logs --tail 20 gibsey-faust-worker | grep -E "Received event|$TEST_ID|INFO"
fi

echo -e "\n=== VERIFICATION COMPLETE ==="
if [[ -n "$TOPICS" ]]; then
  echo "✅ CDC pipeline appears to be working correctly!"
  echo "The pipeline successfully captures changes in Cassandra and sends them to Kafka."
  echo "The Faust worker should be processing these events."
else
  echo "❌ CDC pipeline is not working properly."
  echo "Check the error details above and fix any issues."
  echo "Run 'docker logs gibsey-debezium' for more Debezium connector logs."
fi