#!/bin/bash
# Fix volume paths in docker-compose.cdc.yml

echo "=== FIXING VOLUME PATHS ==="

# Create backup of current file
cp infra/docker-compose.cdc.yml infra/docker-compose.cdc.yml.bak

# Update the docker-compose.cdc.yml file to fix the volume path for Faust worker
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

  # Debezium for CDC (Change Data Capture)
  debezium:
    build:
      context: .
      dockerfile: infra/simple-debezium.Dockerfile
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
      # Plugin path setting
      CONNECT_PLUGIN_PATH: /kafka/connect
      # Logging configuration for debugging
      CONNECT_LOG4J_ROOTLOGGER: INFO
      CONNECT_LOG4J_LOGGERS: org.apache.kafka.connect.runtime.rest=WARN,org.reflections=ERROR,io.debezium=DEBUG
      # For debugging
      CONNECT_DEBUG: "true"
      
  # Faust Worker - processes Kafka messages
  faust-worker:
    build:
      context: .
      dockerfile: faust_worker/Dockerfile
    container_name: gibsey-faust-worker
    volumes:
      - ./faust_worker:/app:ro
    depends_on:
      kafka:
        condition: service_healthy
    environment:
      KAFKA_BROKER: kafka:9092
      STARGATE_URL: http://stargate:8082
    command: python app.py worker -l info

volumes:
  cassandra_data:
  debezium_logs:
EOF

echo "Updated docker-compose file with fixed volume paths and simpler Debezium image"

# Create a simpler Debezium Dockerfile
cat > infra/simple-debezium.Dockerfile << 'EOF'
FROM debezium/connect:2.4

USER root
RUN mkdir -p /kafka/connect/debezium-connector-cassandra
RUN curl -Lo /tmp/connector.jar https://repo1.maven.org/maven2/io/debezium/debezium-connector-cassandra/2.4.2.Final/debezium-connector-cassandra-2.4.2.Final-plugin.jar

# Create the service provider file
RUN mkdir -p /tmp/services/META-INF/services/
RUN echo "io.debezium.connector.cassandra.CassandraConnector" > /tmp/services/META-INF/services/org.apache.kafka.connect.source.SourceConnector

# Add the service provider to the JAR
RUN mkdir -p /kafka/connect/debezium-connector-cassandra/META-INF/services/
RUN cp /tmp/services/META-INF/services/org.apache.kafka.connect.source.SourceConnector /kafka/connect/debezium-connector-cassandra/META-INF/services/
RUN cp /tmp/connector.jar /kafka/connect/debezium-connector-cassandra/

# Fix permissions
RUN chown -R kafka:kafka /kafka/connect && chmod -R 755 /kafka/connect

USER kafka
EOF

echo
echo "Created simplified Debezium Dockerfile"
echo
echo "=== FIXES APPLIED ==="
echo "Next, run: docker compose -f infra/docker-compose.cdc.yml up -d --build"