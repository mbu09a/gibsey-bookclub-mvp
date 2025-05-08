#!/bin/bash
# Final script to resolve Debezium Cassandra connector issues
# Based on latest configuration and documentation insights

echo "=== FINAL DEBEZIUM CASSANDRA CONNECTOR FIX ==="

# Step 1: Check if the service provider file exists in the JAR
echo "Checking for service provider configuration in the JAR..."
mkdir -p /tmp/jar-check
cp "/Users/ghostradongus/Desktop/Gibsey Bookclub MVP/infra/debezium-plugins/debezium-connector-cassandra-4-2.4.2.Final.jar" /tmp/jar-check/
cd /tmp/jar-check

# Extract the JAR to check its contents
echo "Extracting JAR to check contents..."
mkdir -p extracted
cd extracted
jar xf ../debezium-connector-cassandra-4-2.4.2.Final.jar

# Check for the service provider file
echo "Checking for Kafka Connect service provider configuration..."
if [ -f "META-INF/services/org.apache.kafka.connect.source.SourceConnector" ]; then
    echo "SUCCESS: Service provider file found!"
    cat "META-INF/services/org.apache.kafka.connect.source.SourceConnector"
else
    echo "ERROR: Service provider file NOT found! This is likely the core issue."
    
    # Create the missing file
    echo "Creating missing service provider file..."
    mkdir -p META-INF/services
    echo "io.debezium.connector.cassandra.CassandraConnector" > META-INF/services/org.apache.kafka.connect.source.SourceConnector
    
    # Repackage the JAR with the new file
    echo "Repackaging JAR with service provider file..."
    jar cf ../fixed-connector.jar .
    
    # Copy the fixed JAR back to the project
    echo "Copying fixed JAR to the project..."
    cp ../fixed-connector.jar "/Users/ghostradongus/Desktop/Gibsey Bookclub MVP/infra/debezium-plugins/fixed-connector.jar"
    
    echo "Created fixed JAR at: /Users/ghostradongus/Desktop/Gibsey Bookclub MVP/infra/debezium-plugins/fixed-connector.jar"
fi

# Step 2: Create a completely standalone setup with the fixed JAR
echo "Creating a standalone setup with fixed configuration..."

mkdir -p /tmp/standalone-fix
cd /tmp/standalone-fix

# Create connect-distributed.properties
cat > connect-distributed.properties << 'EOF'
# Required settings for Kafka Connect
bootstrap.servers=kafka:9092
group.id=standalone-cassandra-group
key.converter=org.apache.kafka.connect.json.JsonConverter
value.converter=org.apache.kafka.connect.json.JsonConverter
key.converter.schemas.enable=false
value.converter.schemas.enable=false

# Storage settings
offset.storage.topic=standalone_offsets
offset.storage.replication.factor=1
config.storage.topic=standalone_configs
config.storage.replication.factor=1
status.storage.topic=standalone_status
status.storage.replication.factor=1

# REST API settings
rest.port=8089
rest.host.name=0.0.0.0
rest.advertised.host.name=localhost
rest.advertised.port=8089

# Worker settings
plugin.path=/kafka/connect
EOF

# Create a direct Connector configuration file
cat > cassandra-connector.properties << 'EOF'
# Cassandra Connector configuration
name=standalone-cassandra-connector
connector.class=io.debezium.connector.cassandra.CassandraConnector
tasks.max=1
cassandra.hosts=cassandra
cassandra.port=9042
cassandra.username=cassandra
cassandra.password=cassandra
cassandra.keyspace=gibsey
topic.prefix=gibsey
EOF

# Create a new Dockerfile for standalone approach
cat > Dockerfile << 'EOF'
FROM debezium/connect:2.4

USER root

# Install debug tools
RUN microdnf update -y && microdnf install -y unzip curl procps

# Create the plugin directory
RUN mkdir -p /kafka/connect/debezium-connector-cassandra

# Copy our fixed connector JAR
COPY fixed-connector.jar /kafka/connect/debezium-connector-cassandra/
COPY connect-distributed.properties /kafka/config/connect-distributed.properties
COPY cassandra-connector.properties /kafka/config/cassandra-connector.properties

# Create startup script
RUN echo '#!/bin/bash' > /kafka/run.sh && \
    echo 'echo "=== STARTING STANDALONE KAFKA CONNECT ===" && \' >> /kafka/run.sh && \
    echo 'echo "Java version:" && java -version && \' >> /kafka/run.sh && \
    echo 'echo "Connector JAR:" && ls -la /kafka/connect/debezium-connector-cassandra && \' >> /kafka/run.sh && \
    echo 'echo "Service provider file:" && jar tf /kafka/connect/debezium-connector-cassandra/fixed-connector.jar | grep -i service && \' >> /kafka/run.sh && \
    echo 'echo "Starting Connect in standalone mode..." && \' >> /kafka/run.sh && \
    echo 'exec connect-standalone.sh /kafka/config/connect-distributed.properties /kafka/config/cassandra-connector.properties' >> /kafka/run.sh && \
    chmod +x /kafka/run.sh

# Set permissions
RUN chown -R kafka:kafka /kafka && chmod -R 755 /kafka/connect

USER kafka
ENTRYPOINT ["/kafka/run.sh"]
EOF

# Copy the fixed JAR
if [ -f "/Users/ghostradongus/Desktop/Gibsey Bookclub MVP/infra/debezium-plugins/fixed-connector.jar" ]; then
    cp "/Users/ghostradongus/Desktop/Gibsey Bookclub MVP/infra/debezium-plugins/fixed-connector.jar" .
else
    cp "/Users/ghostradongus/Desktop/Gibsey Bookclub MVP/infra/debezium-plugins/debezium-connector-cassandra-4-2.4.2.Final.jar" fixed-connector.jar
