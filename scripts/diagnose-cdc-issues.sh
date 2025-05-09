#!/bin/bash
# diagnose-cdc-issues.sh - Script to diagnose CDC issues and fix them

# Text formatting for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${YELLOW}${BOLD}===== CDC PIPELINE DIAGNOSTIC TOOL =====${NC}"
echo "This script will diagnose issues with your CDC pipeline and fix them."

# Step 1: Docker container check
echo -e "\n${YELLOW}${BOLD}STEP 1: Checking Docker containers${NC}"
SERVICES=("gibsey-cassandra" "gibsey-kafka" "gibsey-zookeeper" "gibsey-debezium" "gibsey-faust-worker")
PROBLEMS_FOUND=false

for SERVICE in "${SERVICES[@]}"; do
    if docker ps -a | grep -q "$SERVICE"; then
        STATUS=$(docker ps -a --filter "name=$SERVICE" --format "{{.Status}}" | grep -o "^[^ ]*")
        if [[ "$STATUS" == "Up" ]]; then
            echo -e "${GREEN}✓ $SERVICE is running${NC}"
        else
            echo -e "${RED}✗ $SERVICE is not running (Status: $STATUS)${NC}"
            PROBLEMS_FOUND=true
            
            echo "Container logs for $SERVICE:"
            docker logs --tail 20 $SERVICE
        fi
    else
        echo -e "${RED}✗ $SERVICE does not exist${NC}"
        PROBLEMS_FOUND=true
    fi
done

