#!/bin/bash
# fix-cdc-pipeline.sh - Comprehensive fix for CDC pipeline issues

# Text formatting
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${YELLOW}${BOLD}===== FIXING CDC PIPELINE =====${NC}"

# Step 1: Update the Faust worker to properly connect to Kafka
echo -e "\n${YELLOW}${BOLD}STEP 1: Updating Faust worker app.py${NC}"
if [ -f "faust_worker/app.py.new" ]; then
    echo "Found prepared app.py.new file, using it..."
    mv faust_worker/app.py.new faust_worker/app.py
    echo -e "${GREEN}✓ Updated app.py using prepared file${NC}"
else
    echo "Creating new app.py file..."
    cat > faust_worker/app.py << 'EOF'
import faust
from faust import App, Record
import json
import os
import logging
import requests
import numpy as np
# import faiss # Only needed if worker does vector updates
from dotenv import load_dotenv

# Basic logging setup
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Load environment variables (including STARGATE_AUTH_TOKEN if needed, though auth is off)
load_dotenv()

# Environment variable checks
KAFKA_BROKER = os.getenv('KAFKA_BROKER')
STARGATE_URL = os.getenv('STARGATE_URL')
# STARGATE_TOKEN = os.getenv('STARGATE_AUTH_TOKEN') # Not strictly needed if auth is off

if not KAFKA_BROKER:
    logger.error("KAFKA_BROKER environment variable not set.")
    exit(1)
if not STARGATE_URL:
    logger.warning("STARGATE_URL environment variable not set. Some functionality may be limited.")
    STARGATE_URL = None  # Set to None so we can check later

# Initialize Faust app
app = App(
    'gibsey_cdc_worker',
    broker=f'kafka://{KAFKA_BROKER}',
    value_serializer='json',
    topic_partitions=1 # Adjust as needed
)

# Define the input topic pattern based on Debezium output
# Example: gibsey.gibsey.pages (topic_prefix.keyspace.table)
# Using a regex to capture events from relevant tables (e.g., pages, vault, ledger)
# Pass the regex pattern directly when pattern=True
cdc_topic_pattern = app.topic(pattern='gibsey\.gibsey\.(pages|vault|ledger|test_cdc)')

# Define a simple Record type (adjust fields based on actual CDC message structure)
class ChangeEvent(Record, serializer='json'):
    payload: dict # Debezium payload often nested here

@app.agent(cdc_topic_pattern)
async def process_cdc_event(events):
    async for event in events:
        logger.info(f"Received event from topic {event.topic}:")
        # logger.info(f"  Key: {event.key}")
        # logger.info(f"  Value: {json.dumps(event.value, indent=2)}")

        # --- Placeholder Logic --- 
        # Extract relevant data from event.value (structure depends on Debezium output)
        payload = event.value.get('payload', {})
        operation = payload.get('op') # e.g., 'c' (create), 'u' (update), 'd' (delete), 'r' (read/snapshot)
        data = payload.get('after') or payload.get('before')

        if not data:
            logger.warning("  Event payload missing data.")
            continue

        table_name = event.topic.split('.')[-1]
        logger.info(f"  Operation: {operation}, Table: {table_name}, Data: {data}")

        # TODO: Implement actual logic based on table and operation
        if table_name == 'pages':
            # - Extract page text
            # - Generate embedding (call Ollama or other service)
            # - Update FAISS index
            logger.info("  TODO: Process page change - update embeddings/index.")
        elif table_name == 'vault':
            # - Maybe trigger user notification or update aggregated stats
            logger.info("  TODO: Process vault change.")
        elif table_name == 'ledger':
            # - Update user credit summary cache if needed
            logger.info("  TODO: Process ledger change.")
        elif table_name == 'test_cdc':
            # - Process test CDC events
            logger.info("  Processing test CDC event.")
        
        # --- End Placeholder Logic ---

