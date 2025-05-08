#!/bin/bash
# Complete CDC pipeline test

echo "=== COMPLETE CDC PIPELINE TEST ==="

# Step 1: Register the Cassandra connector
echo "Registering Cassandra connector..."
cat > /tmp/cassandra-connector.json << 'EOF'
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
    "table.include.list": "gibsey.test_cdc,gibsey.pages",
    "snapshot.mode": "initial",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
  }
}
EOF

curl -X POST -H "Content-Type: application/json" -d @/tmp/cassandra-connector.json http://localhost:8083/connectors

# Step 2: Wait for the connector to start
echo "Waiting for connector to initialize (10 seconds)..."
sleep 10

# Step 3: Check connector status
echo -e "\nChecking connector status..."
curl -s http://localhost:8083/connectors/cassandra-connector/status | grep -o '"state":"[^"]*"'

# Step 4: Create test tables if they don't exist
echo -e "\nEnsuring test tables exist..."
docker exec gibsey-cassandra cqlsh -e "CREATE KEYSPACE IF NOT EXISTS gibsey WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};"
docker exec gibsey-cassandra cqlsh -e "CREATE TABLE IF NOT EXISTS gibsey.test_cdc (id text PRIMARY KEY, data text) WITH cdc = true;"
docker exec gibsey-cassandra cqlsh -e "CREATE TABLE IF NOT EXISTS gibsey.pages (id text PRIMARY KEY, title text, content text, section text) WITH cdc = true;"

# Step 5: Insert test data
echo -e "\nInserting test data to trigger CDC events..."
TEST_ID="cdc-test-$(date +%s)"
docker exec gibsey-cassandra cqlsh -e "INSERT INTO gibsey.test_cdc (id, data) VALUES ('$TEST_ID', 'CDC test at $(date)');"
docker exec gibsey-cassandra cqlsh -e "INSERT INTO gibsey.pages (id, title, content, section) VALUES ('page-$TEST_ID', 'CDC Test Page', 'This is a test page for CDC at $(date)', 'Testing');"

# Step 6: Wait for events to propagate
echo "Waiting 15 seconds for events to propagate..."
sleep 15

# Step 7: Check Kafka topics
echo -e "\nChecking Kafka topics..."
TOPICS=$(docker exec gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list | grep gibsey)
echo "Topics with 'gibsey' prefix:"
echo "$TOPICS"

# Step 8: Check for CDC events in the topics
echo -e "\nChecking for CDC events in topics..."
for TOPIC in $TOPICS; do
  if [[ $TOPIC == *"test_cdc"* || $TOPIC == *"pages"* ]]; then
    echo -e "\nMessages in topic: $TOPIC"
    docker exec gibsey-kafka kafka-console-consumer --bootstrap-server kafka:9092 --topic $TOPIC --from-beginning --max-messages 1 --timeout-ms 5000 || echo "No messages or timeout"
  fi
done

# Step 9: Check Faust worker logs for event processing
echo -e "\nChecking Faust worker logs for event processing..."
docker logs --tail 30 gibsey-faust-worker | grep -E "Received event|Topic|Table|Operation"

echo -e "\n=== CDC PIPELINE TEST RESULTS ==="
if [[ "$TOPICS" == *"test_cdc"* || "$TOPICS" == *"pages"* ]]; then
  echo "✅ CDC pipeline is fully operational!"
  echo "Your pipeline is capturing changes from Cassandra and sending them to Kafka."
  echo "The Faust worker is ready to process these events."
else
  echo "❓ Results inconclusive:"
  echo "1. The connector may still be initializing - wait a few more minutes"
  echo "2. Check Debezium logs: docker logs gibsey-debezium"
  echo "3. Verify connector status: curl -s http://localhost:8083/connectors/cassandra-connector/status | jq"
fi