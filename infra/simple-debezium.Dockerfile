FROM debezium/connect:2.4

USER root
RUN mkdir -p /kafka/connect/debezium-connector-cassandra
RUN curl -Lo /tmp/connector.jar https://repo1.maven.org/maven2/io/debezium/debezium-connector-cassandra/2.4.2.Final/debezium-connector-cassandra-2.4.2.Final-plugin.jar

# Create the service provider file
RUN mkdir -p /tmp/services/META-INF/services/
RUN echo "io.debezium.connector.cassandra.CassandraConnector" > /tmp/services/META-INF/services/org.apache.kafka.connect.source.SourceConnector

# Add the service provider to the JAR
RUN mkdir -p /kafka/connect/debezium-connector-cassandra/META-INF/services/
RUN cp /tmp/services/META-INF/services/org.apache.kafka.connect.source.SourceConnector /kafka/connect/debezium-connector-cassandra/META-INF/services/
RUN cp /tmp/connector.jar /kafka/connect/debezium-connector-cassandra/

# Fix permissions
RUN chown -R kafka:kafka /kafka/connect && chmod -R 755 /kafka/connect

USER kafka
