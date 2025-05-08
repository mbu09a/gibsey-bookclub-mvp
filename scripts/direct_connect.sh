#!/bin/bash
# Direct Kafka Connect Runner - Bypasses Docker complexity for testing

echo "=== RUNNING KAFKA CONNECT DIRECTLY ==="

# Create a temporary directory
mkdir -p /tmp/direct-connect
cd /tmp/direct-connect

# Download required JARs (assuming you have Maven installed)
echo "Downloading Kafka Connect framework..."
mvn org.apache.maven.plugins:maven-dependency-plugin:3.3.0:get \
  -Dartifact=org.apache.kafka:connect-json:3.5.1 \
  -Ddest=./connect-json-3.5.1.jar

echo "Downloading Debezium Cassandra connector..."
cp "/Users/ghostradongus/Desktop/Gibsey Bookclub MVP/infra/debezium-plugins/debezium-connector-cassandra-4-2.4.2.Final.jar" ./

# Create a properties file
echo "Creating properties file..."
cat > connect-standalone.properties << 'EOF'
# Basic Kafka Connect configuration for standalone mode
bootstrap.servers=localhost:29092
key.converter=org.apache.kafka.connect.json.JsonConverter
value.converter=org.apache.kafka.connect.json.JsonConverter
key.converter.schemas.enable=false
value.converter.schemas.enable=false

# Logging configuration
log4j.rootLogger=INFO, stdout
log4j.appender.stdout=org.apache.log4j.ConsoleAppender
log4j.appender.stdout.layout=org.apache.log4j.PatternLayout
log4j.appender.stdout.layout.ConversionPattern=[%d] %p %m (%c:%L)%n

# Directories where Connect looks for plugins
plugin.path=./

# REST API configuration
rest.port=8087
rest.advertised.host.name=localhost
rest.advertised.port=8087

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
cassandra.hosts=localhost
cassandra.port=9042
cassandra.username=cassandra
cassandra.password=cassandra
cassandra.keyspace=gibsey
topic.prefix=gibsey
EOF

# Create a Java launcher script
echo "Creating launcher script..."
cat > run-connect.sh << 'EOF'
#!/bin/bash

echo "Starting Kafka Connect in standalone mode..."
java -cp "*" org.apache.kafka.connect.cli.ConnectStandalone connect-standalone.properties cassandra-connector.properties
EOF
chmod +x run-connect.sh

echo
echo "=== DIRECT KAFKA CONNECT SETUP COMPLETE ==="
echo "To run Kafka Connect directly (requires Java and Maven):"
echo "cd /tmp/direct-connect && ./run-connect.sh"
echo
echo "Note: This bypasses Docker and runs Kafka Connect directly"
echo "on your host machine, connecting to your existing infrastructure."
echo "Use this for debugging the connector itself rather than container issues."