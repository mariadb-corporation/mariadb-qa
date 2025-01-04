# pip3 install --break-system-packages aiomysql

import random
import asyncio
import aiomysql
import os
import time
import logging
import sys
from concurrent.futures import ThreadPoolExecutor

# User variables
USER = "root"
SOCKET_FILE = "socket.sock"
DB_NAME = "test"
QUERY_COUNT = "unlimited"  # Set to a number or 'unlimited'
LOG_FILE = os.path.join(os.path.dirname(SOCKET_FILE), "executed_queries.log")
FAILED_LOG_FILE = os.path.join(os.path.dirname(SOCKET_FILE), "failed_queries.log")
MAX_DEPTH = 59  # Maximum depth for subqueries
POOL_SIZE = 70  # Number of concurrent connections in the pool
GENERATOR_THREADS = 2  # Number of threads for parallel query generation

# List of aggregate functions to choose from
aggregate_funcs = ['SUM', 'AVG', 'COUNT', 'MAX', 'MIN', 'GROUP_CONCAT']

# List of comparison operators for conditions
comparison_ops = ['>', '<', '=', '>=', '<=']

# List of set operators for conditions
set_ops = ['ANY', 'ALL', 'IN']

# List of join types
join_types = ['INNER JOIN', 'LEFT JOIN', 'RIGHT JOIN', 'CROSS JOIN', 'NATURAL JOIN', 'STRAIGHT_JOIN']

# List of window functions
window_funcs = ['ROW_NUMBER()', 'RANK()', 'DENSE_RANK()', 'NTILE(4)']

# Set up logging for executed queries
logging.basicConfig(filename=LOG_FILE, level=logging.INFO, format='%(message)s')

# Set up logging for failed queries
failed_logger = logging.getLogger("failed_queries")
failed_logger.setLevel(logging.ERROR)
failed_handler = logging.FileHandler(FAILED_LOG_FILE)
failed_handler.setFormatter(logging.Formatter('%(message)s'))
failed_logger.addHandler(failed_handler)

# Function to generate a subquery at a given depth
def generate_subquery(depth, alias_counter):
    if depth == 0:
        alias = f"sub{alias_counter[0]}"
        alias_counter[0] += 1
        return f"(SELECT 1 AS x) AS {alias}", f"{alias}.x"
    else:
        inner_query, inner_alias = generate_subquery(depth - 1, alias_counter)
        if random.choice([True, False]):
            agg_func = random.choice(aggregate_funcs)
            group_by = random.choice([True, False])
            having = random.choice([True, False]) if group_by else False
            alias = f"sub{alias_counter[0]}"
            alias_counter[0] += 1
            query = f"(SELECT {agg_func}({inner_alias}) AS x FROM {inner_query}"
            if group_by:
                query += f" GROUP BY {inner_alias}"
                if having:
                    op = random.choice(comparison_ops)
                    value = random.randint(1, 10)
                    query += f" HAVING {inner_alias} {op} {value}"
            query += f") AS {alias}"
            return query, f"{alias}.x"
        else:
            op = random.choice(comparison_ops)
            value = random.randint(1, 10)
            condition = f"{inner_alias} {op} {value}"
            alias = f"sub{alias_counter[0]}"
            alias_counter[0] += 1
            return f"(SELECT {inner_alias} AS x FROM {inner_query} WHERE {condition}) AS {alias}", f"{alias}.x"

# Function to generate a join clause
def generate_join(subquery1, alias1, subquery2, alias2):
    join_type = random.choice(join_types)
    if join_type == "NATURAL JOIN":
        return f"{join_type} {subquery2}"
    else:
        condition = f"{alias1} = {alias2}"
        return f"{join_type} {subquery2} ON {condition}"

# Function to generate a window function
def generate_window_function(alias):
    window_func = random.choice(window_funcs)
    return f"{window_func} OVER (ORDER BY {alias})"

# Function to generate a CASE expression
def generate_case_expression(alias):
    case = "CASE "
    for _ in range(random.randint(1, 3)):
        op = random.choice(comparison_ops)
        value = random.randint(1, 10)
        when_condition = f"WHEN {alias} {op} {value} THEN {random.randint(1, 10)} "
        case += when_condition
    case += f"ELSE {random.randint(1, 10)} END"
    return case