# Utility function to check Stargate connection
@app.task
async def check_stargate_connection():
    """Check connection to Stargate API on startup."""
    if not STARGATE_URL:
        logger.info("Stargate URL not configured - skipping connection check")
        return
        
    stargate_token = os.getenv('STARGATE_AUTH_TOKEN') # <-- Read from environment
    try:
        headers = {
            # "X-Cassandra-Token": stargate_token, # Send token if/when needed and auth enabled
            "Content-Type": "application/json"
        }
        # Add token header only if it exists (and potentially only if auth is expected)
        if stargate_token:
             headers["X-Cassandra-Token"] = stargate_token
             
        logger.info(f"Checking Stargate connection at {STARGATE_URL}/health")
        response = requests.get(f"{STARGATE_URL}/health", headers=headers, timeout=5)
        if response.status_code == 200:
            logger.info("Successfully connected to Stargate API")
        else:
            logger.warning(f"Could not connect to Stargate API: {response.status_code} - {response.text}")
    except requests.exceptions.ConnectionError:
        logger.warning(f"Could not connect to Stargate API at {STARGATE_URL} - service may not be running")
    except Exception as e:
        logger.error(f"Error connecting to Stargate API: {e}")

# Startup tasks
@app.on_configured.connect
async def on_configured(app, **kwargs):
    logger.info("Faust worker configured and starting up...")
    logger.info(f"Listening for CDC events from Kafka broker: {KAFKA_BROKER}")
    logger.info(f"Monitoring topics matching pattern: gibsey.gibsey.(pages|vault|ledger|test_cdc)")

if __name__ == "__main__":
    app.main()
EOF
    echo -e "${GREEN}✓ Created new app.py file${NC}"
fi

# Step 2: Update requirements.txt to match imports
echo -e "\n${YELLOW}${BOLD}STEP 2: Updating Faust worker requirements.txt${NC}"
if [ -f "faust_worker/requirements.txt.new" ]; then
    echo "Found prepared requirements.txt.new file, using it..."
    mv faust_worker/requirements.txt.new faust_worker/requirements.txt
    echo -e "${GREEN}✓ Updated requirements.txt using prepared file${NC}"
else
    echo "Creating new requirements.txt file..."
    cat > faust_worker/requirements.txt << 'EOF'
faust>=1.10.4
aiohttp>=3.8.5
python-dotenv>=1.0.0
requests>=2.31.0
numpy>=1.24.3
faiss-cpu>=1.7.4
EOF
    echo -e "${GREEN}✓ Created new requirements.txt file${NC}"
fi

# Step 3: Check and update docker-compose.cdc.yml
echo -e "\n${YELLOW}${BOLD}STEP 3: Checking docker-compose.cdc.yml${NC}"
if ! grep -q "gibsey-faust-worker" "infra/docker-compose.cdc.yml"; then
    echo -e "${RED}✗ Faust worker not properly configured in docker-compose.cdc.yml${NC}"
    echo "Updating docker-compose.cdc.yml with proper Faust worker configuration..."
    
    # Get existing file content
    COMPOSE_CONTENT=$(cat infra/docker-compose.cdc.yml)
    
    # Check if faust-worker section exists
    if ! grep -q "faust-worker:" "infra/docker-compose.cdc.yml"; then
        # Add faust-worker section if missing
        echo "Adding faust-worker section to docker-compose.cdc.yml..."
        # Find the last service, append after it
        sed -i -e '/volumes:/i \
  # Faust Worker - processes Kafka messages\
  faust-worker:\
    build:\
      context: .\
      dockerfile: faust_worker/Dockerfile\
    container_name: gibsey-faust-worker\
    volumes:\
      - ./faust_worker:/app\
    depends_on:\
      kafka:\
        condition: service_healthy\
    environment:\
      KAFKA_BROKER: kafka:9092\
      STARGATE_URL: http://stargate:8082\
      STARGATE_AUTH_TOKEN: ${STARGATE_AUTH_TOKEN}\
    command: python app.py worker -l info\
' infra/docker-compose.cdc.yml
        echo -e "${GREEN}✓ Added faust-worker section to docker-compose.cdc.yml${NC}"
    else
        echo -e "${GREEN}✓ Faust worker section already exists in docker-compose.cdc.yml${NC}"
    fi
