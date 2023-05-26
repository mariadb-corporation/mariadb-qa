SET JOIN_buffer_size=1;
SET SESSION JOIN_cache_level=4;
SET SESSION optimizer_switch='optimize_JOIN_buffer_size=OFF';
SELECT * FROM information_schema.statistics JOIN information_schema.COLUMNS USING (table_name,column_name);
