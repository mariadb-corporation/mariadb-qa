XA START 'a';
XA END 'a';
SET SESSION tmp_disk_table_size=0;
SELECT * FROM information_schema.tables t JOIN information_schema.COLUMNS c ON t.table_schema=c.table_schema WHERE c.table_schema=(SELECT COUNT(*) FROM information_schema.COLUMNS GROUP BY column_type) GROUP BY t.table_name;

