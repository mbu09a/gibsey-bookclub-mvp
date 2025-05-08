#!/bin/bash
# Enhanced service check for Debezium CDC pipeline

echo "=== ENHANCED SERVICE CHECK ==="

# Track process
declare -A service_status
service_status["cassandra"]="Unknown"
service_status["zookeeper"]="Unknown"
service_status["kafka"]="Unknown"
service_status["debezium"]="Unknown"
service_status["faust"]="Unknown"

# Check container status
echo "Checking container status..."
if docker ps | grep -q gibsey-cassandra; then
    service_status["cassandra"]="Running"
else
    service_status["cassandra"]="Stopped"
fi

if docker ps | grep -q gibsey-zookeeper; then
    service_status["zookeeper"]="Running"
else
    service_status["zookeeper"]="Stopped"
fi

if docker ps | grep -q gibsey-kafka; then
    service_status["kafka"]="Running"
else
    service_status["kafka"]="Stopped"
fi

if docker ps | grep -q gibsey-debezium; then
    service_status["debezium"]="Running"
else
    service_status["debezium"]="Stopped"
fi

if docker ps | grep -q gibsey-faust-worker; then
    service_status["faust"]="Running"
else
    service_status["faust"]="Stopped"
fi

# Print status summary
echo "=== SERVICE STATUS ==="
echo "Cassandra:  ${service_status["cassandra"]}"
echo "Zookeeper:  ${service_status["zookeeper"]}"
echo "Kafka:      ${service_status["kafka"]}"
echo "Debezium:   ${service_status["debezium"]}"
echo "Faust:      ${service_status["faust"]}"
echo "===================="

# Only proceed with deeper checks if all services are running
if [[ "${service_status["cassandra"]}" != "Running" || 
      "${service_status["zookeeper"]}" != "Running" || 
      "${service_status["kafka"]}" != "Running" || 
      "${service_status["debezium"]}" != "Running" ]]; then
    echo "❌ Some services are not running. Start them with:"
    echo "docker compose -f infra/docker-compose.cdc.yml up -d"
    exit 1
fi

# Check Debezium API
echo "Checking Debezium API..."
if curl -s http://localhost:8083/ | grep -q "Kafka Connect"; then
    echo "✅ Debezium API is responding"
else
    echo "❌ Debezium API is not responding"
    echo "Check logs: docker logs gibsey-debezium"
    exit 1
fi

# Check if our keyspace exists
echo "Checking Cassandra keyspace..."
if docker exec gibsey-cassandra cqlsh -e "DESCRIBE KEYSPACES;" | grep -q gibsey; then
    echo "✅ Keyspace 'gibsey' exists"
    
    # Check tables with CDC enabled
    echo "Checking CDC-enabled tables..."
    CDC_TABLES=$(docker exec gibsey-cassandra cqlsh -e "SELECT keyspace_name, table_name FROM system_schema.tables WHERE keyspace_name='gibsey' AND cdc=true;")
    if echo "$CDC_TABLES" | grep -q "gibsey"; then
        echo "✅ CDC-enabled tables found:"
        echo "$CDC_TABLES" | grep -v "^$" | tail -n +4 | head -n -2
    else
        echo "❌ No CDC-enabled tables found"
        echo "Creating test_cdc table with CDC enabled..."
        docker exec gibsey-cassandra cqlsh -e "CREATE TABLE IF NOT EXISTS gibsey.test_cdc (id text PRIMARY KEY, data text) WITH cdc = true;"
        echo "Inserting test data..."
        docker exec gibsey-cassandra cqlsh -e "INSERT INTO gibsey.test_cdc (id, data) VALUES ('test-enhanced-$(date +%s)', 'Test data from enhanced check');"
    fi
else
    echo "❌ Keyspace 'gibsey' does not exist"
    echo "Creating keyspace and test table..."
    docker exec gibsey-cassandra cqlsh -e "CREATE KEYSPACE IF NOT EXISTS gibsey WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};"
    docker exec gibsey-cassandra cqlsh -e "CREATE TABLE IF NOT EXISTS gibsey.test_cdc (id text PRIMARY KEY, data text) WITH cdc = true;"
    docker exec gibsey-cassandra cqlsh -e "INSERT INTO gibsey.test_cdc (id, data) VALUES ('test-enhanced-$(date +%s)', 'Test data from enhanced check');"
fi

