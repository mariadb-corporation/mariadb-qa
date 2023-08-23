CREATE VIEW c AS SELECT * FROM information_schema.VIEWS;
SET GLOBAL aria_encrypt_tables=1;
PREPARE s FROM 'SELECT * FROM c';
EXECUTE s;
EXECUTE s;