fi

# Create docker-compose file
cat > docker-compose.yml << 'EOF'
version: '3'

services:
  standalone-connect:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: standalone-cassandra-connect
    ports:
      - "8089:8089"
    networks:
      - infra_default
    restart: always

networks:
  infra_default:
    external: true
EOF

# Step 3: Create an option to use a traditional Kafka Connect bridge
echo "Creating traditional Kafka Connect bridge option..."

# Create folder for traditional approach
mkdir -p /tmp/kafka-connect-bridge
cd /tmp/kafka-connect-bridge

# Create a simpler Dockerfile that uses vanilla Kafka Connect
cat > Dockerfile << 'EOF'
FROM confluentinc/cp-kafka-connect:7.4.0

USER root

# Create directories
RUN mkdir -p /usr/share/java/debezium-connector-cassandra

# Copy the connector JAR
COPY fixed-connector.jar /usr/share/java/debezium-connector-cassandra/

# Set permissions
RUN chown -R appuser:appuser /usr/share/java/debezium-connector-cassandra && \
    chmod -R 755 /usr/share/java/debezium-connector-cassandra

USER appuser
EOF

# Copy the fixed JAR
if [ -f "/Users/ghostradongus/Desktop/Gibsey Bookclub MVP/infra/debezium-plugins/fixed-connector.jar" ]; then
    cp "/Users/ghostradongus/Desktop/Gibsey Bookclub MVP/infra/debezium-plugins/fixed-connector.jar" .
else
    cp "/Users/ghostradongus/Desktop/Gibsey Bookclub MVP/infra/debezium-plugins/debezium-connector-cassandra-4-2.4.2.Final.jar" fixed-connector.jar
fi

# Create docker-compose file for Confluent Platform
cat > docker-compose.yml << 'EOF'
version: '3'

services:
  connect:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: kafka-connect-bridge
    ports:
      - "8088:8083"
    environment:
      CONNECT_BOOTSTRAP_SERVERS: "kafka:9092"
      CONNECT_REST_PORT: 8083
      CONNECT_GROUP_ID: "kafka-connect-bridge"
      CONNECT_CONFIG_STORAGE_TOPIC: "bridge-configs"
      CONNECT_OFFSET_STORAGE_TOPIC: "bridge-offsets"
      CONNECT_STATUS_STORAGE_TOPIC: "bridge-status"
      CONNECT_KEY_CONVERTER: "org.apache.kafka.connect.json.JsonConverter"
      CONNECT_VALUE_CONVERTER: "org.apache.kafka.connect.json.JsonConverter"
      CONNECT_KEY_CONVERTER_SCHEMAS_ENABLE: "false"
      CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE: "false"
      CONNECT_INTERNAL_KEY_CONVERTER: "org.apache.kafka.connect.json.JsonConverter"
      CONNECT_INTERNAL_VALUE_CONVERTER: "org.apache.kafka.connect.json.JsonConverter"
      CONNECT_LOG4J_ROOT_LOGLEVEL: "INFO"
      CONNECT_LOG4J_LOGGERS: "org.apache.kafka.connect.runtime.rest=WARN,org.reflections=ERROR,io.debezium=DEBUG"
      CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR: "1"
      CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR: "1"
      CONNECT_STATUS_STORAGE_REPLICATION_FACTOR: "1"
      CONNECT_PLUGIN_PATH: "/usr/share/java,/usr/share/confluent-hub-components"
    networks:
      - infra_default
    restart: always

networks:
  infra_default:
    external: true
EOF

# Create connector config JSON
cat > connector-config.json << 'EOF'
{
  "name": "bridge-cassandra-connector",
  "config": {
    "connector.class": "io.debezium.connector.cassandra.CassandraConnector",
    "cassandra.hosts": "cassandra",
    "cassandra.port": "9042",
    "cassandra.username": "cassandra",
    "cassandra.password": "cassandra",
    "cassandra.keyspace": "gibsey", 
    "topic.prefix": "gibsey",
    "tasks.max": "1"
  }
}
EOF

# Step 4: Create an explanation of the approaches
echo "=== DEBEZIUM CASSANDRA CONNECTOR SOLUTION OPTIONS ==="
echo "Based on our analysis, there are three potential approaches to fix the issue:"
echo
echo "OPTION 1: Use fixed JAR with service provider file"
echo "- We've checked your existing JAR for the service provider file"
echo "- If missing, we've created a fixed JAR with the service provider file added"
echo "- Update your Dockerfile to use this fixed JAR:"
echo "  COPY ./infra/debezium-plugins/fixed-connector.jar /kafka/connect/debezium-connector-cassandra/"
echo
echo "OPTION 2: Use standalone Kafka Connect approach"
echo "- A standalone Kafka Connect setup that uses the connect-standalone.sh script"
echo "- Runs in a separate container on port 8089"
echo "- To start: cd /tmp/standalone-fix && docker-compose up -d"
echo
echo "OPTION 3: Use Confluent Kafka Connect"
echo "- Uses Confluent Platform's Kafka Connect instead of Debezium's version"
echo "- Typically has better compatibility and more reliable plugin loading"
echo "- Runs in a separate container on port 8088"
echo "- To start: cd /tmp/kafka-connect-bridge && docker-compose up -d"
echo "- After starting, create the connector:"
echo "  curl -X POST -H \"Content-Type: application/json\" -d @connector-config.json http://localhost:8088/connectors"
echo
echo "RECOMMENDATION:"
echo "Start with Option 3 (Confluent Kafka Connect) as it's the most reliable approach"
echo "This will help isolate whether the issue is with the connector itself or with Debezium"