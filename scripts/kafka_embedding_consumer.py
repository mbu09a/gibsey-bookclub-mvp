#!/usr/bin/env python3
# Kafka Embedding Consumer
# Connects to Kafka, processes CDC events, embeds page text, and writes vectors to Stargate

import os
import json
import time
import logging
import argparse
import threading
import requests
import numpy as np
from typing import List, Dict, Any, Optional
from urllib.parse import urljoin
from confluent_kafka import Consumer, KafkaError, KafkaException
from dotenv import load_dotenv
from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()

# Parse command line arguments
parser = argparse.ArgumentParser(description='Kafka Embedding Consumer')
parser.add_argument('--no-write', action='store_true', 
                    help='Run in dry-run mode (no writes to Stargate)')
parser.add_argument('--topic', type=str, default='cdc.pages',
                    help='Kafka topic to consume (default: cdc.pages)')
parser.add_argument('--stats-interval', type=int, default=10,
                    help='Log statistics every N successful embeddings')
parser.add_argument('--refresh-memory-rag', action='store_true',
                    help='Notify Memory RAG service about new/updated vectors')
args = parser.parse_args()

# Get configuration from environment
KAFKA_BROKER = os.getenv('KAFKA_BROKER', 'kafka:9092')
STARGATE_URL = os.getenv('STARGATE_URL', 'http://stargate:8080')
OLLAMA_URL = os.getenv('OLLAMA_URL', 'http://ollama:11434')
MEMORY_RAG_URL = os.getenv('MEMORY_RAG_URL', 'http://memory-rag:8001')
EMBED_MODEL = os.getenv('EMBED_MODEL', 'nomic-embed-text')

# Constants
CDC_TOPIC = args.topic
STATS_INTERVAL = args.stats_interval
DRY_RUN = args.no_write
REFRESH_MEMORY_RAG = args.refresh_memory_rag
VECTOR_DIMENSION = 768  # Expected dimension for nomic-embed-text

# Statistics
stats = {
    'processed_count': 0,
    'error_count': 0,
    'embedding_time_ms_avg': 0,
    'start_time': time.time()
}

# Thread lock for stats updates
stats_lock = threading.Lock()


# Retry decorators for network operations
@retry(
    stop=stop_after_attempt(5),
    wait=wait_exponential(multiplier=1, min=1, max=10),
    retry=retry_if_exception_type((requests.exceptions.RequestException, json.JSONDecodeError)),
    reraise=True
)
def generate_embedding(text: str) -> List[float]:
    """
    Generate embedding vector using Ollama API with retries
    
    Args:
        text: The text to embed
        
    Returns:
        List of floats representing the embedding vector
    """
    start_time = time.time()
    
    try:
        url = f"{OLLAMA_URL}/api/embeddings"
        payload = {
            "model": EMBED_MODEL,
            "prompt": text
        }
        
        logger.debug(f"Calling Ollama embedding API for {len(text)} chars of text")
        response = requests.post(url, json=payload, timeout=30)
        response.raise_for_status()
        
        data = response.json()
        embedding = data.get("embedding")
        
        if not embedding:
            logger.error(f"No embedding returned from Ollama: {data}")
            # Return zeros as fallback
            return np.zeros(VECTOR_DIMENSION).tolist()
            
        # Verify dimensions
        if len(embedding) != VECTOR_DIMENSION:
            logger.warning(f"Unexpected embedding dimension: got {len(embedding)}, expected {VECTOR_DIMENSION}")
        
        # Update stats
        elapsed_ms = (time.time() - start_time) * 1000
        with stats_lock:
            stats['embedding_time_ms_avg'] = ((stats['embedding_time_ms_avg'] * stats['processed_count']) + elapsed_ms) / (stats['processed_count'] + 1)
        
        logger.debug(f"Generated embedding of dimension {len(embedding)} in {elapsed_ms:.2f}ms")
        return embedding
        
    except Exception as e:
        logger.error(f"Error generating embedding: {str(e)}")
        # Reraise to trigger retry
        raise


