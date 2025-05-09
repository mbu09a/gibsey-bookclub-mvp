#!/usr/bin/env python3
# A simple Kafka consumer to replace the Faust worker with Python 3.11 compatibility issues

import os
import json
import time
import logging
import re
import threading
from dotenv import load_dotenv
from confluent_kafka import Consumer, KafkaError, KafkaException

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()

# Get configuration from environment
KAFKA_BROKER = os.getenv('KAFKA_BROKER')
STARGATE_URL = os.getenv('STARGATE_URL')

if not KAFKA_BROKER:
    logger.error("KAFKA_BROKER not set in environment")
    exit(1)
else:
    logger.info(f"Using Kafka broker: {KAFKA_BROKER}")

if not STARGATE_URL:
    logger.warning("STARGATE_URL not set - vectorized operations will be unavailable")
else:
    logger.info(f"Using Stargate URL: {STARGATE_URL}")

# Define the CDC topics to subscribe to
CDC_TOPIC_PATTERN = r'gibsey\.gibsey\.(pages|vault|ledger|test_cdc)'

def process_message(msg):
    """Process a CDC message from Kafka"""
    try:
        # Extract topic and value
        topic = msg.topic()
        value = msg.value().decode('utf-8')
        
        # Parse JSON
        data = json.loads(value)
        
        # Extract payload
        payload = data.get('payload', {})
        operation = payload.get('op')  # 'c' (create), 'u' (update), 'd' (delete), 'r' (read)
        after_data = payload.get('after')
        before_data = payload.get('before')
        
        # Use after data for inserts/updates, before data for deletes
        data = after_data or before_data
        
        if not data:
            logger.warning("Event payload missing data")
            return
            
        # Extract table name from topic
        table_name = topic.split('.')[-1]
        
        logger.info(f"Operation: {operation}, Table: {table_name}, Data: {data}")
        
        # Process based on table
        if table_name == 'pages':
            logger.info("TODO: Process page change - update embeddings/index")
            # Here you would:
            # 1. Extract page text/content
            # 2. Generate embedding (call Ollama or other service)
            # 3. Update FAISS index
        elif table_name == 'vault':
            logger.info("TODO: Process vault change")
            # Update user stats or notifications
        elif table_name == 'ledger':
            logger.info("TODO: Process ledger change")
            # Update user credit cache
        elif table_name == 'test_cdc':
            logger.info("Processing test CDC event")
            # Log the successful processing of test data
            
    except json.JSONDecodeError:
        logger.error(f"Failed to parse message as JSON: {value}")
    except Exception as e:
        logger.error(f"Error processing message: {str(e)}")

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
    logger.info("Starting CDC Kafka consumer")
    
    # Configure the consumer
    config = {
        'bootstrap.servers': KAFKA_BROKER,
        'group.id': 'gibsey-cdc-consumer',
        'auto.offset.reset': 'earliest',
        'enable.auto.commit': True,
        'session.timeout.ms': 30000,
        'max.poll.interval.ms': 300000,  # Allow up to 5 minutes processing time
    }
    
    # Create consumer
    consumer = Consumer(config)
    
    try:
        # Get metadata about existing topics
        metadata = consumer.list_topics(timeout=10)
        all_topics = list(metadata.topics.keys())
        
        # Filter topics using our pattern
        pattern = re.compile(CDC_TOPIC_PATTERN)
        cdc_topics = [topic for topic in all_topics if pattern.match(topic)]
        
        if not cdc_topics:
            logger.warning(f"No existing topics match pattern: {CDC_TOPIC_PATTERN}")
            logger.info(f"Available topics: {', '.join(all_topics) if all_topics else 'None'}")
            # Use regex subscription for topics that may be created later
            logger.info("Subscribing to topic pattern for future topics")
            consumer.subscribe(['^gibsey\.gibsey\.(pages|vault|ledger|test_cdc)'], 
                             on_assign=lambda c, ps: logger.info(f"Assigned partitions: {ps}"))
        else:
            logger.info(f"Found CDC topics: {cdc_topics}")
            consumer.subscribe(cdc_topics, 
                             on_assign=lambda c, ps: logger.info(f"Assigned partitions: {ps}"))
        
        # Log that we're ready to receive messages
        logger.info(f"Waiting for messages from CDC topics...")
        
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
                logger.info(f"Received message from topic {msg.topic()}")
                process_message(msg)
            
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
    logger.info("CDC Consumer starting up")
    logger.info(f"Monitoring topics matching pattern: {CDC_TOPIC_PATTERN}")
    
    # Start the consumer in a daemon thread
    consumer_thread = start_consumer_daemon()
    
    try:
        # Keep the main thread running
        while True:
            time.sleep(1)
            
    except KeyboardInterrupt:
        logger.info("Shutting down CDC Consumer...")
        # Thread will terminate automatically since it's a daemon

if __name__ == "__main__":
    main()