# Requires standard m/s setup, SBR/MBR/RBR all affected
SET @@old_passwords=1;
CREATE USER ''@'localhost';
SELECT (@id:=Id) FROM information_schema.processlist WHERE User='repl_user';  # change to replication user
KILL QUERY @id;
