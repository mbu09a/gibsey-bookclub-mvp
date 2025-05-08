#!/bin/bash
# Advanced Cassandra Debezium setup based on documentation

echo "=== SETTING UP CASSANDRA DIRECT DEBEZIUM CONNECTOR ==="

# Create working directory
mkdir -p /tmp/cassandra-debezium
cd /tmp/cassandra-debezium

# First, verify CDC is enabled on Cassandra node
echo "Checking if CDC is enabled on Cassandra node..."
docker exec -it gibsey-cassandra nodetool describecluster | grep -i cdc

# Create CDC directory if it doesn't exist
echo "Creating CDC directory in Cassandra container..."
docker exec -it gibsey-cassandra bash -c 'mkdir -p /var/lib/cassandra/data/cdc_raw && chown -R cassandra:cassandra /var/lib/cassandra/data/cdc_raw'

# Enable CDC in Cassandra configuration
echo "Checking if CDC is enabled in configuration..."
docker exec -it gibsey-cassandra grep -i "cdc_enabled" /etc/cassandra/cassandra.yaml || echo "CDC not found in config"

# Setup a specialized standalone Debezium container
echo "Creating a specialized Debezium Cassandra container..."

# Download Debezium JAR and dependencies if needed
if [ ! -f "debezium-connector-cassandra.jar" ]; then
  echo "Copying connector JAR..."
  cp "/Users/ghostradongus/Desktop/Gibsey Bookclub MVP/infra/debezium-plugins/debezium-connector-cassandra-4-2.4.2.Final.jar" ./debezium-connector-cassandra.jar
fi

# Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3'

services:
  cassandra-debezium:
    image: debezium/connect:2.4
    container_name: cassandra-debezium
    ports:
      - "8086:8083"
    environment:
      # Kafka settings
      BOOTSTRAP_SERVERS: kafka:9092
      GROUP_ID: cassandra-debezium-group
      CONFIG_STORAGE_TOPIC: cass_connect_configs
      OFFSET_STORAGE_TOPIC: cass_connect_offsets
      STATUS_STORAGE_TOPIC: cass_connect_statuses
      
      # Connector settings
      CONNECT_KEY_CONVERTER: org.apache.kafka.connect.json.JsonConverter
      CONNECT_VALUE_CONVERTER: org.apache.kafka.connect.json.JsonConverter
      CONNECT_KEY_CONVERTER_SCHEMAS_ENABLE: "false"
      CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE: "false"
      
      # Enable specific log levels for debugging
      CONNECT_LOG4J_ROOT_LOGLEVEL: INFO
      CONNECT_LOG4J_LOGGERS: org.apache.kafka.connect.runtime.rest=WARN,org.reflections=ERROR,io.debezium=DEBUG
      
      # Plugin path (crucial)
      CONNECT_PLUGIN_PATH: /kafka/connect
    volumes:
      - ./debezium-connector-cassandra.jar:/kafka/connect/debezium-connector-cassandra/debezium-connector-cassandra.jar
    networks:
      - infra_default
    command: /docker-entrypoint.sh start

networks:
  infra_default:
    external: true
EOF

# Start the container
docker-compose up -d

# Wait for Kafka Connect to start
echo "Waiting for Kafka Connect to start..."
for i in {1..30}; do
  if curl -s http://localhost:8086/ > /dev/null; then
    echo "Kafka Connect is running"
    break
  fi
  echo "Waiting... ($i/30)"
  sleep 5
done

# Check available connector plugins
echo "Checking available connector plugins..."
curl -s http://localhost:8086/connector-plugins | jq

# Ensure gibsey keyspace and tables exist and have CDC enabled
echo "Checking if gibsey keyspace exists..."
docker exec -it gibsey-cassandra cqlsh -e "DESCRIBE KEYSPACES;" | grep gibsey

echo "Ensure tables have CDC enabled..."
docker exec -it gibsey-cassandra cqlsh -e "USE gibsey; DESCRIBE tables;" 

# Create connector configuration
cat > connector-config.json << 'EOF'
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
    "cassandra.snapshot.mode": "initial",
    "errors.log.enable": "true", 
    "errors.log.include.messages": "true"
  }
}
EOF

# Create the connector
echo "Creating Cassandra connector..."
curl -X POST -H "Content-Type: application/json" -d @connector-config.json http://localhost:8086/connectors

# Check connector status
echo "Checking connector status..."
sleep 5
curl -s http://localhost:8086/connectors/cassandra-connector/status | jq

# Instructions
echo
echo "=== INSTRUCTIONS ==="
echo "Your specialized Cassandra connector is running on port 8086"
echo
echo "To view logs:"
echo "docker logs -f cassandra-debezium"
echo
echo "To check connector status:"
echo "curl -s http://localhost:8086/connectors/cassandra-connector/status | jq"
echo
echo "To check Kafka topics:"
echo "docker exec gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list | grep gibsey"
echo
echo "NOTES FROM DOCUMENTATION:"
echo "1. Make sure CDC is enabled on Cassandra node level: cdc_enabled: true in cassandra.yaml"
echo "2. Make sure CDC is enabled on table level: CREATE TABLE foo (a int, b text, PRIMARY KEY(a)) WITH cdc=true;"
echo "3. The connector must be deployed on EACH node in the Cassandra cluster"
echo "4. Commit logs only arrive in cdc_raw directory when the log is full"
echo "5. The CDC connector processes LOCAL commit logs only"