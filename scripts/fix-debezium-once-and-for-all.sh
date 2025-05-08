#!/bin/bash
# Script to fix the Debezium Cassandra connector issue once and for all

echo "=== FIXING DEBEZIUM CASSANDRA CONNECTOR ISSUE ==="

# Step 1: Stop any running containers
echo "Stopping existing containers..."
docker compose -f infra/docker-compose.cdc.yml down

# Step 2: Update docker-compose.cdc.yml to use the existing files
echo "Updating docker-compose.cdc.yml to use the existing configuration files..."
cat > infra/docker-compose.cdc.yml << 'EOF'
version: '3'

services:
  # Cassandra database
  cassandra:
    image: cassandra:4.1
    container_name: gibsey-cassandra
    ports:
      - "9042:9042"
    environment:
      - CASSANDRA_CLUSTER_NAME=GibseyCluster
      - MAX_HEAP_SIZE=512M
      - HEAP_NEWSIZE=100M
    volumes:
      - cassandra_data:/var/lib/cassandra
    healthcheck:
      test: ["CMD", "cqlsh", "-u", "cassandra", "-p", "cassandra", "-e", "describe keyspaces"]
      interval: 15s
      timeout: 10s
      retries: 10

  # Stargate API for Cassandra
  stargate:
    image: stargateio/coordinator-4_0:v2
    container_name: gibsey-stargate
    depends_on:
      cassandra:
        condition: service_healthy
    ports:
      - "8080:8080"  # REST API
      - "8081:8081"  # GraphQL API
      - "8082:8082"  # Document API
      - "9043:9043"  # Auth port
    environment:
      - CLUSTER_NAME=GibseyCluster
      - CLUSTER_VERSION=4.0
      - CASSANDRA_CONTACT_POINTS=cassandra:9042
      - CASSANDRA_USERNAME=cassandra
      - CASSANDRA_PASSWORD=cassandra
      - DEVELOPER_MODE=true
      - ENABLE_AUTH=false
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8082/health"]
      interval: 15s
      timeout: 10s
      retries: 10

  # Zookeeper - needed for Kafka
  zookeeper:
    image: confluentinc/cp-zookeeper:7.4.0
    container_name: gibsey-zookeeper
    ports:
      - "2181:2181"
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "2181"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Kafka message broker
  kafka:
    image: confluentinc/cp-kafka:7.4.0
    container_name: gibsey-kafka
    depends_on:
      zookeeper:
        condition: service_healthy
    ports:
      - "9092:9092"
      - "29092:29092"
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092,PLAINTEXT_HOST://localhost:29092
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
      KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: true
    healthcheck:
      test: ["CMD", "kafka-topics", "--bootstrap-server", "localhost:9092", "--list"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Debezium for CDC (Change Data Capture) - Using existing files
  debezium:
    build:
      context: .
      dockerfile: infra/debezium.Dockerfile
    container_name: gibsey-debezium
    depends_on:
      kafka:
        condition: service_healthy
      cassandra:
        condition: service_healthy
    ports:
      - "8083:8083"
    environment:
      # Kafka Connect settings
      BOOTSTRAP_SERVERS: kafka:9092
      GROUP_ID: gibsey-debezium-group
      CONFIG_STORAGE_TOPIC: gibsey_connect_configs
      OFFSET_STORAGE_TOPIC: gibsey_connect_offsets
      STATUS_STORAGE_TOPIC: gibsey_connect_statuses
      # Connector settings
      CONNECT_KEY_CONVERTER: org.apache.kafka.connect.json.JsonConverter
      CONNECT_VALUE_CONVERTER: org.apache.kafka.connect.json.JsonConverter
      CONNECT_KEY_CONVERTER_SCHEMAS_ENABLE: "false"
      CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE: "false"
      # Plugin path setting - critical
      CONNECT_PLUGIN_PATH: /kafka/connect
      # Logging configuration for debugging
      CONNECT_LOG4J_ROOT_LOGLEVEL: INFO
      CONNECT_LOG4J_LOGGERS: "org.apache.kafka.connect.runtime.rest=WARN,org.reflections=ERROR,io.debezium=DEBUG"
      # For debugging
      CONNECT_DEBUG: "true"
    volumes:
      - debezium_logs:/kafka/logs
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8083/"]
      interval: 30s
      timeout: 10s
      retries: 10
      start_period: 60s

  # Faust Worker - processes Kafka messages
  faust-worker:
    build:
      context: .
      dockerfile: faust_worker/Dockerfile
    container_name: gibsey-faust-worker
    volumes:
      - ./faust_worker:/app
    depends_on:
      kafka:
        condition: service_healthy
    environment:
      KAFKA_BROKER: kafka:9092
      STARGATE_URL: http://stargate:8082
      STARGATE_AUTH_TOKEN: ${STARGATE_AUTH_TOKEN}
    command: python app.py worker -l info

volumes:
  cassandra_data:
  debezium_logs:
EOF

# Step 3: Create Cassandra connector configuration file
echo "Creating Cassandra connector config..."
mkdir -p infra/connectors
# Check if we already have the JAR file
echo "Checking for existing connector JAR file..."
if [ ! -f "/Users/ghostradongus/Desktop/Gibsey Bookclub MVP/infra/debezium-plugins/debezium-connector-cassandra-4-2.4.2.Final.jar" ]; then
  echo "Downloading Cassandra connector JAR file..."
  curl -Lo "/Users/ghostradongus/Desktop/Gibsey Bookclub MVP/infra/debezium-plugins/debezium-connector-cassandra-4-2.4.2.Final.jar" https://repo1.maven.org/maven2/io/debezium/debezium-connector-cassandra/2.4.2.Final/debezium-connector-cassandra-2.4.2.Final-plugin.jar
fi

# Create the service provider file that's needed
echo "Creating service provider file..."
mkdir -p /tmp/connector-files/META-INF/services
echo "io.debezium.connector.cassandra.CassandraConnector" > /tmp/connector-files/META-INF/services/org.apache.kafka.connect.source.SourceConnector

# Create a temp directory for repackaging
mkdir -p /tmp/repackage
cp "/Users/ghostradongus/Desktop/Gibsey Bookclub MVP/infra/debezium-plugins/debezium-connector-cassandra-4-2.4.2.Final.jar" /tmp/repackage/
(cd /tmp/repackage && jar -uf debezium-connector-cassandra-4-2.4.2.Final.jar -C /tmp/connector-files .)
cp /tmp/repackage/debezium-connector-cassandra-4-2.4.2.Final.jar "/Users/ghostradongus/Desktop/Gibsey Bookclub MVP/infra/debezium-plugins/debezium-connector-cassandra-4-2.4.2.Final.jar"

cat > infra/connectors/cassandra-connector.json << 'EOF'
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
    "table.include.list": "gibsey.pages",
    "snapshot.mode": "initial",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
  }
}
EOF

