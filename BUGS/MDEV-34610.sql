SET SESSION tmp_disk_table_size=1024;
SELECT 1 FROM information_schema.global_variables JOIN seq_1_to_100 INTERSECT ALL SELECT * FROM information_schema.global_variables JOIN seq_1_to_100;
