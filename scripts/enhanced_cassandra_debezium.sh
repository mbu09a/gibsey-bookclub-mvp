#!/bin/bash
# Enhanced Cassandra Debezium setup based on full documentation

echo "=== SETTING UP ENHANCED CASSANDRA DEBEZIUM CONNECTOR ==="

# Create working directory
mkdir -p /tmp/enhanced-cassandra-debezium
cd /tmp/enhanced-cassandra-debezium

# First, verify CDC is enabled on Cassandra node
echo "Checking if CDC is enabled on Cassandra node..."
docker exec -it gibsey-cassandra grep -i "cdc_enabled" /etc/cassandra/cassandra.yaml || echo "CDC not found in config - needs to be enabled"

# Check CDC directory
echo "Checking CDC directory in Cassandra container..."
docker exec -it gibsey-cassandra ls -la /var/lib/cassandra/data/cdc_raw || echo "CDC directory not found - creating it"

# Create CDC directory if it doesn't exist
docker exec -it gibsey-cassandra bash -c 'mkdir -p /var/lib/cassandra/data/cdc_raw && chown -R cassandra:cassandra /var/lib/cassandra/data/cdc_raw'

# Update cassandra.yaml if needed to enable CDC
echo "Creating file to enable CDC in Cassandra..."
cat > cassandra_cdc_config.yaml << EOF
cdc_enabled: true
cdc_raw_directory: /var/lib/cassandra/data/cdc_raw
cdc_free_space_in_mb: 4096
cdc_free_space_check_interval_ms: 250
EOF
echo "To enable CDC in Cassandra, copy these settings to cassandra.yaml and restart Cassandra:"
cat cassandra_cdc_config.yaml

# Ensure the keyspace exists
echo "Ensuring gibsey keyspace exists..."
docker exec -it gibsey-cassandra cqlsh -e "CREATE KEYSPACE IF NOT EXISTS gibsey WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};"

# Create test table with CDC enabled
echo "Creating a test table with CDC enabled..."
docker exec -it gibsey-cassandra cqlsh -e "CREATE TABLE IF NOT EXISTS gibsey.test_cdc (id text PRIMARY KEY, data text) WITH cdc=true;"

# Insert test data
echo "Inserting test data..."
docker exec -it gibsey-cassandra cqlsh -e "INSERT INTO gibsey.test_cdc (id, data) VALUES ('seed-1', 'CDC test data');"

# Use a specialized Docker Compose file for a fresh attempt
cat > docker-compose.yml << 'EOF'
version: '3'

services:
  enhanced-cassandra-debezium:
    image: debezium/connect:2.4
    container_name: enhanced-cassandra-debezium
    ports:
      - "8087:8083"
    environment:
      # Kafka Connect settings
      BOOTSTRAP_SERVERS: kafka:9092
      GROUP_ID: enhanced-cassandra-group
      CONFIG_STORAGE_TOPIC: enhanced_configs
      OFFSET_STORAGE_TOPIC: enhanced_offsets
      STATUS_STORAGE_TOPIC: enhanced_statuses
      
      # Connector settings
      CONNECT_KEY_CONVERTER: org.apache.kafka.connect.json.JsonConverter
      CONNECT_VALUE_CONVERTER: org.apache.kafka.connect.json.JsonConverter
      CONNECT_KEY_CONVERTER_SCHEMAS_ENABLE: "false"
      CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE: "false"
      
      # Debug logging
      CONNECT_LOG4J_ROOT_LOGLEVEL: INFO
      CONNECT_LOG4J_LOGGERS: "org.apache.kafka.connect.runtime.rest=WARN,org.reflections=ERROR,io.debezium=TRACE"
      
      # Plugin path
      CONNECT_PLUGIN_PATH: /kafka/connect
    volumes:
      # Mount the plugins directory to persist across restarts
      - ./plugins:/kafka/connect/debezium-connector-cassandra
      # Mount log directory to see logs
      - ./logs:/kafka/logs
    networks:
      - infra_default
    command: /docker-entrypoint.sh start

networks:
  infra_default:
    external: true
EOF

# Create plugins directory and copy JAR
mkdir -p plugins
cp "/Users/ghostradongus/Desktop/Gibsey Bookclub MVP/infra/debezium-plugins/debezium-connector-cassandra-4-2.4.2.Final.jar" ./plugins/

# Create logs directory
mkdir -p logs

# Start the enhanced container
echo "Starting enhanced Debezium container..."
docker-compose up -d

# Wait for Connect to be available
echo "Waiting for Kafka Connect to become available..."
for i in {1..30}; do
  if curl -s http://localhost:8087/ > /dev/null; then
    echo "Kafka Connect is available"
    break
  fi
  echo "Waiting... ($i/30)"
  sleep 5
done

# Create connector config according to docs
cat > connector-config.json << 'EOF'
{
  "name": "enhanced-cassandra-connector",
  "config": {
    "connector.class": "io.debezium.connector.cassandra.CassandraConnector",
    "cassandra.hosts": "cassandra",
    "cassandra.port": "9042",
    "cassandra.username": "cassandra",
    "cassandra.password": "cassandra",
    "cassandra.keyspace": "gibsey",
    "topic.prefix": "gibsey",
    "cassandra.snapshot.mode": "always",
    "commit.log.real.time.processing.enabled": "false",
    "decimal.handling.mode": "string",
    "varint.handling.mode": "string",
    "tasks.max": "1",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
  }
}
EOF

# Create the connector
echo "Creating the enhanced Cassandra connector..."
curl -X POST -H "Content-Type: application/json" -d @connector-config.json http://localhost:8087/connectors

# Check connector status
echo "Checking connector status..."
sleep 5
curl -s http://localhost:8087/connectors/enhanced-cassandra-connector/status | jq

# Create a test script to verify operation
cat > verify-operation.sh << 'EOF'
#!/bin/bash

# Insert new data
echo "Inserting new data into test_cdc table..."
docker exec -it gibsey-cassandra cqlsh -e "INSERT INTO gibsey.test_cdc (id, data) VALUES ('test-$(date +%s)', 'New CDC data $(date)');"

# Wait a moment for processing
sleep 5

# Check Kafka topics
echo "Checking Kafka topics..."
docker exec gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list | grep gibsey

# Look for our data in the topic
echo "Checking for events in the topic..."
docker exec gibsey-kafka kafka-console-consumer --bootstrap-server kafka:9092 --topic gibsey.gibsey.test_cdc --from-beginning --max-messages 10
EOF
chmod +x verify-operation.sh

echo
echo "=== DOCUMENTATION INSIGHTS ==="
echo "1. The Cassandra connector is NOT built on Kafka Connect framework (despite using it)"
echo "2. It is intended to be deployed ON EACH Cassandra node"
echo "3. It operates directly on commit logs in cdc_raw directory"
echo "4. Commit logs only arrive in cdc_raw when they are full"
echo "5. Kafka topic naming: topic.prefix.keyspace.table (e.g. gibsey.gibsey.test_cdc)"
echo
echo "=== INSTRUCTIONS ==="
echo "Your enhanced setup is running at http://localhost:8087"
echo
echo "1. Check logs:"
echo "docker logs -f enhanced-cassandra-debezium"
echo
echo "2. Check connector status:"
echo "curl -s http://localhost:8087/connectors/enhanced-cassandra-connector/status | jq"
echo
echo "3. Test operation with:"
echo "./verify-operation.sh"
echo
echo "4. If CDC is not enabled in Cassandra, update cassandra.yaml with the settings in cassandra_cdc_config.yaml"
echo "   then restart Cassandra: docker restart gibsey-cassandra"