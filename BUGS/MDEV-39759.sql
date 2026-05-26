CHANGE MASTER 'ch_b' TO master_delay=1;
SET NAMES BINARY;
SET @@default_master_connection='ch1';
SET SESSION collation_connection=utf32_icelandic_ci;
SET SESSION default_master_connection='ch2';
CHANGE MASTER TO master_use_gtid=slave_pos;
