#!/bin/bash
# Simple CDC setup script that doesn't require Java

echo "=== SIMPLE CDC SETUP ==="

# Make sure the infra directory exists
mkdir -p infra/connectors

# Step 1: Create a simple Debezium Dockerfile that gets the connector directly
echo "Creating simple Debezium Dockerfile..."
cat > infra/debezium.Dockerfile << 'EOF'
FROM debezium/connect:2.4

USER root
RUN mkdir -p /kafka/connect/debezium-connector-cassandra

# Download the connector directly - no need for Java locally
RUN curl -Lo /tmp/connector.jar https://repo1.maven.org/maven2/io/debezium/debezium-connector-cassandra/2.4.2.Final/debezium-connector-cassandra-2.4.2.Final-plugin.jar

# Move the JAR to the plugins directory
RUN mv /tmp/connector.jar /kafka/connect/debezium-connector-cassandra/debezium-connector-cassandra-2.4.2.Final.jar

# Create the service provider file that Kafka Connect needs
RUN mkdir -p /kafka/connect/debezium-connector-cassandra/META-INF/services/
RUN echo "io.debezium.connector.cassandra.CassandraConnector" > /kafka/connect/debezium-connector-cassandra/META-INF/services/org.apache.kafka.connect.source.SourceConnector

# Fix permissions
RUN chown -R kafka:kafka /kafka/connect && chmod -R 755 /kafka/connect

USER kafka

# This will be run by Docker Compose
CMD ["/docker-entrypoint.sh", "start"]
EOF

# Step 2: Create a simple connector configuration
echo "Creating connector configuration..."
mkdir -p infra/connectors
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
    "snapshot.mode": "initial"
  }
}
EOF

# Step 3: Start the CDC stack
echo "Starting CDC stack..."
cd "$(dirname "$0")/.." # Move to project root directory
docker compose -f infra/docker-compose.cdc.yml up -d --build

# Step 4: Wait for the services to start
echo "Waiting for services to start (2 minutes)..."
sleep 120

# Step 5: Create the Cassandra tables
echo "Creating Cassandra tables..."
docker exec -it gibsey-cassandra cqlsh -e "CREATE KEYSPACE IF NOT EXISTS gibsey WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};"
docker exec -it gibsey-cassandra cqlsh -e "CREATE TABLE IF NOT EXISTS gibsey.pages (id text PRIMARY KEY, title text, content text, section text) WITH cdc = true;"
docker exec -it gibsey-cassandra cqlsh -e "INSERT INTO gibsey.pages (id, title, content, section) VALUES ('test-1', 'Test Page', 'This is a test page for CDC', 'Testing');"

# Step 6: Register the connector
echo "Registering Cassandra connector..."
# Ensure we are in the project root
cd "$(dirname "$0")/.." # Move to project root directory if not already there
curl -X POST -H "Content-Type: application/json" -d @infra/connectors/cassandra-connector.json http://localhost:8083/connectors

# Step 7: Check status
echo "Checking connector status..."
sleep 10
curl -s http://localhost:8083/connectors/cassandra-connector/status | grep -i state

# Step 8: Insert another record to trigger CDC
echo "Inserting another record to trigger CDC..."
docker exec -it gibsey-cassandra cqlsh -e "INSERT INTO gibsey.pages (id, title, content, section) VALUES ('test-2', 'Second Test', 'Another test entry at $(date)', 'Testing');"

# Step 9: Check Kafka topics
echo "Checking Kafka topics..."
sleep 10
docker exec gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list | grep gibsey

echo
echo "=== CDC SETUP COMPLETE ==="
echo "To check if the CDC pipeline is working correctly:"
echo "1. Check Debezium logs: docker logs gibsey-debezium"
echo "2. Check Kafka topics: docker exec gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list | grep gibsey"
echo "3. Check connector status: curl -s http://localhost:8083/connectors/cassandra-connector/status"
echo "4. Check Faust worker logs: docker logs gibsey-faust-worker"