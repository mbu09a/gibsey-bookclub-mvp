# debezium.Dockerfile (Project Root)
FROM debezium/connect:2.4

USER root

# Create plugin directory 
# Copying contents into a subdirectory named after the connector is standard practice
RUN mkdir -p /kafka/connect/debezium-connector-cassandra

# Copy ALL contents from the local plugins directory
# Assumes infra/debezium-plugins contains the extracted TAR contents
COPY ./infra/debezium-plugins/ /kafka/connect/debezium-connector-cassandra/

# Copy custom properties and startup script if they exist and are needed
# These might have been added by Claude - verify their existence/necessity
COPY ./infra/connect-distributed.properties.custom /kafka/config/connect-distributed.properties.custom
COPY ./infra/start-connect.sh /kafka/start-connect.sh

# Fix permissions
RUN chown -R kafka:kafka /kafka/connect/debezium-connector-cassandra /kafka/config /kafka/start-connect.sh && \
    chmod -R 755 /kafka/connect/debezium-connector-cassandra && \
    chmod 755 /kafka/config/connect-distributed.properties.custom && \
    chmod +x /kafka/start-connect.sh

USER kafka

# Use the custom start script if it exists, otherwise default entrypoint
ENTRYPOINT ["/kafka/start-connect.sh"] 