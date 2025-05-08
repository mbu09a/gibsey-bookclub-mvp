#!/bin/bash
# Script to download and install the Cassandra connector for Debezium

echo "=== DOWNLOADING CASSANDRA CONNECTOR ==="

# Directory for the connector
mkdir -p connector-temp

# Download the connector
echo "Downloading Cassandra connector..."
curl -Lo connector-temp/debezium-connector-cassandra.jar https://repo1.maven.org/maven2/io/debezium/debezium-connector-cassandra/2.4.2.Final/debezium-connector-cassandra-2.4.2.Final-plugin.jar

echo "Connector downloaded to connector-temp/debezium-connector-cassandra.jar"
echo "=== DOWNLOAD COMPLETE ==="
echo "Mount this directory in your Debezium container to use the connector."