# Check connectors
echo "Checking registered connectors..."
CONNECTORS=$(curl -s http://localhost:8083/connectors)
if [[ "$CONNECTORS" != "[]" ]]; then
    echo "✅ Connectors registered: $CONNECTORS"
    
    # Check each connector status
    for CONNECTOR in $(echo $CONNECTORS | tr -d '[]"' | tr ',' ' '); do
        echo "Checking status of connector: $CONNECTOR"
        CONNECTOR_STATUS=$(curl -s http://localhost:8083/connectors/$CONNECTOR/status)
        STATE=$(echo "$CONNECTOR_STATUS" | grep -o '"state":"[^"]*"' | cut -d':' -f2 | tr -d '"')
        echo "  Connector $CONNECTOR state: $STATE"
        
        # Check tasks
        TASKS_STATUS=$(echo "$CONNECTOR_STATUS" | grep -o '"tasks":\[.*\]' | grep -o '"state":"[^"]*"' | cut -d':' -f2 | tr -d '"' | sort | uniq -c)
        echo "  Tasks status: $TASKS_STATUS"
    done
else
    echo "❌ No connectors registered"
    echo "Setting up a test connector..."
    cat > /tmp/test-connector.json << 'EOF'
{
  "name": "test-connector",
  "config": {
    "connector.class": "io.debezium.connector.cassandra.CassandraConnector",
    "tasks.max": "1",
    "cassandra.hosts": "cassandra",
    "cassandra.port": "9042",
    "cassandra.username": "cassandra",
    "cassandra.password": "cassandra",
    "cassandra.keyspace": "gibsey",
    "topic.prefix": "gibsey",
    "table.include.list": "gibsey.test_cdc",
    "snapshot.mode": "initial",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
  }
}
EOF
    curl -X POST -H "Content-Type: application/json" -d @/tmp/test-connector.json http://localhost:8083/connectors
    echo ""
    sleep 5
    NEW_STATUS=$(curl -s http://localhost:8083/connectors/test-connector/status)
    echo "New connector status: $NEW_STATUS"
fi

# Check Kafka topics
echo "Checking Kafka topics (looking for topics with 'gibsey' prefix)..."
TOPICS=$(docker exec gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list | grep gibsey)
if [[ -n "$TOPICS" ]]; then
    echo "✅ Found Kafka topics:"
    echo "$TOPICS"
    
    # Check for messages in topics
    echo "Checking for messages in topics..."
    for TOPIC in $TOPICS; do
        echo "Messages in $TOPIC:"
        docker exec gibsey-kafka kafka-console-consumer --bootstrap-server kafka:9092 --topic $TOPIC --from-beginning --max-messages 1 --timeout-ms 5000 || echo "No messages or timeout"
    done
else
    echo "❌ No topics with 'gibsey' prefix found"
    echo "Issues to check:"
    echo "1. Is the connector running correctly? Check connector status above"
    echo "2. Are there CDC-enabled tables with data?"
    echo "3. Check Debezium logs for errors: docker logs gibsey-debezium"
fi

# Generate diagnostic dump if issues detected
if [[ -z "$TOPICS" || "$CONNECTORS" == "[]" ]]; then
    echo "Creating diagnostic dump..."
    DUMP_DIR="cdc-diagnostics-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$DUMP_DIR"
    
    # Collect container logs
    docker logs gibsey-debezium > "$DUMP_DIR/debezium.log" 2>&1
    docker logs gibsey-kafka > "$DUMP_DIR/kafka.log" 2>&1
    docker logs gibsey-cassandra > "$DUMP_DIR/cassandra.log" 2>&1
    
    # Collect Cassandra schema
    docker exec gibsey-cassandra cqlsh -e "DESCRIBE KEYSPACE gibsey;" > "$DUMP_DIR/gibsey_schema.cql" 2>&1
    
    # Check Debezium plugin path and JAR files
    docker exec gibsey-debezium ls -la /kafka/connect > "$DUMP_DIR/debezium_plugins.txt" 2>&1
    
    # Check service provider files in JARs
    docker exec gibsey-debezium find /kafka/connect -name "*.jar" -exec sh -c 'echo "JAR: $0"; unzip -p "$0" META-INF/services/org.apache.kafka.connect.source.SourceConnector 2>/dev/null || echo "  No connector provider file found"' {} \; > "$DUMP_DIR/jar_service_providers.txt" 2>&1
    
    echo "Diagnostic dump created in $DUMP_DIR directory."
fi

echo
echo "=== ENHANCED SERVICE CHECK COMPLETE ==="
echo "Based on the above checks, here's what to do next:"

if [[ -z "$TOPICS" && "$CONNECTORS" != "[]" ]]; then
    echo "❓ Connectors are registered but no topics are being created."
    echo "1. Try inserting more test data: docker exec gibsey-cassandra cqlsh -e \"INSERT INTO gibsey.test_cdc (id, data) VALUES ('test-fix-$(date +%s)', 'New test data');\""
    echo "2. Check connector configuration to ensure table_include_list matches your tables"
    echo "3. Restart Debezium: docker restart gibsey-debezium"
elif [[ "$CONNECTORS" == "[]" ]]; then
    echo "❓ No connectors are registered."
    echo "1. Register a connector using curl command shown above"
    echo "2. Check if connector JAR file has the service provider file"
elif [[ -n "$TOPICS" ]]; then
    echo "✅ CDC pipeline appears to be working correctly!"
    echo "1. Make sure your Faust worker is processing events properly"
    echo "2. Implement actual page vector update logic in the worker"
fi