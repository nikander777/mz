-- Создаёт БД для discogs (muzilla_main уже создана через POSTGRES_DB).
SELECT 'CREATE DATABASE muzilla_discogs' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'muzilla_discogs')\gexec
