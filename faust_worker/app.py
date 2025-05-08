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
cdc_topic_pattern = app.topic(pattern='gibsey\.gibsey\.(pages|vault|ledger)')

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

if __name__ == "__main__":
    app.main()