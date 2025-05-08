#!/bin/bash
# Script to create a CDC connector (Cassandra if available, PostgreSQL as fallback)

echo "=== CREATING CDC CONNECTOR ==="

# Wait for Debezium to be ready
echo "Checking if Debezium is ready..."
max_attempts=10
attempt=0
while [ $attempt -lt $max_attempts ]; do
  if curl -s http://localhost:8083/ | grep -q "version"; then
    echo "✅ Debezium is ready"
    break
  fi
  attempt=$((attempt+1))
  echo "Waiting for Debezium... ($attempt/$max_attempts)"
  sleep 5
done

if [ $attempt -eq $max_attempts ]; then
  echo "❌ Debezium is not responding. Please check if it's running."
  echo "Run 'docker ps' to check container status."
  exit 1
fi

# Check if connector plugins are available
echo "Checking available connector plugins..."
PLUGINS=$(curl -s http://localhost:8083/connector-plugins)
echo "$PLUGINS" | grep "connector.class" || echo "No connector classes found"

# Check if Cassandra connector is available
if echo "$PLUGINS" | grep -q "CassandraConnector"; then
  echo "✅ Cassandra connector found! Using the proper Cassandra connector."
  
  # Create Cassandra connector configuration
  echo "Creating Cassandra connector configuration..."
  cat > /tmp/connector.json << 'EOF'
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
    "snapshot.mode": "initial"
  }
}
EOF

  # Register the connector
  echo "Registering Cassandra connector..."
  curl -X POST -H "Content-Type: application/json" -d @/tmp/connector.json http://localhost:8083/connectors
  echo ""
  CONNECTOR_NAME="cassandra-connector"
  
else
  echo "⚠️ Cassandra connector not found. Using PostgreSQL connector for demonstration."
  echo "To fix this, run: ./scripts/fix-debezium.sh"
  
  # Create PostgreSQL connector configuration for demo
  echo "Creating PostgreSQL connector configuration (demo only)..."
  cat > /tmp/connector.json << 'EOF'
{
  "name": "postgres-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "tasks.max": "1",
    "database.hostname": "cassandra",
    "database.port": "5432",
    "database.user": "postgres",
    "database.password": "postgres",
    "database.dbname": "postgres",
    "database.server.name": "gibsey",
    "topic.prefix": "gibsey",
    "schema.include.list": "public",
    "table.include.list": "public.test_cdc",
    "snapshot.mode": "initial"
  }
}
EOF

  # Register the connector
  echo "Registering PostgreSQL connector (demo)..."
  curl -X POST -H "Content-Type: application/json" -d @/tmp/connector.json http://localhost:8083/connectors
  echo ""
  CONNECTOR_NAME="postgres-connector"
fi

# Wait for connector to start
echo "Waiting for connector to initialize (10 seconds)..."
sleep 10

# Check connector status
echo "Checking connector status..."
curl -s http://localhost:8083/connectors/$CONNECTOR_NAME/status || echo "Failed to get connector status, but continuing anyway."
echo ""

# Create test tables if they don't exist (for both connectors)
echo "Creating test tables..."
docker exec gibsey-cassandra cqlsh -e "CREATE KEYSPACE IF NOT EXISTS gibsey WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};"
docker exec gibsey-cassandra cqlsh -e "CREATE TABLE IF NOT EXISTS gibsey.test_cdc (id text PRIMARY KEY, data text) WITH cdc = true;"
docker exec gibsey-cassandra cqlsh -e "CREATE TABLE IF NOT EXISTS gibsey.pages (id text PRIMARY KEY, title text, content text, section text) WITH cdc = true;"

# Insert test data
echo "Inserting test data..."
TEST_ID=$(date +%s)
docker exec gibsey-cassandra cqlsh -e "INSERT INTO gibsey.test_cdc (id, data) VALUES ('test-$TEST_ID', 'Test CDC data');"
docker exec gibsey-cassandra cqlsh -e "INSERT INTO gibsey.pages (id, title, content, section) VALUES ('page-$TEST_ID', 'Test Page', 'Test content', 'Test');"

# Wait for events to flow through
echo "Waiting for events to flow through (10 seconds)..."
sleep 10

# Check topics
echo "Checking for CDC topics in Kafka..."
docker exec gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list | grep gibsey || echo "No gibsey topics found yet, events might take more time to flow through."

echo 
echo "=== CONNECTOR CREATION COMPLETE ==="
if [[ "$CONNECTOR_NAME" == "postgres-connector" ]]; then
  echo "NOTE: Using PostgreSQL connector as a temporary solution."
  echo "Run ./scripts/fix-debezium.sh to install the proper Cassandra connector."
else
  echo "Using the proper Cassandra connector."
fi
echo "Check connector status with: curl -s http://localhost:8083/connectors/$CONNECTOR_NAME/status"