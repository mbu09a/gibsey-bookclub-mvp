#!/bin/bash
# Script to verify the Cassandra connector JAR in the Debezium container

echo "=== VERIFYING DEBEZIUM CASSANDRA CONNECTOR JAR ==="

# Check if the container is running
echo "Checking if gibsey-debezium container is running..."
CONTAINER_STATUS=$(docker ps -f "name=gibsey-debezium" --format "{{.Status}}")

if [[ -z "$CONTAINER_STATUS" ]]; then
  echo "Container is not running. Starting it..."
  docker start gibsey-debezium
  sleep 5
fi

# Check if JAR file exists in the expected location
echo "Checking for JAR file in the container..."
docker exec gibsey-debezium ls -la /kafka/connect/debezium-connector-cassandra/

# Check the connect-distributed.properties file
echo "Checking connect-distributed.properties..."
docker exec gibsey-debezium cat /kafka/config/connect-distributed.properties

# Check the plugin.path setting
echo "Checking plugin.path setting..."
docker exec gibsey-debezium grep -i "plugin.path" /kafka/config/connect-distributed.properties

# Check available plugins
echo "Checking available plugins in Kafka Connect..."
curl -s http://localhost:8083/connector-plugins | jq

# Check the class in the JAR file
echo "Checking for CassandraConnector class in the JAR..."
docker exec gibsey-debezium bash -c 'if command -v unzip &> /dev/null; then unzip -l /kafka/connect/debezium-connector-cassandra/*.jar | grep CassandraConnector; else echo "unzip not installed"; fi'

# Check if connector class exists using jar command
echo "Checking using jar command..."
docker exec gibsey-debezium bash -c 'if command -v jar &> /dev/null; then jar tf /kafka/connect/debezium-connector-cassandra/*.jar | grep CassandraConnector; else echo "jar command not installed"; fi'

# Try to install debugging tools if not present
echo "Attempting to install debugging tools..."
docker exec gibsey-debezium bash -c 'if command -v apt-get &> /dev/null; then apt-get update && apt-get install -y unzip; elif command -v yum &> /dev/null; then yum install -y unzip; elif command -v dnf &> /dev/null; then dnf install -y unzip; else echo "Package manager not found"; fi'

# Check JAR with unzip after installing
echo "Checking JAR content after installing unzip..."
docker exec gibsey-debezium bash -c 'if command -v unzip &> /dev/null; then unzip -l /kafka/connect/debezium-connector-cassandra/*.jar | grep -i cassandra; else echo "unzip still not available"; fi'

# Check class loading by looking at logs
echo "Checking logs for class loading issues..."
docker logs gibsey-debezium | grep -i "cassandra"
docker logs gibsey-debezium | grep -i "exception"
docker logs gibsey-debezium | grep -i "error"

# Check file permissions
echo "Checking file permissions..."
docker exec gibsey-debezium ls -la /kafka/connect/
docker exec gibsey-debezium ls -la /kafka/connect/debezium-connector-cassandra/

# Create a corrected Debezium Dockerfile
echo "Creating a corrected Dockerfile..."
cat > /tmp/fixed-debezium.Dockerfile << 'EOF'
FROM debezium/connect:2.4

USER root

# Install debugging tools
RUN microdnf install -y unzip

# Create connector directory
RUN mkdir -p /kafka/connect/debezium-connector-cassandra

# Copy connector JAR - using a local file for testing
COPY ./infra/debezium-plugins/debezium-connector-cassandra-4-2.4.2.Final.jar /kafka/connect/debezium-connector-cassandra/

# Fix permissions
RUN chown -R kafka:kafka /kafka/connect/debezium-connector-cassandra && \
    chmod -R 755 /kafka/connect/debezium-connector-cassandra

# Create a valid connect-distributed.properties file with correct plugin path
RUN echo "# Basic Kafka Connect configuration" > /kafka/config/connect-distributed.properties && \
    echo "bootstrap.servers=kafka:9092" >> /kafka/config/connect-distributed.properties && \
    echo "group.id=gibsey-debezium-group" >> /kafka/config/connect-distributed.properties && \
    echo "plugin.path=/kafka/connect" >> /kafka/config/connect-distributed.properties && \
    echo "key.converter=org.apache.kafka.connect.json.JsonConverter" >> /kafka/config/connect-distributed.properties && \
    echo "value.converter=org.apache.kafka.connect.json.JsonConverter" >> /kafka/config/connect-distributed.properties && \
    echo "key.converter.schemas.enable=false" >> /kafka/config/connect-distributed.properties && \
    echo "value.converter.schemas.enable=false" >> /kafka/config/connect-distributed.properties && \
    echo "offset.storage.topic=gibsey_connect_offsets" >> /kafka/config/connect-distributed.properties && \
    echo "config.storage.topic=gibsey_connect_configs" >> /kafka/config/connect-distributed.properties && \
    echo "status.storage.topic=gibsey_connect_statuses" >> /kafka/config/connect-distributed.properties

# Add a simple debug script
RUN echo '#!/bin/bash' > /kafka/debug.sh && \
    echo 'echo "=== KAFKA CONNECT DEBUG INFO ==="' >> /kafka/debug.sh && \
    echo 'echo "Plugin path directory contents:"' >> /kafka/debug.sh && \
    echo 'find /kafka/connect -type f -name "*.jar" | sort' >> /kafka/debug.sh && \
    echo 'echo "Connect properties:"' >> /kafka/debug.sh && \
    echo 'cat /kafka/config/connect-distributed.properties' >> /kafka/debug.sh && \
    echo 'echo "Available classes in Cassandra connector:"' >> /kafka/debug.sh && \
    echo 'unzip -l /kafka/connect/debezium-connector-cassandra/*.jar | grep -i "cassandra"' >> /kafka/debug.sh && \
    chmod +x /kafka/debug.sh

USER kafka

CMD ["/docker-entrypoint.sh", "start"]
EOF

echo "=== POTENTIAL ISSUES ==="
echo "1. The JAR file may not be copied correctly due to Docker build context issues"
echo "2. The plugin.path setting might be incorrect in connect-distributed.properties"
echo "3. The JAR file may have permission issues preventing it from being loaded"
echo "4. The JAR file might not contain the expected class io.debezium.connector.cassandra.CassandraConnector"
echo "5. The container might exit before Kafka Connect fully initializes"
echo "6. There might be missing dependencies or classpath issues"
echo
echo "=== RECOMMENDATIONS ==="
echo "1. Update your docker-compose.cdc.yml to use this new fixed Dockerfile:"
echo "   /tmp/fixed-debezium.Dockerfile"
echo "2. Rebuild and restart containers:"
echo "   docker-compose -f infra/docker-compose.cdc.yml down"
echo "   docker-compose -f infra/docker-compose.cdc.yml up -d --build"
echo "3. Run the debug script in the container:"
echo "   docker exec gibsey-debezium /kafka/debug.sh"
echo
echo "4. Ensure the required service providers file exists:"
echo "   docker exec gibsey-debezium find /kafka/connect -name \"*.jar\" -exec jar tf {} \\; | grep -i ServiceProvider"
echo
echo "5. Try the enhanced_cassandra_debezium.sh script created earlier as a completely separate approach"