# Step 4: Rebuild and restart the stack
echo "Rebuilding and starting the stack..."
docker compose -f infra/docker-compose.cdc.yml up -d --build

# Step 5: Wait for everything to start
echo "Waiting for services to start (this may take a few minutes)..."
sleep 60

# Step 6: Initialize Cassandra with CDC-enabled table
echo "Initializing Cassandra with CDC-enabled table..."
docker exec -it gibsey-cassandra cqlsh -e "CREATE KEYSPACE IF NOT EXISTS gibsey WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};"
docker exec -it gibsey-cassandra cqlsh -e "CREATE TABLE IF NOT EXISTS gibsey.pages (id text PRIMARY KEY, title text, content text, section text) WITH cdc = true;"
docker exec -it gibsey-cassandra cqlsh -e "INSERT INTO gibsey.pages (id, title, content, section) VALUES ('test-page-1', 'Test Page', 'This is a test page for CDC', 'Testing');"

# Step 7: Check Debezium is up
echo "Checking if Debezium is up..."
curl -s http://localhost:8083/ | grep -q "Kafka Connect" && echo "✅ Debezium is UP" || echo "❌ Debezium is DOWN"

# Step 8: Register the connector
echo "Registering the Cassandra connector..."
curl -X POST -H "Content-Type: application/json" --data @infra/connectors/cassandra-connector.json http://localhost:8083/connectors

# Step 9: Check connector status
echo "Checking connector status..."
sleep 5
curl -s http://localhost:8083/connectors/cassandra-connector/status | jq

# Step 10: Insert another record to trigger CDC
echo "Inserting another record to trigger CDC..."
docker exec -it gibsey-cassandra cqlsh -e "INSERT INTO gibsey.pages (id, title, content, section) VALUES ('test-page-2', 'Test Page 2', 'This is another test page for CDC', 'Testing');"

# Step 11: Check Kafka topics
echo "Checking Kafka topics (looking for topic with 'gibsey' prefix)..."
docker exec -it gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list | grep gibsey

# Step 12: Final diagnostics
echo "Performing final diagnostics..."
echo "Contents of Debezium connector JAR:"
jar -tvf "/Users/ghostradongus/Desktop/Gibsey Bookclub MVP/infra/debezium-plugins/debezium-connector-cassandra-4-2.4.2.Final.jar" | grep -i service

echo
echo "=== DEBEZIUM FIX SCRIPT COMPLETE ==="
echo "If all steps completed successfully, your CDC pipeline should now be working."
echo 
echo "To check if everything is working:"
echo "1. Check Debezium logs: docker logs gibsey-debezium"
echo "2. Check Kafka topics: docker exec gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list | grep gibsey"
echo "3. Check connector status: curl -s http://localhost:8083/connectors/cassandra-connector/status | jq"
echo
echo "You may need to wait a few minutes for Debezium to fully initialize and connect to Cassandra."
echo
echo "If you still encounter issues, run the Faust worker in debug mode:"
echo "docker logs gibsey-faust-worker"