# mysqld options required for replay:  --plugin-maturity=unknown
INSTALL PLUGIN example SONAME 'ha_example.so';
SET @a=(SELECT 0 FROM information_schema.session_status WHERE variable_name='a');