@retry(
    stop=stop_after_attempt(5),
    wait=wait_exponential(multiplier=1, min=1, max=10),
    retry=retry_if_exception_type(requests.exceptions.RequestException),
    reraise=True
)
def store_vector_in_stargate(page_id: str, vector: List[float]) -> bool:
    """
    Store vector in Stargate via REST API with retries
    
    Args:
        page_id: The unique ID of the page
        vector: The embedding vector to store
        
    Returns:
        True if successful, False otherwise
    """
    if DRY_RUN:
        logger.info(f"[DRY RUN] Would store vector for page_id: {page_id}")
        return True
        
    try:
        # Construct the URL for the page_vectors table
        url = f"{STARGATE_URL}/v2/keyspaces/gibsey/page_vectors/{page_id}"
        
        # Prepare the payload
        payload = {
            "vector": vector
        }
        
        # Make the PUT request
        response = requests.put(url, json=payload, timeout=10)
        response.raise_for_status()
        
        logger.debug(f"Successfully stored vector for page_id: {page_id}")
        return True
        
    except Exception as e:
        logger.error(f"Error storing vector in Stargate: {str(e)}")
        # Reraise to trigger retry
        raise


@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=1, max=5),
    retry=retry_if_exception_type(requests.exceptions.RequestException)
)
def notify_memory_rag(page_id: str, vector: List[float]) -> bool:
    """
    Notify Memory RAG service about new/updated vector with retries
    
    Args:
        page_id: The unique ID of the page
        vector: The embedding vector
        
    Returns:
        True if successful, False otherwise
    """
    if not REFRESH_MEMORY_RAG or DRY_RUN:
        return True
        
    try:
        url = f"{MEMORY_RAG_URL}/refresh"
        payload = {
            "page_id": page_id,
            "vector": vector
        }
        
        response = requests.post(url, json=payload, timeout=5)
        response.raise_for_status()
        
        logger.debug(f"Successfully notified Memory RAG for page_id: {page_id}")
        return True
        
    except Exception as e:
        logger.error(f"Error notifying Memory RAG: {str(e)}")
        return False  # Don't raise exception, this is optional


def log_stats():
    """Log current processing statistics"""
    with stats_lock:
        elapsed = time.time() - stats['start_time']
        rate = stats['processed_count'] / elapsed if elapsed > 0 else 0
        
        logger.info(f"Stats: processed={stats['processed_count']}, "
                   f"errors={stats['error_count']}, "
                   f"rate={rate:.2f}/s, "
                   f"avg_embedding_time={stats['embedding_time_ms_avg']:.2f}ms")


def process_message(msg):
    """
    Process a CDC message from Kafka
    
    Args:
        msg: The Kafka message
    """
    try:
        # Extract value
        value = msg.value().decode('utf-8')
        
        # Parse JSON
        data = json.loads(value)
        
        # Extract payload
        payload = data.get('payload', {})
        operation = payload.get('op')  # 'c' (create), 'u' (update), 'd' (delete), 'r' (read)
        
        # We only care about creates and updates
        if operation not in ['c', 'u']:
            logger.debug(f"Ignoring operation type: {operation}")
            return
            
        # Use after data for create/update operations
        after_data = payload.get('after')
        if not after_data:
            logger.warning("Event payload missing 'after' data for create/update operation")
            return
            
        # Extract page_id and body
        page_id = after_data.get('page_id')
        body = after_data.get('body')
        
        if not page_id or not body:
            logger.warning(f"Missing required fields. page_id: {page_id}, body length: {len(body) if body else 0}")
            return
            
        logger.info(f"Processing page_id: {page_id}, operation: {operation}, body length: {len(body)}")
        
        # Generate embedding for the body text
        vector = generate_embedding(body)
        
        # Store the vector in Stargate
        if store_vector_in_stargate(page_id, vector):
            # Update stats
            with stats_lock:
                stats['processed_count'] += 1
                processed_count = stats['processed_count']
                
            # Notify Memory RAG service (optional)
            notify_memory_rag(page_id, vector)
            
            # Log stats at intervals
            if processed_count % STATS_INTERVAL == 0:
                log_stats()
        
    except json.JSONDecodeError:
        logger.error(f"Failed to parse message as JSON")
        with stats_lock:
            stats['error_count'] += 1
    except Exception as e:
        logger.error(f"Error processing message: {str(e)}")
        with stats_lock:
            stats['error_count'] += 1


