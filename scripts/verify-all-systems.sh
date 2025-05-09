#!/bin/bash
# verify-all-systems.sh - Comprehensive verification of all system components

# Text formatting
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${YELLOW}${BOLD}===== GIBSEY BOOKCLUB MVP SYSTEM VERIFICATION =====${NC}"

# Function to print section headers
section() {
  echo -e "\n${YELLOW}${BOLD}$1${NC}"
}

# Function to check if command succeeded
check_result() {
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ $1${NC}"
    return 0
  else
    echo -e "${RED}✗ $1${NC}"
    return 1
  fi
}

# Step 1: Check if containers are running
section "STEP 1: Checking system containers"
ALL_GOOD=true

# Define required containers
CONTAINERS=("gibsey-cassandra" "gibsey-kafka" "gibsey-zookeeper" "gibsey-debezium" "gibsey-faust-worker" "gibsey-stargate")

for CONTAINER in "${CONTAINERS[@]}"; do
  if docker ps | grep -q "$CONTAINER"; then
    echo -e "${GREEN}✓ $CONTAINER is running${NC}"
  else
    echo -e "${RED}✗ $CONTAINER is not running${NC}"
    ALL_GOOD=false
  fi
done

if [ "$ALL_GOOD" = false ]; then
  echo -e "${YELLOW}Would you like to start the missing containers? (y/n)${NC}"
  read -r START_CONTAINERS
  
  if [[ "$START_CONTAINERS" == "y" || "$START_CONTAINERS" == "Y" ]]; then
    echo "Starting CDC stack..."
    docker compose -f infra/docker-compose.cdc.yml up -d
    check_result "Started CDC stack"
  fi
fi

# Step 2: Check CDC pipeline functionality
section "STEP 2: Testing CDC pipeline"
echo "Running test-cdc-manually.sh to inject a test message..."
./scripts/test-cdc-manually.sh
check_result "CDC pipeline test"

# Step 3: Check database functionality
section "STEP 3: Testing database operations"
echo "Testing Cassandra connection..."
DATABASE_TEST=$(docker exec gibsey-cassandra cqlsh -e "SELECT keyspace_name FROM system_schema.keyspaces WHERE keyspace_name = 'gibsey';" 2>/dev/null)
check_result "Cassandra connection"

# Step 4: Check if we can insert and read data
if [[ ! -z "$DATABASE_TEST" ]]; then
  echo "Inserting test data..."
  TEST_ID="verification-$(date +%s)"
  docker exec gibsey-cassandra cqlsh -e "CREATE TABLE IF NOT EXISTS gibsey.verification_test (id text PRIMARY KEY, data text);"
  docker exec gibsey-cassandra cqlsh -e "INSERT INTO gibsey.verification_test (id, data) VALUES ('$TEST_ID', 'System verification test');"
  
  echo "Reading test data..."
  READ_TEST=$(docker exec gibsey-cassandra cqlsh -e "SELECT * FROM gibsey.verification_test WHERE id='$TEST_ID';" 2>/dev/null)
  
  if [[ "$READ_TEST" == *"$TEST_ID"* ]]; then
    echo -e "${GREEN}✓ Database read/write test successful${NC}"
  else
    echo -e "${RED}✗ Database read/write test failed${NC}"
  fi
else
  echo -e "${RED}Skipping database read/write test due to connection failure${NC}"
fi

# Step 5: Check Debezium status
section "STEP 5: Checking Debezium status"
DEBEZIUM_STATUS=$(curl -s http://localhost:8083/ 2>/dev/null)
if [[ ! -z "$DEBEZIUM_STATUS" ]]; then
  echo -e "${GREEN}✓ Debezium is running${NC}"
  
  # Check connector status
  CONNECTORS=$(curl -s http://localhost:8083/connectors 2>/dev/null)
  if [[ "$CONNECTORS" != "[]" && ! -z "$CONNECTORS" ]]; then
    echo -e "${GREEN}✓ Connectors are registered: $CONNECTORS${NC}"
    
    # Check individual connector status
    for CONNECTOR in $(echo "$CONNECTORS" | tr -d '[]"' | tr ',' '\n'); do
      CONNECTOR_STATUS=$(curl -s http://localhost:8083/connectors/$CONNECTOR/status 2>/dev/null)
      CONNECTOR_STATE=$(echo "$CONNECTOR_STATUS" | grep -o '"state":"[^"]*"' | cut -d'"' -f4)
      
      if [[ "$CONNECTOR_STATE" == "RUNNING" ]]; then
        echo -e "${GREEN}✓ Connector $CONNECTOR is running${NC}"
      else
        echo -e "${RED}✗ Connector $CONNECTOR is not running (State: $CONNECTOR_STATE)${NC}"
      fi
    done
  else
    echo -e "${YELLOW}! No connectors registered with Debezium${NC}"
    echo "Would you like to register the Cassandra connector? (y/n)"
    read -r REGISTER_CONNECTOR
    
    if [[ "$REGISTER_CONNECTOR" == "y" || "$REGISTER_CONNECTOR" == "Y" ]]; then
      if [ -f "infra/connectors/cassandra-connector.json" ]; then
        curl -X POST -H "Content-Type: application/json" -d @infra/connectors/cassandra-connector.json http://localhost:8083/connectors
        check_result "Registered Cassandra connector"
      else
        echo -e "${RED}Connector configuration file not found${NC}"
      fi
    fi
  fi
else
  echo -e "${RED}✗ Debezium is not responding${NC}"
fi

# Step 6: Check Web API
section "STEP 6: Checking Python API"
if pgrep -f "python.*main.py" > /dev/null; then
  echo -e "${GREEN}✓ Python API is running${NC}"
else
  echo -e "${YELLOW}! Python API is not running${NC}"
  echo "Would you like to start the Python API? (y/n)"
  read -r START_API
  
  if [[ "$START_API" == "y" || "$START_API" == "Y" ]]; then
    echo "Starting Python API..."
    nohup python main.py > api.log 2>&1 &
    check_result "Started Python API"
  fi
fi

# Step 7: Summary
section "===== VERIFICATION SUMMARY ====="
echo -e "The following components were tested:"

# Display configuration info
echo -e "\n${YELLOW}${BOLD}Configuration:${NC}"
echo -e "- Running containers: $(docker ps --format '{{.Names}}' | tr '\n' ', ')"
echo -e "- Cassandra keyspaces: $(docker exec gibsey-cassandra cqlsh -e "SELECT keyspace_name FROM system_schema.keyspaces;" | grep -v "keyspace_name" | grep -v "---" | tr -d ' \n' | tr -s ' ' | sed 's/^,//')"
echo -e "- Kafka topics: $(docker exec gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list | tr '\n' ', ')"

# Final message
echo -e "\n${GREEN}${BOLD}Verification complete!${NC}"
echo -e "If any components failed, refer to the documentation for troubleshooting tips."
echo -e "Use ./scripts/diagnose-cdc-issues.sh for more detailed CDC pipeline diagnostics."
echo -e "\nYou can now commit and push your changes to the repository."