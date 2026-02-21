SELECT 'CREATE DATABASE feast_registry'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'feast_registry')\gexec

\c feast_registry
GRANT ALL PRIVILEGES ON DATABASE feast_registry TO sentinel_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO sentinel_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO sentinel_user;

\echo 'Database "feast_registry" created and permissions granted to "sentinel_user".'