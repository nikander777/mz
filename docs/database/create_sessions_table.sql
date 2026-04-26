-- SQL script to create sessions table for Laravel
CREATE TABLE sessions (
    id varchar(255) NOT NULL PRIMARY KEY,
    user_id integer DEFAULT NULL,
    ip_address varchar(45) DEFAULT NULL,
    user_agent text DEFAULT NULL,
    payload text NOT NULL,
    last_activity integer NOT NULL
);

-- Create indexes for better performance
CREATE INDEX sessions_user_id_index ON sessions (user_id);
CREATE INDEX sessions_last_activity_index ON sessions (last_activity);