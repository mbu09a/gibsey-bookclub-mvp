#!/bin/bash

# Simple healthcheck for Debezium/Kafka Connect
CONNECT_URL="http://localhost:8083/"

# Try to access the Kafka Connect REST API
response=$(curl -s -o /dev/null -w "%{http_code}" $CONNECT_URL)

if [ "$response" == "200" ]; then
  echo "Debezium/Kafka Connect is healthy!"
  exit 0
else
  echo "Debezium/Kafka Connect is not healthy. Response code: $response"
  exit 1
fi 