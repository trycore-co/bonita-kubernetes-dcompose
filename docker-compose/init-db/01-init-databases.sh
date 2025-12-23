#!/bin/bash
# PostgreSQL database initialization script for Bonita
# This script creates the required databases and users for Bonita Runtime

set -e

echo "============================================"
echo "Initializing Bonita databases..."
echo "============================================"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
	-- Create Bonita user and database
	CREATE USER bonitauser WITH PASSWORD 'myDbSecret';
	CREATE DATABASE bonita OWNER bonitauser;

	-- Create Business Data Model (BDM) user and database
	CREATE USER bizuser WITH PASSWORD 'myBdmSecret';
	CREATE DATABASE bizdata OWNER bizuser;

	-- Grant necessary privileges
	GRANT ALL PRIVILEGES ON DATABASE bonita TO bonitauser;
	GRANT ALL PRIVILEGES ON DATABASE bizdata TO bizuser;
EOSQL

echo "============================================"
echo "Bonita databases initialized successfully!"
echo "  - bonita database (owner: bonitauser)"
echo "  - bizdata database (owner: bizuser)"
echo "============================================"
