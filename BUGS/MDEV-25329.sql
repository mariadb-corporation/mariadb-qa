SET @@session.max_error_count=-10;
SET profiling=1;
SET SESSION debug_dbug='+d,alloc_sort_buffer_fail';
SELECT * FROM performance_schema.events_waits_history_long ORDER BY thread_id;
