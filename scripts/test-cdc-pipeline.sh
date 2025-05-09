#!/bin/bash
# Script to test the CDC pipeline end-to-end

# Text formatting for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}===== TESTING CDC PIPELINE =====${NC}"

# Step 1: Check if services are running
echo -e "\n${YELLOW}Checking if services are running...${NC}"
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

# Step 2: Check if Debezium connector is registered
echo -e "\n${YELLOW}Checking Debezium connector status...${NC}"
CONNECTOR_STATUS=$(curl -s http://localhost:8083/connectors/cassandra-connector/status 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$CONNECTOR_STATUS" ]; then
    echo -e "${RED}Failed to get connector status. Checking if Debezium is running...${NC}"
    if curl -s -f http://localhost:8083/ > /dev/null; then
        echo -e "${GREEN}Debezium is running. Will try to register the connector.${NC}"
    else
        echo -e "${RED}Cannot connect to Debezium API. Check if the service is healthy.${NC}"
        docker logs --tail 20 gibsey-debezium
        exit 1
    fi
else
    echo "$CONNECTOR_STATUS" | grep -q "state" && echo "$CONNECTOR_STATUS" | grep "state" || echo "$CONNECTOR_STATUS"
fi

# Check if connector is running or try to register
STATE=$(echo "$CONNECTOR_STATUS" | grep -o '"state":"[^"]*"' | cut -d'"' -f4)
if [[ "$STATE" == "RUNNING" ]]; then
    echo -e "${GREEN}✓ Connector is running${NC}"
else
    echo -e "${YELLOW}Connector is not running or not registered. Trying to register it...${NC}"
    
    # Check if connector config exists
    if [ -f "infra/connectors/cassandra-connector.json" ]; then
        curl -X POST -H "Content-Type: application/json" -d @infra/connectors/cassandra-connector.json http://localhost:8083/connectors
        echo
        sleep 5
        
        # Check status again
        NEW_STATUS=$(curl -s http://localhost:8083/connectors/cassandra-connector/status 2>/dev/null)
        NEW_STATE=$(echo "$NEW_STATUS" | grep -o '"state":"[^"]*"' | cut -d'"' -f4)
        
        if [[ "$NEW_STATE" == "RUNNING" ]]; then
            echo -e "${GREEN}✓ Successfully registered connector${NC}"
        else
            echo -e "${RED}Failed to register connector. Status:${NC}"
            echo "$NEW_STATUS" | grep -q "state" && echo "$NEW_STATUS" | grep "state" || echo "$NEW_STATUS"
        fi
    else
        echo -e "${RED}Connector configuration file not found at infra/connectors/cassandra-connector.json${NC}"
        exit 1
    fi
fi

# Step 3: Check Cassandra and create test table if needed
echo -e "\n${YELLOW}Checking Cassandra CDC tables...${NC}"
if ! docker exec -it gibsey-cassandra cqlsh -e "DESCRIBE KEYSPACES;" 2>/dev/null | grep -q "gibsey"; then
    echo -e "${YELLOW}Creating gibsey keyspace...${NC}"
    docker exec -it gibsey-cassandra cqlsh -e "CREATE KEYSPACE IF NOT EXISTS gibsey WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};" 2>/dev/null
fi

if ! docker exec -it gibsey-cassandra cqlsh -e "DESCRIBE TABLES FROM gibsey;" 2>/dev/null | grep -q "test_cdc"; then
    echo -e "${YELLOW}Creating test_cdc table with CDC enabled...${NC}"
    docker exec -it gibsey-cassandra cqlsh -e "CREATE TABLE IF NOT EXISTS gibsey.test_cdc (id text PRIMARY KEY, data text) WITH cdc = true;" 2>/dev/null
fi

# Step 4: Insert data into Cassandra to trigger CDC
echo -e "\n${YELLOW}Inserting test data into Cassandra...${NC}"
TEST_ID="test-$(date +%s)"
TEST_DATA="CDC test at $(date)"
docker exec -it gibsey-cassandra cqlsh -e "INSERT INTO gibsey.test_cdc (id, data) VALUES ('$TEST_ID', '$TEST_DATA');" 2>/dev/null

# Step A5: Check if CDC is enabled on the table
echo -e "\n${YELLOW}Verifying CDC is enabled on tables...${NC}"
CDC_TABLES=$(docker exec -it gibsey-cassandra cqlsh -e "SELECT keyspace_name, table_name, cdc FROM system_schema.tables WHERE keyspace_name='gibsey';" 2>/dev/null | grep "True")
if [ -z "$CDC_TABLES" ]; then
    echo -e "${RED}No tables with CDC enabled found. This will prevent CDC from working.${NC}"
    
    # Recreate table with explicit CDC
    echo -e "${YELLOW}Recreating test_cdc table with explicit CDC...${NC}"
    docker exec -it gibsey-cassandra cqlsh -e "DROP TABLE IF EXISTS gibsey.test_cdc;" 2>/dev/null
    docker exec -it gibsey-cassandra cqlsh -e "CREATE TABLE gibsey.test_cdc (id text PRIMARY KEY, data text) WITH cdc = true;" 2>/dev/null
    
    # Insert data again
    docker exec -it gibsey-cassandra cqlsh -e "INSERT INTO gibsey.test_cdc (id, data) VALUES ('$TEST_ID', '$TEST_DATA');" 2>/dev/null
    
    # Verify CDC again
    CDC_TABLES=$(docker exec -it gibsey-cassandra cqlsh -e "SELECT keyspace_name, table_name, cdc FROM system_schema.tables WHERE keyspace_name='gibsey';" 2>/dev/null | grep "True")
    if [ -z "$CDC_TABLES" ]; then
        echo -e "${RED}Failed to enable CDC on tables. Check Cassandra configuration.${NC}"
    else
        echo -e "${GREEN}✓ Successfully enabled CDC on tables${NC}"
    fi
else
    echo -e "${GREEN}✓ CDC is enabled on tables:${NC}"
    echo "$CDC_TABLES"
fi

# Step 6: Wait for events to flow through the pipeline
echo -e "\n${YELLOW}Waiting for CDC events to flow through the pipeline (15 seconds)...${NC}"
sleep 15

# Step 7: Check Kafka topics
echo -e "\n${YELLOW}Checking Kafka topics...${NC}"
ALL_TOPICS=$(docker exec -it gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list 2>/dev/null)
echo "All Kafka topics:"
echo "$ALL_TOPICS"

CDC_TOPICS=$(echo "$ALL_TOPICS" | grep -E "gibsey\..*\.test_cdc")
if [ -z "$CDC_TOPICS" ]; then
    echo -e "${RED}No CDC topics found for test_cdc. This suggests the connector is not capturing changes.${NC}"
    
    # Check connector status again
    echo -e "${YELLOW}Checking connector status...${NC}"
    curl -s http://localhost:8083/connectors/cassandra-connector/status | grep -E "state|error|trace" || echo "No status information available"
    
    # Try alternative topic pattern
    ALT_CDC_TOPICS=$(echo "$ALL_TOPICS" | grep "gibsey")
    if [ -n "$ALT_CDC_TOPICS" ]; then
        echo -e "${YELLOW}Found possible CDC topics with different naming pattern:${NC}"
        echo "$ALT_CDC_TOPICS"
        CDC_TOPICS="$ALT_CDC_TOPICS"
    else
        echo -e "${RED}No CDC topics found at all. CDC is not working.${NC}"
    fi
else
    echo -e "${GREEN}✓ Found CDC topics:${NC}"
    echo "$CDC_TOPICS"
fi

# Step 8: Check for messages in the Kafka topic
if [ -n "$CDC_TOPICS" ]; then
    FIRST_TOPIC=$(echo "$CDC_TOPICS" | head -n 1)
    echo -e "\n${YELLOW}Checking for messages in topic $FIRST_TOPIC...${NC}"
    
    # Get messages (with timeout to prevent hanging)
    MESSAGES=$(docker exec -it gibsey-kafka kafka-console-consumer --bootstrap-server kafka:9092 --topic $FIRST_TOPIC --from-beginning --max-messages 3 --timeout-ms 10000 2>/dev/null)
    
    if [ -z "$MESSAGES" ]; then
        echo -e "${RED}No messages found in the topic. CDC events are not flowing.${NC}"
    else
        echo -e "${GREEN}✓ Found CDC messages:${NC}"
        echo "$MESSAGES"
        
        # Check if our test record is captured
        if echo "$MESSAGES" | grep -q "$TEST_ID"; then
            echo -e "${GREEN}✓ Test record with ID '$TEST_ID' was captured by CDC!${NC}"
        else
            echo -e "${YELLOW}Test record not found in the sample messages (it might be in other messages).${NC}"
        fi
    fi
else
    echo -e "${RED}Skipping message check since no CDC topics were found.${NC}"
fi

# Step 9: Check Faust worker logs
echo -e "\n${YELLOW}Checking Faust worker logs...${NC}"
FAUST_LOGS=$(docker logs --tail 50 gibsey-faust-worker 2>/dev/null)

# Check if Faust worker is in compatibility mode
if echo "$FAUST_LOGS" | grep -q "compatibility mode"; then
    echo -e "${RED}Faust worker is running in compatibility mode and not connecting to Kafka.${NC}"
    echo -e "${RED}You need to update faust_worker/app.py to connect to Kafka.${NC}"
else
    # Check for CDC events in Faust logs
    CDC_EVENTS=$(echo "$FAUST_LOGS" | grep -E "Received event|Operation:|$TEST_ID")
    if [ -z "$CDC_EVENTS" ]; then
        echo -e "${RED}No CDC events found in Faust worker logs.${NC}"
    else
        echo -e "${GREEN}✓ Found CDC events in Faust worker logs:${NC}"
        echo "$CDC_EVENTS"
    fi
fi

# Step 10: Summary
echo -e "\n${YELLOW}===== CDC PIPELINE TEST SUMMARY =====${NC}"

if [ -n "$CDC_TOPICS" ] && [ -n "$MESSAGES" ] && [ ! -z "$(echo "$FAUST_LOGS" | grep "Received event")" ]; then
    echo -e "${GREEN}The CDC pipeline appears to be working!${NC}"
    echo -e "1. All services are running"
    echo -e "2. CDC is enabled on Cassandra tables"
    echo -e "3. Debezium connector is capturing changes"
    echo -e "4. Events are flowing through Kafka"
    echo -e "5. Faust worker is processing the events"
else
    echo -e "${RED}Issues were found with the CDC pipeline.${NC}"
    
    # Build a list of specific issues
    if [ "$ALL_RUNNING" = false ]; then
        echo -e "${RED}✗ Not all services are running${NC}"
    fi
    
    if [ -z "$CDC_TABLES" ]; then
        echo -e "${RED}✗ CDC is not enabled on Cassandra tables${NC}"
    fi
    
    if [ -z "$CDC_TOPICS" ]; then
        echo -e "${RED}✗ No CDC topics found in Kafka${NC}"
    elif [ -z "$MESSAGES" ]; then
        echo -e "${RED}✗ No CDC events flowing through Kafka${NC}"
    fi
    
    if echo "$FAUST_LOGS" | grep -q "compatibility mode"; then
        echo -e "${RED}✗ Faust worker is in compatibility mode (not connecting to Kafka)${NC}"
    elif [ -z "$(echo "$FAUST_LOGS" | grep "Received event")" ]; then
        echo -e "${RED}✗ Faust worker is not receiving CDC events${NC}"
    fi
    
    echo -e "\n${YELLOW}For detailed troubleshooting:${NC}"
    echo -e "1. Run ./scripts/diagnose-cdc-issues.sh for detailed diagnostics"
    echo -e "2. Check Debezium logs: docker logs gibsey-debezium"
    echo -e "3. Check Faust worker logs: docker logs gibsey-faust-worker"
fi

echo -e "\n${YELLOW}===== TEST COMPLETE =====${NC}"