# Step 2: Debezium connector check
echo -e "\n${YELLOW}${BOLD}STEP 2: Checking Debezium connector${NC}"
if curl -s -f http://localhost:8083/ > /dev/null; then
    echo -e "${GREEN}✓ Debezium API is accessible${NC}"
    
    # Check connector registration
    CONNECTORS=$(curl -s http://localhost:8083/connectors)
    if [[ -z "$CONNECTORS" || "$CONNECTORS" == "[]" ]]; then
        echo -e "${RED}✗ No connectors are registered${NC}"
        PROBLEMS_FOUND=true
    else
        echo -e "${GREEN}✓ Connectors found: $CONNECTORS${NC}"
        
        # Check connector status
        for CONNECTOR in $(echo "$CONNECTORS" | tr -d '[]"' | tr ',' '\n'); do
            echo "Checking status of connector: $CONNECTOR"
            STATUS=$(curl -s http://localhost:8083/connectors/$CONNECTOR/status)
            STATE=$(echo "$STATUS" | grep -o '"state":"[^"]*"' | cut -d'"' -f4)
            
            if [[ "$STATE" == "RUNNING" ]]; then
                echo -e "${GREEN}✓ Connector $CONNECTOR is running${NC}"
            else
                echo -e "${RED}✗ Connector $CONNECTOR is not running (State: $STATE)${NC}"
                echo "Detailed status:"
                echo "$STATUS"
                PROBLEMS_FOUND=true
            fi
        done
    fi
else
    echo -e "${RED}✗ Cannot connect to Debezium API${NC}"
    PROBLEMS_FOUND=true
    
    # Check Debezium logs
    echo "Checking Debezium logs:"
    docker logs --tail 30 gibsey-debezium
fi

# Step 3: Check Cassandra CDC tables
echo -e "\n${YELLOW}${BOLD}STEP 3: Checking Cassandra CDC tables${NC}"
if docker ps | grep -q "gibsey-cassandra"; then
    # Check keyspace
    KEYSPACE_CHECK=$(docker exec -it gibsey-cassandra cqlsh -e "DESCRIBE KEYSPACES;" 2>/dev/null | grep gibsey)
    if [[ -z "$KEYSPACE_CHECK" ]]; then
        echo -e "${RED}✗ 'gibsey' keyspace does not exist${NC}"
        PROBLEMS_FOUND=true
    else
        echo -e "${GREEN}✓ 'gibsey' keyspace exists${NC}"
        
        # Check tables
        TABLES=$(docker exec -it gibsey-cassandra cqlsh -e "DESCRIBE TABLES FROM gibsey;" 2>/dev/null)
        echo "Tables in 'gibsey' keyspace:"
        echo "$TABLES"
        
        # Check CDC enabled
        CDC_CHECK=$(docker exec -it gibsey-cassandra cqlsh -e "SELECT keyspace_name, table_name, cdc FROM system_schema.tables WHERE keyspace_name='gibsey';" 2>/dev/null | grep -i true)
        if [[ -z "$CDC_CHECK" ]]; then
            echo -e "${RED}✗ No tables have CDC enabled${NC}"
            PROBLEMS_FOUND=true
        else
            echo -e "${GREEN}✓ Tables with CDC enabled:${NC}"
            echo "$CDC_CHECK"
        fi
    fi
else
    echo -e "${RED}✗ Cannot check Cassandra tables - container is not running${NC}"
    PROBLEMS_FOUND=true
fi

# Step 4: Check Kafka topics
echo -e "\n${YELLOW}${BOLD}STEP 4: Checking Kafka topics${NC}"
if docker ps | grep -q "gibsey-kafka"; then
    TOPICS=$(docker exec -it gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list 2>/dev/null)
    echo "Available Kafka topics:"
    echo "$TOPICS"
    
    CDC_TOPICS=$(echo "$TOPICS" | grep gibsey)
    if [[ -z "$CDC_TOPICS" ]]; then
        echo -e "${RED}✗ No CDC topics found${NC}"
        PROBLEMS_FOUND=true
    else
        echo -e "${GREEN}✓ CDC topics found${NC}"
        
        # Check for messages
        echo "Checking for messages in the first CDC topic..."
        FIRST_TOPIC=$(echo "$CDC_TOPICS" | head -n 1)
        MESSAGES=$(docker exec -it gibsey-kafka kafka-console-consumer --bootstrap-server kafka:9092 --topic $FIRST_TOPIC --from-beginning --max-messages 1 --timeout-ms 5000 2>/dev/null)
        
        if [[ -z "$MESSAGES" ]]; then
            echo -e "${RED}✗ No messages found in topic $FIRST_TOPIC${NC}"
            PROBLEMS_FOUND=true
        else
            echo -e "${GREEN}✓ Messages found in topic $FIRST_TOPIC${NC}"
        fi
    fi
else
    echo -e "${RED}✗ Cannot check Kafka topics - container is not running${NC}"
    PROBLEMS_FOUND=true
fi

# Step 5: Check Faust worker
echo -e "\n${YELLOW}${BOLD}STEP 5: Checking Faust worker${NC}"
if docker ps | grep -q "gibsey-faust-worker"; then
    echo "Faust worker logs:"
    LOGS=$(docker logs --tail 30 gibsey-faust-worker 2>/dev/null)
    echo "$LOGS"
    
    # Check if it's using the compatibility mode
    if echo "$LOGS" | grep -q "compatibility mode"; then
        echo -e "${RED}✗ Faust worker is running in compatibility mode and not connecting to Kafka${NC}"
        PROBLEMS_FOUND=true
    elif echo "$LOGS" | grep -q "Received event"; then
        echo -e "${GREEN}✓ Faust worker is receiving events${NC}"
    else
        echo -e "${YELLOW}! Faust worker is running but doesn't seem to be receiving events${NC}"
    fi
else
    echo -e "${RED}✗ Cannot check Faust worker - container is not running${NC}"
    PROBLEMS_FOUND=true
fi

# Step 6: Summary and recommendations
echo -e "\n${YELLOW}${BOLD}===== DIAGNOSTIC SUMMARY =====${NC}"
if [ "$PROBLEMS_FOUND" = true ]; then
    echo -e "${RED}Problems were found with your CDC pipeline.${NC}"
    
    echo -e "\n${YELLOW}${BOLD}RECOMMENDATIONS:${NC}"
    
    # Recommendation 1: Fix Faust compatibility mode
    if docker ps | grep -q "gibsey-faust-worker" && docker logs gibsey-faust-worker 2>/dev/null | grep -q "compatibility mode"; then
        echo -e "1. ${BOLD}Update Faust worker to actually connect to Kafka${NC}"
        echo "   Current app.py is using a compatibility mode that doesn't connect to Kafka."
        echo "   Run the following commands to fix it:"
        echo
        echo "   cat > faust_worker/app.py << 'EOF'"
        echo "   import faust"
        echo "   from faust import App, Record"
        echo "   import json"
        echo "   import os"
        echo "   import logging"
        echo "   import requests"
        echo "   import numpy as np"
        echo "   from dotenv import load_dotenv"
        echo
        echo "   # Basic logging setup"
        echo "   logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')"
        echo "   logger = logging.getLogger(__name__)"
        echo
        echo "   # Load environment variables"
        echo "   load_dotenv()"
        echo
        echo "   # Environment variable checks"
        echo "   KAFKA_BROKER = os.getenv('KAFKA_BROKER')"
        echo "   STARGATE_URL = os.getenv('STARGATE_URL')"
        echo
        echo "   if not KAFKA_BROKER:"
        echo "       logger.error(\"KAFKA_BROKER environment variable not set.\")"
        echo "       exit(1)"
        echo "   if not STARGATE_URL:"
        echo "       logger.warning(\"STARGATE_URL environment variable not set. Some functionality may be limited.\")"
        echo "       STARGATE_URL = None"
        echo
        echo "   # Initialize Faust app"
        echo "   app = App("
        echo "       'gibsey_cdc_worker',"
        echo "       broker=f'kafka://{KAFKA_BROKER}',"
        echo "       value_serializer='json',"
        echo "       topic_partitions=1"
        echo "   )"
        echo
        echo "   # Define the input topic pattern"
        echo "   cdc_topic_pattern = app.topic(pattern='gibsey\\.gibsey\\.(pages|vault|ledger)')"
        echo
        echo "   @app.agent(cdc_topic_pattern)"
        echo "   async def process_cdc_event(events):"
        echo "       async for event in events:"
        echo "           logger.info(f\"Received event from topic {event.topic}\")"
        echo "           payload = event.value.get('payload', {})"
        echo "           operation = payload.get('op')"
        echo "           data = payload.get('after') or payload.get('before')"
        echo
        echo "           if not data:"
        echo "               logger.warning(\"Event payload missing data.\")"
        echo "               continue"
        echo
        echo "           table_name = event.topic.split('.')[-1]"
        echo "           logger.info(f\"Operation: {operation}, Table: {table_name}, Data: {data}\")"
        echo
        echo "           if table_name == 'pages':"
        echo "               logger.info(\"Processing page change.\")"
        echo "           elif table_name == 'vault':"
        echo "               logger.info(\"Processing vault change.\")"
        echo "           elif table_name == 'ledger':"
        echo "               logger.info(\"Processing ledger change.\")"
        echo
        echo "   if __name__ == \"__main__\":"
        echo "       app.main()"
        echo "   EOF"
        echo
        echo "   docker compose -f infra/docker-compose.cdc.yml up -d --build faust-worker"
    fi
    
    # Recommendation 2: Fix connector registration
    if curl -s -f http://localhost:8083/ > /dev/null && [[ -z "$(curl -s http://localhost:8083/connectors)" || "$(curl -s http://localhost:8083/connectors)" == "[]" ]]; then
        echo -e "2. ${BOLD}Register the Cassandra connector${NC}"
        echo "   No connector is currently registered with Debezium."
        echo "   Run the following command to register it:"
        echo
        echo "   curl -X POST -H \"Content-Type: application/json\" -d @infra/connectors/cassandra-connector.json http://localhost:8083/connectors"
    fi
    
    # Recommendation 3: Fix CDC-enabled tables
    if docker ps | grep -q "gibsey-cassandra" && [[ -z "$(docker exec -it gibsey-cassandra cqlsh -e "SELECT keyspace_name, table_name, cdc FROM system_schema.tables WHERE keyspace_name='gibsey';" 2>/dev/null | grep -i true)" ]]; then
        echo -e "3. ${BOLD}Create CDC-enabled tables in Cassandra${NC}"
        echo "   No tables with CDC enabled were found."
        echo "   Run the following commands to create a test table with CDC enabled:"
        echo
        echo "   docker exec -it gibsey-cassandra cqlsh -e \"CREATE KEYSPACE IF NOT EXISTS gibsey WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};\""
        echo "   docker exec -it gibsey-cassandra cqlsh -e \"CREATE TABLE IF NOT EXISTS gibsey.test_cdc (id text PRIMARY KEY, data text) WITH cdc = true;\""
        echo "   docker exec -it gibsey-cassandra cqlsh -e \"INSERT INTO gibsey.test_cdc (id, data) VALUES ('test-1', 'CDC test data');\""
    fi
    
    # Recommendation 4: Full restart
    echo -e "4. ${BOLD}Consider a full restart of the CDC pipeline${NC}"
    echo "   If the above recommendations don't solve the issues, try restarting the entire CDC pipeline:"
    echo
    echo "   docker compose -f infra/docker-compose.cdc.yml down"
    echo "   ./scripts/simple-cdc-setup.sh"
    echo "   ./verify-operation.sh"
else
    echo -e "${GREEN}No major problems found with your CDC pipeline!${NC}"
fi

echo -e "\n${YELLOW}${BOLD}===== DIAGNOSTIC COMPLETE =====${NC}"