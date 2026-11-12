CREATE TABLE t1 (a INT PRIMARY KEY, b INT, c VARCHAR(20), KEY kb (b), KEY kbc (b, c));
INSERT INTO t1 VALUES (1,1,'x'),(2,2,'y'),(3,3,'z');
SET @ctx='{"tables":[{"name":"test.t1","file_stat_records":3,"data_file_length":16384,"index_file_length":32768,"mean_rec_length":5461,"read_cost_io":4,"read_cost_cpu":0.0104286,"multi_range_read_info_const_calls":[{"index_name":"kb","ranges":["(2) <= (b) <= (2)"],"num_rows":1,"cost":{"avg_io_cost":0.0002048,"cpu_cost":0,"comp_cost":3.2e-05,"copy_cost":0,"limit_cost":0,"setup_cost":0.00079112,"index_cost_io":4,"index_cost_cpu":-100,"row_cost_io":4,"row_cost_cpu":0.00086244},"mrr_mode":76,"max_index_blocks":4,"max_row_blocks":4,"call_number":1}]}]}';
SET optimizer_replay_context='ctx';
SELECT * FROM t1 WHERE b = 2;

CREATE TABLE t1 (a INT PRIMARY KEY, b INT, c VARCHAR(20), KEY kb (b), KEY kbc (b, c));
INSERT INTO t1 VALUES (1,1,'x'),(2,2,'y'),(3,3,'z');
SET @ctx='{"tables":[{"name":"test.t1","file_stat_records":3,"data_file_length":16384,"index_file_length":32768,"mean_rec_length":5461,"read_cost_io":4,"read_cost_cpu":0.0104286,"multi_range_read_info_const_calls":[{"index_name":"kb","ranges":["(2) <= (b) <= (2)"],"num_rows":2147483648,"cost":{"avg_io_cost":0.0002048,"cpu_cost":0,"comp_cost":3.2e-05,"copy_cost":0,"limit_cost":0,"setup_cost":0.00079112,"index_cost_io":4,"index_cost_cpu":0.00092572,"row_cost_io":4,"row_cost_cpu":0.00086244},"mrr_mode":76,"max_index_blocks":4,"max_row_blocks":4,"call_number":1}]}]}';
SET optimizer_replay_context='ctx';
SELECT * FROM t1 WHERE b = 2;
