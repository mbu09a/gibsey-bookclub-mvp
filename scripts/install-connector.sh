#!/bin/bash
# Script to install the Cassandra connector inside the Debezium container

echo "=== INSTALLING CASSANDRA CONNECTOR ==="

# Step 1: Download the connector jar directly into the container
echo "Downloading connector JAR into Debezium container..."
docker exec -it gibsey-debezium bash -c "curl -sLo /tmp/connector.jar https://repo1.maven.org/maven2/io/debezium/debezium-connector-cassandra/2.4.2.Final/debezium-connector-cassandra-2.4.2.Final-plugin.jar"

# Step 2: Create the plugin directory structure
echo "Creating connector directory structure..."
docker exec -it gibsey-debezium bash -c "mkdir -p /kafka/connect/debezium-connector-cassandra/META-INF/services"

# Step 3: Create the service provider file
echo "Creating service provider file..."
docker exec -it gibsey-debezium bash -c "echo 'io.debezium.connector.cassandra.CassandraConnector' > /kafka/connect/debezium-connector-cassandra/META-INF/services/org.apache.kafka.connect.source.SourceConnector"

# Step 4: Move the JAR to the correct location
echo "Installing connector JAR..."
docker exec -it gibsey-debezium bash -c "cp /tmp/connector.jar /kafka/connect/debezium-connector-cassandra/"

# Step 5: Fix permissions
echo "Setting correct permissions..."
docker exec -it gibsey-debezium bash -c "chown -R kafka:kafka /kafka/connect/debezium-connector-cassandra && chmod -R 755 /kafka/connect/debezium-connector-cassandra"

# Step 6: Restart Debezium to pick up the new connector
echo "Restarting Debezium..."
docker restart gibsey-debezium

# Step 7: Wait for Debezium to restart
echo "Waiting for Debezium to restart (30 seconds)..."
sleep 30

# Step 8: Verify connector is available
echo "Verifying connector availability..."
curl -s http://localhost:8083/connector-plugins | grep CassandraConnector

echo -e "\n=== CONNECTOR INSTALLATION COMPLETE ==="
echo "To register the connector, run: ./scripts/complete-cdc-test.sh"