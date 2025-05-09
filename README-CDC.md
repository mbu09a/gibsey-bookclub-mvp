# CDC Pipeline for Gibsey Bookclub MVP

This document explains the Change Data Capture (CDC) pipeline implementation for the Gibsey Bookclub MVP project.

## Overview

The CDC pipeline captures changes to Cassandra database tables and processes them through Kafka for real-time updates to search indices and other downstream systems.

## Architecture

The pipeline consists of:

1. **Cassandra**: Database with CDC-enabled tables
2. **Debezium**: Captures changes from Cassandra and publishes to Kafka
3. **Kafka**: Message broker that streams CDC events
4. **Simple Kafka Consumer**: Processes CDC events (replaces Faust due to Python 3.11 compatibility)

## Getting Started

### 1. Start the CDC Stack

```bash
# Start all services
docker compose -f infra/docker-compose.cdc.yml up -d
```

### 2. Create CDC-Enabled Tables

```bash
# Create keyspace and table with CDC enabled
docker exec gibsey-cassandra cqlsh -e "CREATE KEYSPACE IF NOT EXISTS gibsey WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};"
docker exec gibsey-cassandra cqlsh -e "CREATE TABLE IF NOT EXISTS gibsey.test_cdc (id text PRIMARY KEY, data text) WITH cdc = true;"
```

### 3. Register the Connector

```bash
# Register the Cassandra connector with Debezium
curl -X POST -H "Content-Type: application/json" -d @infra/connectors/cassandra-connector.json http://localhost:8083/connectors
```

### 4. Insert Test Data

```bash
# Insert data to trigger CDC
docker exec gibsey-cassandra cqlsh -e "INSERT INTO gibsey.test_cdc (id, data) VALUES ('test-1', 'Test CDC data');"
```

### 5. Verify the Pipeline

```bash
# Run verification script
./verify-operation.sh
```

## Troubleshooting

If you encounter issues with the CDC pipeline, try these steps:

### Check Service Status

```bash
docker ps | grep gibsey
```

### Check Debezium Connector Status

```bash
curl -s http://localhost:8083/connectors/cassandra-connector/status | jq
```

### Check Kafka Topics

```bash
docker exec gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list
```

### View Consumer Logs

```bash
docker logs gibsey-faust-worker
```

### Manually Test the Pipeline

```bash
./scripts/test-cdc-manually.sh
```

## Mock Connector Alternative

If the Cassandra connector doesn't work, you can use the mock connector:

```bash
# Delete existing connector
curl -X DELETE http://localhost:8083/connectors/cassandra-connector

# Register mock connector
curl -X POST -H "Content-Type: application/json" -d @infra/connectors/mock-connector.json http://localhost:8083/connectors
```

## Implementation Notes

### Python 3.11 Compatibility

Due to compatibility issues between Faust and Python 3.11, we've implemented a simpler Kafka consumer using the confluent-kafka library.

### Using Regular Faust (If Using Python 3.8-3.10)

If using Python 3.8-3.10, you can revert to using Faust:

1. Update requirements.txt:
   ```
   faust>=1.10.4
   ```

2. Replace simple_consumer.py with app.py that uses Faust

### Connector Configuration

The connector requires specifying the correct `connector.class`:

- For Cassandra 4.x: `"connector.class": "io.debezium.connector.cassandra.Cassandra4Connector"`
- For older versions: `"connector.class": "io.debezium.connector.cassandra.CassandraConnector"`

## Next Steps

1. Implement actual embedding generation in the consumer
2. Configure the connector to capture changes from the pages table
3. Update the FAISS index when page content changes

## References

- [Debezium Cassandra Connector](https://debezium.io/documentation/reference/connectors/cassandra.html)
- [Confluent Kafka Python Client](https://docs.confluent.io/platform/current/clients/confluent-kafka-python/html/index.html)