def start_consumer_daemon():
    """Start the consumer in a daemon thread for cleaner shutdown"""
    thread = threading.Thread(target=consume_forever, daemon=True)
    thread.start()
    return thread


def consume_forever():
    """Consume messages in an infinite loop, handling reconnection"""
    while True:
        try:
            run_consumer()
        except Exception as e:
            logger.error(f"Consumer error: {str(e)}")
            logger.info("Restarting consumer in 5 seconds...")
            time.sleep(5)


def run_consumer():
    """Run the main consumer logic with proper error handling"""
    logger.info(f"Starting CDC Kafka consumer for topic: {CDC_TOPIC}")
    if DRY_RUN:
        logger.info("Running in DRY RUN mode - no writes will be performed")
    
    # Configure the consumer
    config = {
        'bootstrap.servers': KAFKA_BROKER,
        'group.id': 'gibsey-embedding-consumer',
        'auto.offset.reset': 'earliest',
        'enable.auto.commit': False,
        'session.timeout.ms': 30000,
        'max.poll.interval.ms': 300000,  # Allow up to 5 minutes processing time
    }
    
    # Create consumer
    consumer = Consumer(config)
    
    try:
        # Subscribe to the CDC topic
        consumer.subscribe([CDC_TOPIC])
        logger.info(f"Subscribed to topic: {CDC_TOPIC}")
        
        # Main processing loop
        while True:
            # Poll for messages
            msg = consumer.poll(timeout=1.0)
            
            if msg is None:
                continue
                
            if msg.error():
                if msg.error().code() == KafkaError._PARTITION_EOF:
                    # End of partition event - not an error
                    logger.debug(f"Reached end of partition {msg.partition()}")
                elif msg.error().code() == KafkaError._UNKNOWN_TOPIC_OR_PART:
                    logger.warning(f"Unknown topic or partition")
                else:
                    logger.error(f"Kafka error: {msg.error()}")
            else:
                # Process the message
                logger.debug(f"Received message from topic {msg.topic()}")
                process_message(msg)
                
                # Commit after processing
                consumer.commit(msg)
            
            # Sleep briefly to reduce CPU usage in tight loops
            time.sleep(0.01)
                
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        raise  # Re-raise to trigger reconnection
    finally:
        # Clean up on exit
        logger.info("Closing consumer")
        consumer.close()


def main():
    """Main entry point"""
    logger.info(f"Kafka Embedding Consumer starting up")
    logger.info(f"Configuration:")
    logger.info(f"  Kafka Broker: {KAFKA_BROKER}")
    logger.info(f"  Stargate URL: {STARGATE_URL}")
    logger.info(f"  Ollama URL: {OLLAMA_URL}")
    logger.info(f"  Topic: {CDC_TOPIC}")
    logger.info(f"  Embedding Model: {EMBED_MODEL}")
    logger.info(f"  Dry Run: {DRY_RUN}")
    
    # Reset stats
    with stats_lock:
        stats['start_time'] = time.time()
        stats['processed_count'] = 0
        stats['error_count'] = 0
        stats['embedding_time_ms_avg'] = 0
    
    # Start the consumer in a daemon thread
    consumer_thread = start_consumer_daemon()
    
    try:
        # Keep the main thread running
        while True:
            time.sleep(10)
            # Log stats periodically from main thread too
            log_stats()
            
    except KeyboardInterrupt:
        logger.info("Shutting down Kafka Embedding Consumer...")
        # Thread will terminate automatically since it's a daemon


if __name__ == "__main__":
    main()