#!/usr/bin/env python3
"""
Script to set up Debezium connector for Cassandra CDC.
Run this after the Cassandra, Kafka, and Debezium services are up.
"""

import requests
import json
import time
import logging
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
)
logger = logging.getLogger("setup-debezium")

# Debezium Connect REST API endpoint
DEBEZIUM_CONNECT_URL = "http://localhost:8083/connectors"

def wait_for_debezium():
    """Wait for Debezium Connect service to be ready."""
    max_attempts = 30
    attempt = 0
    
    while attempt < max_attempts:
        try:
            response = requests.get(DEBEZIUM_CONNECT_URL)
            if response.status_code == 200:
                logger.info("Debezium Connect is ready")
                return True
        except requests.exceptions.ConnectionError:
            pass
        
        attempt += 1
        logger.info(f"Waiting for Debezium Connect... Attempt {attempt}/{max_attempts}")
        time.sleep(5)
    
    logger.error("Debezium Connect did not become ready in time")
    return False

def create_connector():
    """Create Cassandra CDC connector."""
    # Connector configuration
    connector_config = {
        "name": "gibsey-cassandra-connector",
        "config": {
            "connector.class": "io.debezium.connector.cassandra.CassandraConnector",
            "cassandra.hosts": "cassandra",
            "cassandra.port": "9042",
            "cassandra.username": "cassandra",
            "cassandra.password": "cassandra",
            "cassandra.keyspace": "gibsey",
            "topic.prefix": "gibsey",
            "schema.history.internal.kafka.bootstrap.servers": "kafka:9092",
            "schema.history.internal.kafka.topic": "schema-changes.gibsey",
            "snapshot.mode": "initial",
            "key.converter": "org.apache.kafka.connect.json.JsonConverter",
            "value.converter": "org.apache.kafka.connect.json.JsonConverter",
            "transforms": "unwrap",
            "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
            "transforms.unwrap.drop.tombstones": "false",
            "tombstones.on.delete": "true"
        }
    }
    
    # Create connector
    response = requests.post(
        DEBEZIUM_CONNECT_URL,
        headers={"Content-Type": "application/json"},
        data=json.dumps(connector_config)
    )
    
    if response.status_code in [201, 200]:
        logger.info("Successfully created Debezium connector for Cassandra")
        return True
    else:
        logger.error(f"Failed to create connector: {response.status_code}, {response.text}")
        return False

def main():
    """Main function to set up Debezium connector."""
    if wait_for_debezium():
        create_connector()
    else:
        logger.error("Could not set up Debezium connector")

if __name__ == "__main__":
    main()