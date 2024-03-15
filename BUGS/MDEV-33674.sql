# Requires m/s setup
SET sql_mode='';
CREATE ROLE r1;
GRANT r1 TO current_user;
GRANT SELECT ON * TO '1';
