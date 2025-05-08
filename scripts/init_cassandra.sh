#!/bin/bash
# Script to initialize Cassandra keyspace and tables with CDC enabled

# 1) Keyspace + tables (CDC ON)
docker exec -it gibsey-cassandra cqlsh -e "\
CREATE KEYSPACE IF NOT EXISTS gibsey \nWITH replication = {'class':'SimpleStrategy','replication_factor':1};\n\
USE gibsey;\n\
CREATE TABLE IF NOT EXISTS pages (\n  id text PRIMARY KEY,\n  title text,\n  content text,\n  section text\n) WITH cdc = true;\n\
CREATE TABLE IF NOT EXISTS page_vectors (\n  id text PRIMARY KEY,\n  vector_data blob\n);\n\
CREATE TABLE IF NOT EXISTS questions (\n  id text PRIMARY KEY,\n  user_id text,\n  question text,\n  timestamp timestamp\n) WITH cdc = true;\n\
CREATE TABLE IF NOT EXISTS answers (\n  id text PRIMARY KEY,\n  question_id text,\n  content text,\n  timestamp timestamp,\n  citations list<text>\n) WITH cdc = true;\n"

# 2) Seed row so Debezium has immediate content
docker exec -it gibsey-cassandra cqlsh -e "\
INSERT INTO gibsey.pages (id, title, content, section) \nVALUES ('seed-1', 'Seed Page', 'Hello, CDC world', 'Introduction');\n"

echo "Cassandra initialization complete!"