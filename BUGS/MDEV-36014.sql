SET @@collation_connection=BINARY;
SELECT CONVERT(REPLACE (EXPORT_SET ('','','',''),0,'') USING ujis);
