# mysqld options required for replay:  --thread_handling=pool-of-threads
SET GLOBAL thread_pool_stall_limit=2148;  # >=2148 triggers the issue
