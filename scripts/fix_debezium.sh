#!/bin/bash
# Script to fix and debug Debezium container issues

echo "=== FIXING DEBEZIUM ISSUES ==="

# Step 1: Check container status
echo "Checking container status..."
docker ps -a | grep gibsey-debezium

# Step 2: Ensure parent directory /kafka/connect exists in the container
echo "Making sure plugin path directory exists..."
docker exec -it gibsey-cassandra mkdir -p /tmp/debezium_check
docker exec -it gibsey-cassandra echo "Checking container status..." > /tmp/debezium_check/test.txt

# Step 3: Identify if we need a new approach - use "vanilla" approach with standard configs
echo "Creating a simpler Debezium setup..."

# Create a simplified connect-distributed.properties file
echo "Creating simplified connect properties file..."
cat > /tmp/connect-distributed.properties << EOF
# Basic Kafka Connect configuration
bootstrap.servers=kafka:9092
group.id=gibsey-debezium-group
key.converter=org.apache.kafka.connect.json.JsonConverter
value.converter=org.apache.kafka.connect.json.JsonConverter
key.converter.schemas.enable=false
value.converter.schemas.enable=false

# REST configuration
rest.port=8083
rest.advertised.host.name=0.0.0.0
rest.advertised.port=8083

# Storage configuration for the Kafka Connect offset manager
offset.storage.topic=gibsey_connect_offsets
offset.storage.replication.factor=1
offset.storage.partitions=25
offset.flush.interval.ms=10000

# Storage configuration for Kafka Connect's configuration
config.storage.topic=gibsey_connect_configs
config.storage.replication.factor=1

# Storage configuration for Kafka Connect's statuses
status.storage.topic=gibsey_connect_statuses
status.storage.replication.factor=1
status.storage.partitions=5

# Plugin path - critical setting
plugin.path=/kafka/connect
EOF

# Create a simpler setup script
echo "Creating simplified start script..."
cat > /tmp/start-connect.sh << 'EOF'
#!/bin/bash
set -e

echo "=== DEBEZIUM DEBUG INFO ==="
echo "Java version:"
java -version
echo "Environment variables:"
env | grep -E 'KAFKA|CONNECT|BOOTSTRAP'
echo "Plugin path directories:"
ls -la /kafka/connect
echo "Cassandra connector files:"
ls -la /kafka/connect/debezium-connector-cassandra || echo "Directory not found!"
echo "=== END DEBUG INFO ==="

echo "Copying custom properties file..."
cp /kafka/config/connect-distributed.properties.custom /kafka/config/connect-distributed.properties
echo "Properties file content:"
cat /kafka/config/connect-distributed.properties

echo "Starting Connect in the foreground..."
exec /docker-entrypoint.sh start
EOF

# Create a vanilla Dockerfile for testing
echo "Creating test Dockerfile..."
cat > /tmp/test-debezium.Dockerfile << 'EOF'
FROM debezium/connect:2.4

USER root

# Create connector directory
RUN mkdir -p /kafka/connect/debezium-connector-cassandra

# Copy connector JAR files
COPY ./infra/debezium-plugins/debezium-connector-cassandra-*.jar /kafka/connect/debezium-connector-cassandra/

# Copy configuration files
COPY /tmp/connect-distributed.properties /kafka/config/connect-distributed.properties.custom
COPY /tmp/start-connect.sh /kafka/start-connect.sh

# Fix permissions
RUN chown -R kafka:kafka /kafka/connect /kafka/config /kafka/start-connect.sh && \
    chmod -R 755 /kafka/connect && \
    chmod +x /kafka/start-connect.sh

USER kafka
ENTRYPOINT ["/kafka/start-connect.sh"]
EOF

# Create a test docker-compose file
echo "Creating test docker-compose file..."
cat > /tmp/test-docker-compose.yml << 'EOF'
version: '3'

services:
  debezium-test:
    build:
      context: .
      dockerfile: /tmp/test-debezium.Dockerfile
    container_name: debezium-test
    ports:
      - "8084:8083"  # Use different port to avoid conflicts
    environment:
      BOOTSTRAP_SERVERS: kafka:9092
      GROUP_ID: test-group
      CONFIG_STORAGE_TOPIC: test_connect_configs
      OFFSET_STORAGE_TOPIC: test_connect_offsets
      STATUS_STORAGE_TOPIC: test_connect_statuses
      CONNECT_PLUGIN_PATH: /kafka/connect
    networks:
      - infra_default  # Should match your existing network

networks:
  infra_default:
    external: true
EOF

# Show instructions
echo ""
echo "=== INSTRUCTIONS ==="
echo "To try a simpler Debezium setup, run:"
echo "docker-compose -f /tmp/test-docker-compose.yml up -d"
echo ""
echo "To debug the existing container manually:"
echo "docker start gibsey-debezium"
echo "docker logs -f gibsey-debezium"
echo ""
echo "To check if the Debezium Connect API is accessible:"
echo "curl -v http://localhost:8083/"
echo ""
echo "To see what connectors are available:"
echo "curl -s http://localhost:8083/connector-plugins | jq"
echo ""
echo "To fix permissions inside the container:"
echo "docker exec -it gibsey-debezium /bin/bash -c 'chown -R kafka:kafka /kafka/connect && chmod -R 755 /kafka/connect'"
echo ""
echo "To manually create the Cassandra connector:"
echo "curl -X POST http://localhost:8083/connectors -H 'Content-Type: application/json' -d '{\"name\":\"gibsey-cassandra-connector\",\"config\":{\"connector.class\":\"io.debezium.connector.cassandra.CassandraConnector\",\"tasks.max\":\"1\",\"cassandra.hosts\":\"cassandra\",\"cassandra.port\":\"9042\",\"cassandra.username\":\"cassandra\",\"cassandra.password\":\"cassandra\",\"cassandra.keyspace\":\"gibsey\",\"topic.prefix\":\"gibsey\"}}'"