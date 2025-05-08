FROM debezium/connect:2.4

USER root
RUN mkdir -p /kafka/connect/debezium-connector-cassandra

# Download the connector directly - no need for Java locally
RUN curl -Lo /tmp/connector.jar https://repo1.maven.org/maven2/io/debezium/debezium-connector-cassandra/2.4.2.Final/debezium-connector-cassandra-2.4.2.Final-plugin.jar

# Move the JAR to the plugins directory
RUN mv /tmp/connector.jar /kafka/connect/debezium-connector-cassandra/debezium-connector-cassandra-2.4.2.Final.jar

# Create the service provider file that Kafka Connect needs
RUN mkdir -p /kafka/connect/debezium-connector-cassandra/META-INF/services/
RUN echo "io.debezium.connector.cassandra.CassandraConnector" > /kafka/connect/debezium-connector-cassandra/META-INF/services/org.apache.kafka.connect.source.SourceConnector

# Fix permissions
RUN chown -R kafka:kafka /kafka/connect && chmod -R 755 /kafka/connect

USER kafka

# This will be run by Docker Compose
CMD ["/docker-entrypoint.sh", "start"]
