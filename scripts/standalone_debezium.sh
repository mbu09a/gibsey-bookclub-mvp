#!/bin/bash
# Standalone Debezium Container - Run this to test the Cassandra connector in isolation

echo "=== CREATING STANDALONE DEBEZIUM CONTAINER ==="

# Create a directory for our standalone test
mkdir -p /tmp/standalone-debezium
cd /tmp/standalone-debezium

# Copy the connector JAR
echo "Copying connector JAR..."
mkdir -p debezium-connector-cassandra
cp "/Users/ghostradongus/Desktop/Gibsey Bookclub MVP/infra/debezium-plugins/debezium-connector-cassandra-4-2.4.2.Final.jar" debezium-connector-cassandra/

# Create a simple start script
echo "Creating start script..."
cat > start-connect.sh << 'EOF'
#!/bin/bash
set -e

echo "=== STARTING STANDALONE DEBEZIUM CONNECT ==="
echo "Environment variables:"
env | grep -E 'KAFKA|CONNECT|BOOTSTRAP'
echo "Plugin path directories:"
find /kafka/connect -type d | sort
echo "Cassandra connector files:"
ls -la /kafka/connect/debezium-connector-cassandra || echo "Directory not found!"

# Start in the foreground to keep the container running and see logs
exec connect-standalone.sh /kafka/config/connect-standalone.properties
EOF
chmod +x start-connect.sh

# Create a standalone properties file
echo "Creating standalone properties file..."
cat > connect-standalone.properties << 'EOF'
# Basic Kafka Connect configuration for standalone mode
bootstrap.servers=kafka:9092
key.converter=org.apache.kafka.connect.json.JsonConverter
value.converter=org.apache.kafka.connect.json.JsonConverter
key.converter.schemas.enable=false
value.converter.schemas.enable=false

# Directories where Connect looks for plugins
plugin.path=/kafka/connect

# REST API configuration
rest.port=8083
rest.advertised.host.name=0.0.0.0
rest.advertised.port=8083

# Various settings
offset.flush.interval.ms=10000
offset.storage.file.filename=/tmp/connect.offsets
EOF

# Create a connector config file
echo "Creating connector config file..."
cat > cassandra-connector.properties << 'EOF'
name=cassandra-connector
connector.class=io.debezium.connector.cassandra.CassandraConnector
tasks.max=1
cassandra.hosts=cassandra
cassandra.port=9042
cassandra.username=cassandra
cassandra.password=cassandra
cassandra.keyspace=gibsey
topic.prefix=gibsey
EOF

# Create a Dockerfile
echo "Creating Dockerfile..."
cat > Dockerfile << 'EOF'
FROM debezium/connect:2.4

USER root

# Add our connector
COPY debezium-connector-cassandra /kafka/connect/debezium-connector-cassandra

# Add our configuration files
COPY connect-standalone.properties /kafka/config/
COPY cassandra-connector.properties /kafka/config/
COPY start-connect.sh /kafka/

# Fix permissions
RUN chown -R kafka:kafka /kafka/connect /kafka/config /kafka/start-connect.sh && \
    chmod -R 755 /kafka/connect && \
    chmod +x /kafka/start-connect.sh

USER kafka
ENTRYPOINT ["/kafka/start-connect.sh"]
EOF

# Create a docker-compose file
echo "Creating docker-compose file..."
cat > docker-compose.yml << 'EOF'
version: '3'

services:
  standalone-debezium:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: standalone-debezium
    restart: always
    ports:
      - "8085:8083"  # Use different port to avoid conflicts
    environment:
      BOOTSTRAP_SERVERS: kafka:9092
    networks:
      - infra_default  # Should match your existing network
    volumes:
      - ./cassandra-connector.properties:/kafka/config/cassandra-connector.properties
      - ./connect-standalone.properties:/kafka/config/connect-standalone.properties
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8083/"]
      interval: 10s
      timeout: 5s
      retries: 3

networks:
  infra_default:
    external: true
EOF

echo
echo "=== STANDALONE DEBEZIUM SETUP CREATED ==="
echo "Files created in /tmp/standalone-debezium"
echo
echo "To run the standalone Debezium Connect container:"
echo "cd /tmp/standalone-debezium && docker-compose up -d"
echo
echo "To check logs:"
echo "docker logs -f standalone-debezium"
echo
echo "To check if the connector is running:"
echo "curl -s http://localhost:8085/connector-plugins | jq"
echo
echo "Note: This standalone container connects to your existing Kafka and Cassandra"
echo "containers through the 'infra_default' network."