# Function to generate the main query with optional clauses
def generate_main_query(max_depth):
    alias_counter = [0]  # Counter to ensure unique aliases
    depth = random.randint(1, max_depth)
    subquery1, sub_alias1 = generate_subquery(depth, alias_counter)
    subquery2, sub_alias2 = generate_subquery(depth, alias_counter)
    
    # Start with the base query
    query = f"SELECT {sub_alias1}"
    
    # Add a WINDOW function randomly
    if random.choice([True, False]):
        window_func = generate_window_function(sub_alias1)
        query += f", {window_func}"
    
    # Add a CASE expression randomly
    if random.choice([True, False]):
        case_expr = generate_case_expression(sub_alias1)
        query += f", {case_expr}"
    
    query += f" FROM {subquery1}"
    
    # Add a JOIN randomly
    if random.choice([True, False]):
        join_clause = generate_join(subquery1, sub_alias1, subquery2, sub_alias2)
        query += f" {join_clause}"
    
    # Add a WHERE clause randomly
    if random.choice([True, False]):
        if random.choice([True, False]):
            op = random.choice(comparison_ops)
            value = random.randint(1, 10)
            query += f" WHERE {sub_alias1} {op} {value}"
        else:
            set_op = random.choice(set_ops)
            if set_op == 'IN':
                values = [random.randint(1, 10) for _ in range(random.randint(1, 5))]
                query += f" WHERE {sub_alias1} {set_op} ({', '.join(map(str, values))})"
            else:
                op = random.choice(comparison_ops)
                value = random.randint(1, 10)
                query += f" WHERE {sub_alias1} {op} {set_op} (SELECT {random.choice(aggregate_funcs)}(x) FROM {subquery1})"
    
    # Add a GROUP BY clause randomly
    group_by_added = random.choice([True, False])
    if group_by_added:
        query += f" GROUP BY {sub_alias1}"
    
    # Add an ORDER BY clause randomly
    order_by_added = random.choice([True, False])
    if order_by_added:
        order = random.choice(['ASC', 'DESC'])
        query += f" ORDER BY {sub_alias1} {order}"
    
    # Add a LIMIT clause randomly
    limit_added = random.choice([True, False])
    if limit_added:
        limit = random.randint(1, 100)
        query += f" LIMIT {limit}"
    
    # Add a DISTINCT clause randomly
    if random.choice([True, False]):
        query = query.replace("SELECT", "SELECT DISTINCT")
    
    # Add WITH ROLLUP only if there is a GROUP BY clause and no ORDER BY, LIMIT, or UNION
    if random.choice([True, False]) and group_by_added and not order_by_added and not limit_added:
        query += " WITH ROLLUP"
    
    query += ";"
    return query

# Function to execute a single query asynchronously
async def execute_query(pool, query):
    async with pool.acquire() as conn:
        async with conn.cursor() as cursor:
            try:
                # Log the query being executed
                logging.info(query)
                # Execute the query (no need to fetch results)
                await cursor.execute(query)
                return True  # Query succeeded
            except Exception as e:
                # Log the failing query and error
                error_message = f"{query}  # ERROR {e.args[0]}: {e.args[1]}"
                failed_logger.error(error_message)
                
                # Check for "Lost connection to MySQL server" error (ERROR 2013)
                if e.args[0] == 2013:
                    print("ERROR 2013: Lost connection to MySQL server. Terminating script.")
                    sys.exit(1)  # Immediately terminate the script
                
                return False  # Query failed

# Function to continuously generate and execute queries
async def process_queries():
    # Create connection pool with configurable size
    pool = await aiomysql.create_pool(
        user=USER,
        unix_socket=SOCKET_FILE,
        db=DB_NAME,
        charset='utf8mb4',
        cursorclass=aiomysql.DictCursor,
        minsize=POOL_SIZE,  # Minimum number of connections in the pool
        maxsize=POOL_SIZE   # Maximum number of connections in the pool
    )

    query_count = 0
    start_time = time.time()

    # Queue to hold generated queries
    queue = asyncio.Queue(maxsize=POOL_SIZE * 2)

    # Function to generate queries in parallel
    async def generate_queries():
        nonlocal query_count
        with ThreadPoolExecutor(max_workers=GENERATOR_THREADS) as executor:
            while QUERY_COUNT == "unlimited" or query_count < QUERY_COUNT:
                # Generate queries in parallel
                future = executor.submit(generate_main_query, MAX_DEPTH)
                query = await asyncio.wrap_future(future)
                await queue.put(query)
                query_count += 1

    # Function to execute queries from the queue
    async def consume_queries():
        while True:
            query = await queue.get()
            if query is None:  # Sentinel value to stop
                break
            success = await execute_query(pool, query)
            if not success:
                #print(f"Query failed: {query}")  # Debugging
                pass
            queue.task_done()

    # Start the query generator and consumers
    generator_task = asyncio.create_task(generate_queries())
    consumer_tasks = [asyncio.create_task(consume_queries()) for _ in range(POOL_SIZE)]

    # Wait for the generator to finish
    await generator_task

    # Wait for the queue to be empty
    await queue.join()

    # Stop the consumers
    for _ in range(POOL_SIZE):
        await queue.put(None)
    await asyncio.gather(*consumer_tasks)

    # Close the connection pool
    pool.close()
    await pool.wait_closed()

    end_time = time.time()
    print(f"Executed {query_count} queries in {end_time - start_time:.2f} seconds")

# Main
if __name__ == "__main__":
    asyncio.run(process_queries())
