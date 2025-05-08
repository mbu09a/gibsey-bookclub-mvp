#!/bin/bash
# Script to fix Debezium's Cassandra connector setup

echo "=== FIXING DEBEZIUM CASSANDRA CONNECTOR ==="

# Check if Debezium container is running
if ! docker ps | grep -q gibsey-debezium; then
  echo "❌ Debezium container is not running!"
  echo "Start it with: docker compose -f infra/docker-compose.cdc.yml up -d"
  exit 1
fi

echo "Step 1: Downloading the correct Cassandra 4 connector JAR..."
echo "This will create a temporary script to run inside the Debezium container"

# Create a temporary script to download the connector
cat > /tmp/fix-connector.sh << 'EOF'
#!/bin/bash
# Temporary script to download the correct Cassandra connector

mkdir -p /kafka/connect/debezium-connector-cassandra
cd /kafka/connect/debezium-connector-cassandra

echo "Removing any existing connector files..."
rm -f connector.jar

echo "Downloading Cassandra 4 connector..."
wget -O connector.jar https://repo1.maven.org/maven2/io/debezium/debezium-connector-cassandra-4/2.4.2.Final/debezium-connector-cassandra-4-2.4.2.Final-jar-with-dependencies.jar

echo "Setting up service provider configuration..."
mkdir -p META-INF/services
echo "io.debezium.connector.cassandra.CassandraConnector" > META-INF/services/org.apache.kafka.connect.source.SourceConnector

echo "Checking downloaded JAR file..."
ls -la
file connector.jar

echo "Download complete. Restart Debezium to apply changes."
EOF

# Copy the script to the container and execute it
echo "Step 2: Copying and running the fix script inside the container..."
docker cp /tmp/fix-connector.sh gibsey-debezium:/tmp/
docker exec -it gibsey-debezium bash -c "chmod +x /tmp/fix-connector.sh && /tmp/fix-connector.sh"

# Clean up
rm /tmp/fix-connector.sh

echo "Step 3: Restarting Debezium to apply changes..."
docker restart gibsey-debezium

echo "Step 4: Waiting for Debezium to restart (30 seconds)..."
sleep 30

echo "Step 5: Checking available connector plugins..."
curl -s http://localhost:8083/connector-plugins | grep -i cassandra || echo "Cassandra connector not found. Check Debezium logs."

echo
echo "=== FIX COMPLETE ==="
echo "If the Cassandra connector is now available, you can create it with:"
echo "./scripts/create-connector.sh"
echo
echo "If the connector is still not available, check the Debezium logs:"
echo "docker logs gibsey-debezium"