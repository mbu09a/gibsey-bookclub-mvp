#!/bin/bash
# Quick test to diagnose CDC setup without waiting the full 2 minutes

echo "=== QUICK TEST OF CDC PIPELINE ==="

# Check if services are running
echo "Checking if services are running..."
docker ps -a | grep -E 'gibsey-cassandra|gibsey-kafka|gibsey-debezium|gibsey-faust-worker'

# Check Debezium health directly
echo "Checking Debezium health..."
curl -s http://localhost:8083/ | grep -q "Kafka Connect" && echo "✅ Debezium is UP" || echo "❌ Debezium is DOWN"

# Check if the test table exists
echo "Checking if test_cdc table exists..."
docker exec gibsey-cassandra cqlsh -e "DESCRIBE KEYSPACES;" | grep -q gibsey && echo "✅ Keyspace gibsey exists" || echo "❌ Keyspace gibsey does not exist"

if docker exec gibsey-cassandra cqlsh -e "DESCRIBE KEYSPACES;" | grep -q gibsey; then
  echo "Creating test_cdc table if it doesn't exist..."
  docker exec gibsey-cassandra cqlsh -e "CREATE TABLE IF NOT EXISTS gibsey.test_cdc (id text PRIMARY KEY, data text) WITH cdc = true;"
  echo "Inserting test data..."
  docker exec gibsey-cassandra cqlsh -e "INSERT INTO gibsey.test_cdc (id, data) VALUES ('quick-test-$(date +%s)', 'Test data $(date)');"
fi

# Try to register a test connector
echo "Setting up a test connector for test_cdc table..."
cat > /tmp/test-connector.json << 'EOF'
{
  "name": "test-connector",
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

# Wait just a bit
sleep 5

# Check connector status
echo "Checking connector status..."
curl -s http://localhost:8083/connectors/test-connector/status | grep -i state

# Check Kafka topics
echo "Checking Kafka topics..."
docker exec gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list | grep gibsey

# Insert some more test data
echo "Inserting more test data..."
docker exec gibsey-cassandra cqlsh -e "INSERT INTO gibsey.test_cdc (id, data) VALUES ('quick-test-2-$(date +%s)', 'More test data $(date)');"

# Check Debezium logs
echo "Recent Debezium logs:"
docker logs --tail 20 gibsey-debezium | grep -E "ERROR|CassandraConnector|initialize|registered"

echo
echo "=== QUICK TEST COMPLETE ==="
echo "Look at the output above to diagnose issues."
echo "If you don't see your test topics, check the Debezium logs for errors:"
echo "docker logs gibsey-debezium"