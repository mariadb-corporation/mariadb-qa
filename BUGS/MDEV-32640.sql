PREPARE s_1 FROM 'SHOW RELAYLOG EVENTS';
SET default_master_connection='MASTER';
EXECUTE s_1;
SET default_master_connection='MASTER';
EXECUTE s_1;
