#!/bin/bash

# Insert new data
echo "Inserting new data into test_cdc table..."
docker exec -it gibsey-cassandra cqlsh -e "INSERT INTO gibsey.test_cdc (id, data) VALUES ('test-$(date +%s)', 'New CDC data $(date)');"

# Wait a moment for processing
sleep 5

# Check Kafka topics
echo "Checking Kafka topics..."
docker exec gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list | grep gibsey

# Look for our data in the topic
echo "Checking for events in the topic..."
docker exec gibsey-kafka kafka-console-consumer --bootstrap-server kafka:9092 --topic gibsey.gibsey.test_cdc --from-beginning --max-messages 10 