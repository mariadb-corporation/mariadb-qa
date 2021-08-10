# mysqld options required for replay:  --tmp-disk-table-size=1024
SELECT * FROM information_schema.TRIGGERS ORDER BY trigger_name;
# Then check error log for: Incorrect information in file: './sys/sys_config.frm'
