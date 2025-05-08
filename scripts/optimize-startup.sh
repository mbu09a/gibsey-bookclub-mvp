#!/bin/bash
# Optimize startup for CDC pipeline with better sequencing and reduced wait times

echo "=== OPTIMIZED CDC PIPELINE STARTUP ==="

# Stop any running containers first
echo "Stopping existing containers..."
docker compose -f infra/docker-compose.cdc.yml down

# Start Cassandra and Kafka first
echo "Starting core services (Cassandra and Kafka)..."
docker compose -f infra/docker-compose.cdc.yml up -d cassandra zookeeper kafka

# Wait for Cassandra to be ready
echo "Waiting for Cassandra to be ready..."
MAX_RETRIES=30
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if docker exec gibsey-cassandra cqlsh -e "SHOW VERSION" &>/dev/null; then
        echo "✅ Cassandra is ready!"
        break
    fi
    echo "Waiting for Cassandra... ($((RETRY_COUNT+1))/$MAX_RETRIES)"
    RETRY_COUNT=$((RETRY_COUNT+1))
    sleep 5
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌ Cassandra did not become ready in time. Please check the logs."
    exit 1
fi

# Initialize Cassandra schema
echo "Setting up Cassandra schema..."
docker exec gibsey-cassandra cqlsh -e "CREATE KEYSPACE IF NOT EXISTS gibsey WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};"
docker exec gibsey-cassandra cqlsh -e "CREATE TABLE IF NOT EXISTS gibsey.test_cdc (id text PRIMARY KEY, data text) WITH cdc = true;"
docker exec gibsey-cassandra cqlsh -e "CREATE TABLE IF NOT EXISTS gibsey.pages (id text PRIMARY KEY, title text, content text, section text) WITH cdc = true;"
docker exec gibsey-cassandra cqlsh -e "INSERT INTO gibsey.test_cdc (id, data) VALUES ('init-$(date +%s)', 'Initial data');"
docker exec gibsey-cassandra cqlsh -e "INSERT INTO gibsey.pages (id, title, content, section) VALUES ('init-page-$(date +%s)', 'Initial Page', 'This is an initial test page for the CDC pipeline', 'Testing');"

# Wait for Kafka to be ready
echo "Waiting for Kafka to be ready..."
MAX_RETRIES=30
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if docker exec gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list &>/dev/null; then
        echo "✅ Kafka is ready!"
        break
    fi
    echo "Waiting for Kafka... ($((RETRY_COUNT+1))/$MAX_RETRIES)"
    RETRY_COUNT=$((RETRY_COUNT+1))
    sleep 5
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌ Kafka did not become ready in time. Please check the logs."
    exit 1
fi

# Start Debezium and Faust now that core services are ready
echo "Starting Debezium and Faust..."
docker compose -f infra/docker-compose.cdc.yml up -d debezium faust-worker

# Wait for Debezium to be ready
echo "Waiting for Debezium to be ready..."
MAX_RETRIES=20
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -s http://localhost:8083/ | grep -q "Kafka Connect"; then
        echo "✅ Debezium is ready!"
        break
    fi
    echo "Waiting for Debezium... ($((RETRY_COUNT+1))/$MAX_RETRIES)"
    RETRY_COUNT=$((RETRY_COUNT+1))
    sleep 5
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌ Debezium did not become ready in time. Please check the logs:"
    docker logs gibsey-debezium
    exit 1
fi

# Register the connector
echo "Registering Cassandra connector..."
cat > /tmp/optimized-connector.json << 'EOF'
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

curl -X POST -H "Content-Type: application/json" -d @/tmp/optimized-connector.json http://localhost:8083/connectors

# Wait a moment for the connector to start
sleep 10

# Check connector status
echo "Checking connector status..."
CONNECTOR_STATUS=$(curl -s http://localhost:8083/connectors/cassandra-connector/status)
echo "$CONNECTOR_STATUS" | grep -i state

# Insert more test data to trigger CDC
echo "Inserting additional test data to trigger CDC events..."
docker exec gibsey-cassandra cqlsh -e "INSERT INTO gibsey.test_cdc (id, data) VALUES ('trigger-$(date +%s)', 'Trigger data for CDC');"

# Wait a moment for events to flow
sleep 5

# Check for topics
echo "Checking for Kafka topics..."
TOPICS=$(docker exec gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list | grep gibsey)
if [ -n "$TOPICS" ]; then
    echo "✅ Topics created: $TOPICS"
    echo "CDC pipeline is set up and working!"
else
    echo "❌ No topics found, checking Debezium logs for issues:"
    docker logs gibsey-debezium | grep -E "ERROR|exception|fail|CassandraConnector"
fi

echo
echo "=== OPTIMIZED STARTUP COMPLETE ==="
echo "Your CDC pipeline should now be ready to use."
echo "To verify operation, run:"
echo "./verify-operation.sh"