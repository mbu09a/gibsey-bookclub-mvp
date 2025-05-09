#!/bin/bash
# test-cdc-manually.sh - Script to test the CDC pipeline by manually injecting messages

# Text formatting for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${YELLOW}${BOLD}===== MANUAL CDC PIPELINE TEST =====${NC}"

# Step 1: Create the topic if it doesn't exist
echo -e "\n${YELLOW}${BOLD}STEP 1: Creating CDC topic if it doesn't exist${NC}"
CDC_TOPIC="gibsey.gibsey.test_cdc"
TOPIC_EXISTS=$(docker exec gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --list | grep "$CDC_TOPIC")

if [ -z "$TOPIC_EXISTS" ]; then
    echo "Creating CDC topic: $CDC_TOPIC"
    docker exec gibsey-kafka kafka-topics --bootstrap-server kafka:9092 --create --topic $CDC_TOPIC --partitions 1 --replication-factor 1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Topic created successfully${NC}"
    else
        echo -e "${RED}✗ Failed to create topic${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ CDC topic already exists: $CDC_TOPIC${NC}"
fi

# Step 2: Generate test CDC messages
echo -e "\n${YELLOW}${BOLD}STEP 2: Generating test CDC messages${NC}"

# Generate timestamp for unique ID
TIMESTAMP=$(date +%s)

# Create a test message
echo "Creating test message with ID: test-$TIMESTAMP"
TEST_MESSAGE="{\"payload\": {\"op\": \"c\", \"after\": {\"id\": \"test-$TIMESTAMP\", \"data\": \"Test CDC data generated at $(date)\"}}}"
echo "Message content:"
echo "$TEST_MESSAGE" | jq .

# Step 3: Publish message to Kafka
echo -e "\n${YELLOW}${BOLD}STEP 3: Publishing message to Kafka${NC}"
echo "Publishing to topic: $CDC_TOPIC"
echo "$TEST_MESSAGE" > /tmp/cdc-test-message.json
cat /tmp/cdc-test-message.json | docker exec -i gibsey-kafka kafka-console-producer --bootstrap-server kafka:9092 --topic $CDC_TOPIC
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Message published successfully${NC}"
else
    echo -e "${RED}✗ Failed to publish message${NC}"
    exit 1
fi

# Step 4: Check for the message in the topic
echo -e "\n${YELLOW}${BOLD}STEP 4: Verifying message in topic${NC}"
echo "Waiting 5 seconds for message to be processed..."
sleep 5
echo "Looking for messages in topic $CDC_TOPIC..."
MESSAGES=$(docker exec gibsey-kafka kafka-console-consumer --bootstrap-server kafka:9092 --topic $CDC_TOPIC --from-beginning --max-messages 1 --timeout-ms 5000)
if [ -z "$MESSAGES" ]; then
    echo -e "${RED}✗ No messages found in topic${NC}"
else
    echo -e "${GREEN}✓ Found messages in topic:${NC}"
    echo "$MESSAGES" | jq .
fi

# Step 5: Check if the consumer received the message
echo -e "\n${YELLOW}${BOLD}STEP 5: Checking if CDC consumer received the message${NC}"
echo "Checking logs of gibsey-faust-worker container..."
CONSUMER_LOGS=$(docker logs --tail 20 gibsey-faust-worker 2>&1)
if echo "$CONSUMER_LOGS" | grep -q "test-$TIMESTAMP"; then
    echo -e "${GREEN}✓ Consumer received the test message!${NC}"
    echo -e "Relevant log entry:"
    echo "$CONSUMER_LOGS" | grep -A 3 "test-$TIMESTAMP"
else
    echo -e "${YELLOW}! Message not found in consumer logs yet${NC}"
    echo -e "This could be because:"
    echo -e "1. The consumer hasn't processed the message yet"
    echo -e "2. The consumer pattern doesn't match the topic name"
    echo -e "3. The consumer is not configured correctly"
    echo -e "\nCheck full consumer logs with:"
    echo -e "docker logs gibsey-faust-worker"
fi

echo -e "\n${YELLOW}${BOLD}===== MANUAL TEST COMPLETE =====${NC}"
echo "To send another test message, run this script again."