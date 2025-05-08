# infra/Dockerfile (For Debezium)
FROM debezium/connect:2.4

USER root
RUN mkdir -p /kafka/connect

# COPY paths relative to build context (infra/)
COPY ./debezium-plugins/ /kafka/connect/
COPY ./connect-distributed.properties.custom /kafka/config/connect-distributed.properties.custom
COPY ./start-connect.sh /kafka/start-connect.sh

# Fix permissions
RUN chown -R kafka:kafka /kafka/connect /kafka/config /kafka/start-connect.sh && \
    chmod -R 755 /kafka/connect && \
    chmod 755 /kafka/config/connect-distributed.properties.custom && \
    chmod +x /kafka/start-connect.sh

USER kafka
ENTRYPOINT ["/kafka/start-connect.sh"] 