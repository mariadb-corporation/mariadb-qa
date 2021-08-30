SET SESSION tmp_disk_table_size=2047, big_tables=1;
SELECT table_name FROM information_schema.tables WHERE table_schema='sys' AND table_type='';
