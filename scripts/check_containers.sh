#!/bin/bash
# Script to check the status of all containers in the CDC pipeline

echo "===== CHECKING CONTAINER STATUS ====="
docker ps -a | grep "gibsey-"

echo
echo "===== CHECKING CASSANDRA ====="
docker logs --tail 20 gibsey-cassandra

echo
echo "===== CHECKING KAFKA ====="
docker logs --tail 20 gibsey-kafka 

echo
echo "===== CHECKING ZOOKEEPER ====="
docker logs --tail 20 gibsey-zookeeper

echo
echo "===== CHECKING STARGATE ====="
docker logs --tail 20 gibsey-stargate

echo
echo "===== CHECKING DEBEZIUM ====="
docker logs gibsey-debezium

echo
echo "===== CHECKING FAUST WORKER ====="
docker logs gibsey-faust-worker

echo
echo "===== NETWORK CHECKS ====="
echo "Checking if Debezium Connect port is open:"
curl -v telnet://localhost:8083 2>&1 | grep -i "connected"

echo "Checking if Kafka port is open:"
curl -v telnet://localhost:9092 2>&1 | grep -i "connected"

echo "Checking if Cassandra port is open:"
curl -v telnet://localhost:9042 2>&1 | grep -i "connected"

echo "Checking if Stargate port is open:"
curl -v telnet://localhost:8082 2>&1 | grep -i "connected"

echo
echo "===== RESTART DEBEZIUM MANUALLY ====="
echo "Command to manually start Debezium:"
echo "docker start gibsey-debezium && docker logs -f gibsey-debezium"

echo
echo "===== SETUP SCRIPT ====="
echo "Command to run setup script (after Debezium is running):"
echo "./scripts/setup_debezium_connector.sh"