#!/bin/bash
# Comprehensive CDC Pipeline verification script
# This script tests the entire CDC pipeline functionality

# Text formatting for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}===== VERIFYING CDC PIPELINE OPERATION =====${NC}"

# Step 1: Check if all required services are running
echo -e "\n${YELLOW}Checking if all required services are running...${NC}"
SERVICES=("gibsey-cassandra" "gibsey-kafka" "gibsey-zookeeper" "gibsey-debezium" "gibsey-faust-worker")
ALL_RUNNING=true

for SERVICE in "${SERVICES[@]}"; do
    if docker ps | grep -q "$SERVICE"; then
        echo -e "${GREEN}✓ $SERVICE is running${NC}"
    else
        echo -e "${RED}✗ $SERVICE is not running${NC}"
        ALL_RUNNING=false
    fi
done

if [ "$ALL_RUNNING" = false ]; then
    echo -e "${RED}Some services are not running. Please start the CDC stack using:${NC}"
    echo "docker compose -f infra/docker-compose.cdc.yml up -d"
    exit 1
fi

# Step 2: Check Debezium health
echo -e "\n${YELLOW}Checking Debezium health...${NC}"
DEBEZIUM_HEALTH=$(curl -s http://localhost:8083/ | grep version)
if [[ ! -z "$DEBEZIUM_HEALTH" ]]; then
    echo -e "${GREEN}✓ Debezium is healthy${NC}"
    echo "$DEBEZIUM_HEALTH"
else
    echo -e "${RED}✗ Debezium might not be healthy${NC}"
    echo "Attempting to get detailed status..."
    curl -s http://localhost:8083/ || echo -e "${RED}Failed to connect to Debezium${NC}"
fi

# Step 3: Check Cassandra keyspace and table
echo -e "\n${YELLOW}Checking Cassandra keyspace and test table...${NC}"
KEYSPACE_CHECK=$(docker exec gibsey-cassandra cqlsh -e "DESCRIBE KEYSPACES;" | grep gibsey)
if [[ ! -z "$KEYSPACE_CHECK" ]]; then
    echo -e "${GREEN}✓ 'gibsey' keyspace exists${NC}"
else
    echo -e "${RED}✗ 'gibsey' keyspace doesn't exist${NC}"
    echo "Creating 'gibsey' keyspace..."
    docker exec gibsey-cassandra cqlsh -e "CREATE KEYSPACE IF NOT EXISTS gibsey WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};"
fi

# Check for test_cdc table and create if it doesn't exist
TABLE_CHECK=$(docker exec gibsey-cassandra cqlsh -e "DESCRIBE TABLES FROM gibsey;" | grep test_cdc)
if [[ ! -z "$TABLE_CHECK" ]]; then
    echo -e "${GREEN}✓ 'test_cdc' table exists${NC}"
else
    echo -e "${YELLOW}! 'test_cdc' table doesn't exist, creating it...${NC}"
    docker exec gibsey-cassandra cqlsh -e "CREATE TABLE IF NOT EXISTS gibsey.test_cdc (id text PRIMARY KEY, data text) WITH cdc = true;"
    echo -e "${GREEN}✓ Created 'test_cdc' table with CDC enabled${NC}"
fi

# Step 4: Check registered connectors
echo -e "\n${YELLOW}Checking registered connectors...${NC}"
CONNECTORS=$(curl -s http://localhost:8083/connectors)
if [[ "$CONNECTORS" == "[]" ]]; then
    echo -e "${YELLOW}! No connectors are registered${NC}"
    
    # Check if connector config exists
    if [ -f "infra/connectors/cassandra-connector.json" ]; then
        echo "Registering Cassandra connector..."
        REGISTER_RESULT=$(curl -s -X POST -H "Content-Type: application/json" -d @infra/connectors/cassandra-connector.json http://localhost:8083/connectors)
        echo "$REGISTER_RESULT"
        
        # Now check again to verify
        CONNECTORS=$(curl -s http://localhost:8083/connectors)
        if [[ "$CONNECTORS" != "[]" ]]; then
            echo -e "${GREEN}✓ Connector registered successfully${NC}"
        else
            echo -e "${RED}✗ Failed to register connector${NC}"
        fi
    else
        echo -e "${RED}✗ Connector configuration file not found${NC}"
        echo "Creating a basic connector configuration..."
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
    "table.include.list": "gibsey.test_cdc",
    "snapshot.mode": "initial",
    "errors.log.enable": "true"
  }
}
EOF
        echo "Registering the connector..."
        REGISTER_RESULT=$(curl -s -X POST -H "Content-Type: application/json" -d @infra/connectors/cassandra-connector.json http://localhost:8083/connectors)
        echo "$REGISTER_RESULT"
    fi
else
    echo -e "${GREEN}✓ Connectors are registered:${NC}"
    echo "$CONNECTORS"
    
    # Check connector status
    for CONNECTOR in $(echo "$CONNECTORS" | jq -r '.[]'); do
        echo -e "\n${YELLOW}Checking status of $CONNECTOR...${NC}"
        CONNECTOR_STATUS=$(curl -s http://localhost:8083/connectors/$CONNECTOR/status)
        CONNECTOR_STATE=$(echo "$CONNECTOR_STATUS" | jq -r '.connector.state' 2>/dev/null)
        
        if [[ "$CONNECTOR_STATE" == "RUNNING" ]]; then
            echo -e "${GREEN}✓ Connector $CONNECTOR is running${NC}"
        else
            echo -e "${RED}✗ Connector $CONNECTOR is not running, state: $CONNECTOR_STATE${NC}"
            echo "Detailed status:"
            echo "$CONNECTOR_STATUS" | jq
        fi
    done
fi

# Step 5: Insert test data to trigger CDC
echo -e "\n${YELLOW}Inserting test data to trigger CDC...${NC}"
TIMESTAMP=$(date +%s)
TEST_ID="test-$TIMESTAMP"
TEST_DATA="CDC test data - $TIMESTAMP"

echo "Inserting record with ID: $TEST_ID"
docker exec gibsey-cassandra cqlsh -e "INSERT INTO gibsey.test_cdc (id, data) VALUES ('$TEST_ID', '$TEST_DATA');"

# Step 6: Check Kafka topics
echo -e "\n${YELLOW}Checking Kafka topics...${NC}"
KAFKA_TOPICS=$(docker exec gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list)
echo "$KAFKA_TOPICS"

CDC_TOPIC=$(echo "$KAFKA_TOPICS" | grep "gibsey.gibsey.test_cdc")
if [[ ! -z "$CDC_TOPIC" ]]; then
    echo -e "${GREEN}✓ Found CDC topic: $CDC_TOPIC${NC}"
else
    echo -e "${RED}✗ CDC topic not found. It might take a moment to be created.${NC}"
    echo "Waiting 30 seconds for topic creation..."
    sleep 30
    
    # Check again
    KAFKA_TOPICS=$(docker exec gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list)
    CDC_TOPIC=$(echo "$KAFKA_TOPICS" | grep "gibsey.gibsey.test_cdc")
    if [[ ! -z "$CDC_TOPIC" ]]; then
        echo -e "${GREEN}✓ Found CDC topic after waiting: $CDC_TOPIC${NC}"
    else
        echo -e "${RED}✗ CDC topic still not found after waiting.${NC}"
    fi
fi

# Step 7: Look for events in Kafka topic
if [[ ! -z "$CDC_TOPIC" ]]; then
    echo -e "\n${YELLOW}Looking for events in the CDC topic...${NC}"
    echo "This may take a moment..."
    EVENTS=$(docker exec gibsey-kafka kafka-console-consumer --bootstrap-server kafka:9092 --topic $CDC_TOPIC --from-beginning --max-messages 5 --timeout-ms 10000)
    
    if [[ ! -z "$EVENTS" ]]; then
        echo -e "${GREEN}✓ Found events in the topic:${NC}"
        echo "$EVENTS" | jq . || echo "$EVENTS"
        
        # Check if our test record appears
        if echo "$EVENTS" | grep -q "$TEST_ID"; then
            echo -e "${GREEN}✓ Our test record ($TEST_ID) was captured by CDC!${NC}"
        else
            echo -e "${YELLOW}! Our test record wasn't found in the sample. It might appear later or farther down in the stream.${NC}"
        fi
    else
        echo -e "${RED}✗ No events found in the topic.${NC}"
    fi
fi

# Step 8: Check Faust worker logs
echo -e "\n${YELLOW}Checking Faust worker logs...${NC}"
FAUST_LOGS=$(docker logs --tail 50 gibsey-faust-worker 2>&1)
echo "$FAUST_LOGS" | grep -E "Received event|$TEST_ID|Operation:|gibsey.test_cdc" || echo -e "${RED}No relevant log entries found${NC}"

# Step 9: Summary
echo -e "\n${YELLOW}===== CDC PIPELINE VERIFICATION SUMMARY =====${NC}"

if [[ ! -z "$CDC_TOPIC" ]] && [[ ! -z "$EVENTS" ]]; then
    echo -e "${GREEN}The CDC pipeline appears to be working!${NC}"
    echo -e "1. All services are running"
    echo -e "2. Debezium is operational"
    echo -e "3. CDC topic was created"
    echo -e "4. Events are flowing through Kafka"
    
    # Add note about Faust worker
    if echo "$FAUST_LOGS" | grep -q "Received event"; then
        echo -e "5. Faust worker is processing events"
    else
        echo -e "${YELLOW}Note: Faust worker may not be showing logs for events yet. Check its configuration.${NC}"
    fi
else
    echo -e "${RED}There might be issues with the CDC pipeline.${NC}"
    echo -e "Please check:"
    
    if [ "$ALL_RUNNING" = false ]; then
        echo -e "- Not all services are running"
    fi
    
    if [[ -z "$DEBEZIUM_HEALTH" ]]; then
        echo -e "- Debezium might not be healthy"
    fi
    
    if [[ -z "$CDC_TOPIC" ]]; then
        echo -e "- CDC topic was not created"
    fi
    
    if [[ -z "$EVENTS" ]] && [[ ! -z "$CDC_TOPIC" ]]; then
        echo -e "- No events were found in the CDC topic"
    fi
    
    echo -e "\nFor detailed troubleshooting:"
    echo -e "1. Check Debezium logs: docker logs gibsey-debezium"
    echo -e "2. Check Faust worker logs: docker logs gibsey-faust-worker"
    echo -e "3. Run scripts/fix-debezium-once-and-for-all.sh to reconfigure the CDC pipeline"
fi

echo -e "\n${YELLOW}===== VERIFICATION COMPLETE =====${NC}"