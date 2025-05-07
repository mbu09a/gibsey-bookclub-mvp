import faust
import json
import os
import logging
import requests
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
)
logger = logging.getLogger("gibsey-faust-worker")

# Get environment variables
KAFKA_BROKER = os.getenv("KAFKA_BROKER", "kafka:9092")
STARGATE_URL = os.getenv("STARGATE_URL", "http://stargate:8082")
STARGATE_AUTH_TOKEN = os.getenv("STARGATE_AUTH_TOKEN")

# Define the Faust app
app = faust.App(
    'gibsey-faust-worker',
    broker=f'kafka://{KAFKA_BROKER}',
    value_serializer='raw',
)

# Define topics
# Topics will be created when Debezium is configured with a connector
page_changes_topic = app.topic('gibsey.public.pages')
question_changes_topic = app.topic('gibsey.public.questions')
answer_changes_topic = app.topic('gibsey.public.answers')

# Define models for records
class PageRecord(faust.Record):
    id: str
    title: str
    content: str
    section: str
    
class QuestionRecord(faust.Record):
    id: str
    user_id: str
    question: str
    timestamp: str
    
class AnswerRecord(faust.Record):
    id: str
    question_id: str
    content: str
    timestamp: str
    citations: list

# Agent to process page changes
@app.agent(page_changes_topic)
async def process_page_changes(stream):
    """Process changes to pages from Cassandra CDC via Kafka."""
    async for message in stream:
        try:
            # Parse the CDC event
            event = json.loads(message)
            logger.info(f"Received page change event: {event}")
            
            # TODO: Generate embeddings for the page content
            # TODO: Update vector index with new embeddings
            # TODO: Log to audit trail
            
            logger.info(f"Processed page change for ID: {event.get('after', {}).get('id')}")
        except Exception as e:
            logger.error(f"Error processing page change: {e}")

# Agent to process question changes
@app.agent(question_changes_topic)
async def process_question_changes(stream):
    """Process changes to questions from Cassandra CDC via Kafka."""
    async for message in stream:
        try:
            # Parse the CDC event
            event = json.loads(message)
            logger.info(f"Received question change event: {event}")
            
            # TODO: Generate embeddings for the question
            # TODO: Update relevant statistics
            # TODO: Log to audit trail
            
            logger.info(f"Processed question change for ID: {event.get('after', {}).get('id')}")
        except Exception as e:
            logger.error(f"Error processing question change: {e}")

# Agent to process answer changes
@app.agent(answer_changes_topic)
async def process_answer_changes(stream):
    """Process changes to answers from Cassandra CDC via Kafka."""
    async for message in stream:
        try:
            # Parse the CDC event
            event = json.loads(message)
            logger.info(f"Received answer change event: {event}")
            
            # TODO: Update answer statistics
            # TODO: Update user credit balance if applicable
            # TODO: Log to audit trail
            
            logger.info(f"Processed answer change for ID: {event.get('after', {}).get('id')}")
        except Exception as e:
            logger.error(f"Error processing answer change: {e}")

# Utility function to check Stargate connection
@app.task
async def check_stargate_connection():
    """Check connection to Stargate API on startup."""
    try:
        headers = {
            "X-Cassandra-Token": STARGATE_AUTH_TOKEN,
            "Content-Type": "application/json"
        }
        response = requests.get(f"{STARGATE_URL}/health", headers=headers)
        if response.status_code == 200:
            logger.info("Successfully connected to Stargate API")
        else:
            logger.warning(f"Could not connect to Stargate API: {response.status_code}")
    except Exception as e:
        logger.error(f"Error connecting to Stargate API: {e}")

# Startup tasks
@app.on_configured.connect
async def on_configured(app, **kwargs):
    logger.info("Faust worker configured and starting up...")

if __name__ == "__main__":
    app.main()