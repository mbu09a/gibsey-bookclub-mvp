#!/bin/bash
# Script to test the CDC pipeline end-to-end

echo "=== TESTING CDC PIPELINE ==="

# Step 1: Check if services are running
echo "Checking if services are running..."
docker ps -a | grep -E 'gibsey-cassandra|gibsey-kafka|gibsey-debezium|gibsey-faust-worker'

# Step 2: Check if Debezium connector is registered
echo "Checking Debezium connector status..."
CONNECTOR_STATUS=$(curl -s http://localhost:8083/connectors/cassandra-connector/status)
echo "$CONNECTOR_STATUS" | jq

# Check if connector is running
STATE=$(echo "$CONNECTOR_STATUS" | jq -r '.connector.state' 2>/dev/null)
if [[ "$STATE" == "RUNNING" ]]; then
  echo "✅ Connector is running"
else
  echo "❌ Connector is not running, state: $STATE"
  
  # If connector not running, try to register it
  echo "Trying to register the connector..."
  curl -X POST -H "Content-Type: application/json" -d @infra/connectors/cassandra-connector.json http://localhost:8083/connectors
  sleep 5
  curl -s http://localhost:8083/connectors/cassandra-connector/status | jq
fi

# Step 3: Insert data into Cassandra to trigger CDC
echo "Inserting test data into Cassandra..."
TEST_ID="test-$(date +%s)"
docker exec -it gibsey-cassandra cqlsh -e "INSERT INTO gibsey.pages (id, title, content, section) VALUES ('$TEST_ID', 'CDC Test', 'This is a test of the CDC pipeline at $(date)', 'Testing');"

# Step 4: Wait for events to flow through the pipeline
echo "Waiting for CDC events to flow through the pipeline (10 seconds)..."
sleep 10

# Step 5: Check Kafka topics
echo "Checking Kafka topics..."
docker exec gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list | grep gibsey

# Step 6: Check for messages in the Kafka topic
echo "Checking for messages in the Kafka topic..."
docker exec gibsey-kafka kafka-console-consumer --bootstrap-server kafka:9092 --topic gibsey.gibsey.pages --from-beginning --max-messages 1

# Step A7: Check Faust worker logs
echo "Checking Faust worker logs..."
docker logs gibsey-faust-worker | grep -E "$TEST_ID|Received event|Operation|TODO: Process page change" | tail -n 20

echo
echo "=== CDC PIPELINE TEST COMPLETE ==="
echo "If you saw:"
echo "1. A Kafka topic named gibsey.gibsey.pages"
echo "2. Messages in that topic containing your test data"
echo "3. Faust worker logs showing it received and processed the event"
echo "Then your CDC pipeline is working correctly!"
echo
echo "Next steps:"
echo "1. Add real embedding logic to the Faust worker"
echo "2. Create the Memory RAG service"
echo "3. Integrate with the front-end"