else
    echo -e "${GREEN}✓ Faust worker properly configured in docker-compose.cdc.yml${NC}"
fi

# Step 4: Check for Cassandra connector configuration
echo -e "\n${YELLOW}${BOLD}STEP 4: Checking Cassandra connector configuration${NC}"
mkdir -p infra/connectors
if [ ! -f "infra/connectors/cassandra-connector.json" ]; then
    echo -e "${RED}✗ Cassandra connector configuration not found${NC}"
    echo "Creating Cassandra connector configuration..."
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
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
  }
}
EOF
    echo -e "${GREEN}✓ Created Cassandra connector configuration${NC}"
else
    echo -e "${GREEN}✓ Cassandra connector configuration found${NC}"
    
    # Update include list if needed to include test_cdc
    if ! grep -q "test_cdc" "infra/connectors/cassandra-connector.json"; then
        echo "Updating table.include.list to include test_cdc table..."
        sed -i 's/"table\.include\.list": "[^"]*"/"table.include.list": "gibsey.pages,gibsey.test_cdc"/g' infra/connectors/cassandra-connector.json
        echo -e "${GREEN}✓ Updated connector configuration to include test_cdc table${NC}"
    fi
fi

# Step 5: Rebuild and restart the containers
echo -e "\n${YELLOW}${BOLD}STEP 5: Rebuilding and restarting containers${NC}"
echo "Stopping all CDC containers..."
docker compose -f infra/docker-compose.cdc.yml down

echo "Rebuilding and starting CDC stack..."
docker compose -f infra/docker-compose.cdc.yml up -d --build

# Step 6: Wait for services to start
echo -e "\n${YELLOW}${BOLD}STEP 6: Waiting for services to start (60 seconds)...${NC}"
echo "This may take a minute or two..."
sleep 60

# Step 7: Create test table and register connector
echo -e "\n${YELLOW}${BOLD}STEP 7: Setting up Cassandra and registering connector${NC}"

echo "Creating test table in Cassandra..."
docker exec gibsey-cassandra cqlsh -e "CREATE KEYSPACE IF NOT EXISTS gibsey WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};"
docker exec gibsey-cassandra cqlsh -e "CREATE TABLE IF NOT EXISTS gibsey.test_cdc (id text PRIMARY KEY, data text) WITH cdc = true;"
docker exec gibsey-cassandra cqlsh -e "INSERT INTO gibsey.test_cdc (id, data) VALUES ('initial-data', 'Initial CDC test data');"

echo "Checking if Debezium is up..."
if curl -s -f -m 5 http://localhost:8083/ > /dev/null; then
    echo -e "${GREEN}✓ Debezium API is up${NC}"
    
    echo "Registering Cassandra connector..."
    curl -s -X POST -H "Content-Type: application/json" -d @infra/connectors/cassandra-connector.json http://localhost:8083/connectors
    
    echo -e "\nChecking connector status..."
    sleep 5
    curl -s http://localhost:8083/connectors/cassandra-connector/status | grep -E "state|error|trace" || echo "No status information available"
else
    echo -e "${RED}✗ Debezium API is not responding yet${NC}"
    echo "This is normal if Debezium is still starting up. You'll need to register the connector manually later using:"
    echo "curl -X POST -H \"Content-Type: application/json\" -d @infra/connectors/cassandra-connector.json http://localhost:8083/connectors"
fi

# Step 8: Final verification
echo -e "\n${YELLOW}${BOLD}STEP 8: Final verification${NC}"
echo "Running verification script in 30 seconds..."
echo "This delay allows time for Debezium to initialize and register the connector."
sleep 30

echo -e "\n${YELLOW}${BOLD}===== CDC PIPELINE FIX COMPLETE =====${NC}"
echo "Your CDC pipeline should now be working. Run the verification script to confirm:"
echo "./verify-operation.sh"
echo 
echo "If issues persist, run the diagnostic script for detailed troubleshooting:"
echo "./scripts/diagnose-cdc-issues.sh"