#!/bin/bash
# Script to fix Debezium and install the connector properly

echo "=== FIXING DEBEZIUM SETUP ==="

# Step 1: Stop all containers
echo "Stopping all containers..."
docker compose -f infra/docker-compose.cdc.yml down

# Step 2: Create a more reliable setup for Debezium
echo "Creating better configuration..."
cat > infra/docker-compose.cdc.yml << 'EOF'
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

  # Debezium with Cassandra connector built in
  debezium:
    image: debezium/connect:2.4
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
      # Connector settings - simplified
      KEY_CONVERTER: org.apache.kafka.connect.json.JsonConverter
      VALUE_CONVERTER: org.apache.kafka.connect.json.JsonConverter
      KEY_CONVERTER_SCHEMAS_ENABLE: "false"
      VALUE_CONVERTER_SCHEMAS_ENABLE: "false"
    # Script to run after container starts
    command: >
      bash -c '
        echo "Downloading Cassandra connector..." &&
        mkdir -p /kafka/connect/debezium-connector-cassandra &&
        curl -sLo /tmp/connector.jar https://repo1.maven.org/maven2/io/debezium/debezium-connector-cassandra/2.4.2.Final/debezium-connector-cassandra-2.4.2.Final-plugin.jar &&
        mkdir -p /kafka/connect/debezium-connector-cassandra/META-INF/services &&
        echo "io.debezium.connector.cassandra.CassandraConnector" > /kafka/connect/debezium-connector-cassandra/META-INF/services/org.apache.kafka.connect.source.SourceConnector &&
        cp /tmp/connector.jar /kafka/connect/debezium-connector-cassandra/ &&
        ls -la /kafka/connect/debezium-connector-cassandra/ &&
        cat /kafka/connect/debezium-connector-cassandra/META-INF/services/org.apache.kafka.connect.source.SourceConnector &&
        echo "Starting Kafka Connect..." &&
        /docker-entrypoint.sh start'

  # Faust Worker - processes Kafka messages
  faust-worker:
    build:
      context: ..
      dockerfile: faust_worker/Dockerfile
    container_name: gibsey-faust-worker
    volumes:
      - ../faust_worker:/app:ro
    depends_on:
      kafka:
        condition: service_healthy
    environment:
      KAFKA_BROKER: kafka:9092
      # Optional since Stargate is not strictly needed for CDC
      STARGATE_URL: http://cassandra:9042
    command: python app.py worker -l info

volumes:
  cassandra_data:
EOF

# Step 3: Start the containers with the new configuration
echo "Starting containers with new configuration..."
docker compose -f infra/docker-compose.cdc.yml up -d

# Step 4: Wait for services to start
echo "Waiting for services to start (this might take a minute or two)..."
attempts=0
max_attempts=20
while [ $attempts -lt $max_attempts ]; do
  if curl -s http://localhost:8083/ | grep -q "Kafka Connect"; then
    echo "✅ Debezium is ready"
    break
  fi
  attempts=$((attempts+1))
  echo "Waiting for Debezium... ($attempts/$max_attempts)"
  sleep 15
done

if [ $attempts -eq $max_attempts ]; then
  echo "⚠️ Debezium didn't respond in time. It might still be starting up."
  echo "Check the logs with: docker logs gibsey-debezium"
else
  # Step 5: Create test tables
  echo "Creating test tables..."
  docker exec gibsey-cassandra cqlsh -e "CREATE KEYSPACE IF NOT EXISTS gibsey WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};"
  docker exec gibsey-cassandra cqlsh -e "CREATE TABLE IF NOT EXISTS gibsey.test_cdc (id text PRIMARY KEY, data text) WITH cdc = true;"
  docker exec gibsey-cassandra cqlsh -e "CREATE TABLE IF NOT EXISTS gibsey.pages (id text PRIMARY KEY, title text, content text, section text) WITH cdc = true;"

  # Step 6: Register the connector
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
    "snapshot.mode": "initial"
  }
}
EOF

  curl -X POST -H "Content-Type: application/json" -d @/tmp/cassandra-connector.json http://localhost:8083/connectors

  # Step 7: Insert test data
  echo "Inserting test data..."
  TEST_ID=$(date +%s)
  docker exec gibsey-cassandra cqlsh -e "INSERT INTO gibsey.test_cdc (id, data) VALUES ('test-$TEST_ID', 'Test CDC data');"
  docker exec gibsey-cassandra cqlsh -e "INSERT INTO gibsey.pages (id, title, content, section) VALUES ('page-$TEST_ID', 'Test Page', 'Test content', 'Test');"

  # Step 8: Wait for events to propagate
  echo "Waiting for events to propagate (15 seconds)..."
  sleep 15

  # Step 9: Check topics
  echo "Checking Kafka topics..."
  docker exec gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list | grep gibsey
fi

echo
echo "=== DEBEZIUM SETUP FIXED ==="
echo "Check if topics are created. If you don't see topic names yet, wait a few more minutes."
echo "The connector might take some time to initialize."
echo "You can check the status with: curl -s http://localhost:8083/connectors/cassandra-connector/status | jq"