import random
import string
import itertools
import json
from itertools import permutations
from itertools import combinations
from datetime import datetime, timedelta
# Define a global variables

ctype_names = ""
ctype_data = ""
rand_data = ""
column_name_type = {}
column_name = ""
column_type = ""
index_columns = ""
char_set = ""
collation_name = ""
table_def = ""
lock_query = ""
column_def = [ "NOT NULL", "NULL" , "UNIQUE KEY", "PRIMARY KEY", "INVISIBLE" , "WITH SYSTEM VERSIONING", "WITHOUT SYSTEM VERSIONING" ]
engine = ["INNODB", "INNODB", "INNODB", "MYISAM", "MEMORY", "ARIA" ]
char_sets = [ "big5","dec8","cp850", "hp8","koi8r", "latin1", "latin2", "swe7","ascii", "ujis","sjis","hebrew", "tis620", "euckr", "koi8u", "gb2312", "greek", "cp1250", "gbk","latin5", "armscii8", "utf8mb3", "ucs2","cp866", "keybcs2", "macce", "macroman", "cp852", "latin7", "utf8mb4", "cp1251", "utf16", "utf16le", "cp1256", "cp1257", "utf32", "binary", "geostd8", "cp932", "eucjpms" ]
select_opts = [ "ALL", "DISTINCT", "DISTINCTROW", "HIGH_PRIORITY", "STRAIGHT_JOIN", "SQL_SMALL_RESULT", "SQL_BIG_RESULT", "SQL_BUFFER_RESULT", "SQL_CACHE", "SQL_NO_CACHE", "SQL_CALC_FOUND_ROWS", "" ]
where_condition = [ "GROUP BY", "ORDER BY" ]
sys_tables = ["Tables_priv","Gtid_slave_pos","Event","Time_zone_transition","Help_relation","Proxies_priv","Roles_mapping","Index_stats","Proc","Global_priv","Innodb_index_stats","Columns_priv","Help_keyword","Help_topic","Plugin","Slow_log","Help_category","Db","Time_zone_leap_second","Innodb_table_stats","Time_zone_name","General_log","User","Time_zone","Servers","Procs_priv","Column_stats","Time_zone_transition_type","Func","Table_stats","Transaction_registry"]

#Function to generate random alpha numeric string
def rand_alpha_num_string(length):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

# Generate a random JSON-compatible data structure
random_json_value = {
    "string": rand_alpha_num_string(random.randint(1, 16)),
    "number": random.randint(1, 100),
    "boolean": random.choice([True, False]),
    "array": [random.randint(1, 10) for _ in range(3)],
    "object": {"key": random.choice(["value1", "value2", "value3"])},
    "null": None
}

# Get lock statement
def lock_stmt(tbl):
    global lock_query
    lock_query = ''
    if tbl == "":
        lock_query = random.choice(["LOCK IN SHARE MODE;", "FLUSH TABLES WITH READ LOCK;"])
    else:
        lock_query = "LOCK TABLE " + tbl + " " +  random.choice(["READ", "WRITE"])
    
    print(lock_query)

# Get character set collation 
def get_char_set_collation(filename):
    global char_set, collation_name
    char_set = ''
    collation_name = ''
    char_set = random.choice(char_sets)
    # Open the file
    with open(filename, "r") as file:
        # Read lines containing character set into a list
        collations = [line.strip() for line in file if char_set in line.lower()]

    # Choose a random collation
    if collations:
        collation_name = random.choice(collations)
    else:
        print("collation not found for character set:" + char_set )

# Get session variable 
def get_session_variable(filename):
    with open(filename, 'r') as file:
        lines =  file.readlines()
        return random.choice(lines).strip()

# Generate SET session variable statement
def set_session_stmt():
    session_variable_file = random.choice(['session_variables_numeric.txt', 'session_variables.txt'])
    lines = get_session_variable(session_variable_file)
    if session_variable_file == "session_variables_numeric.txt":
        line = lines.split(',')
        print("SET " + line[0].strip() + " = " + str(random.randint( int(line[1].strip()) , int(line[2].strip()))) + ";")
    else:
        print(lines)


def random_date():
    # Generate random year between 0000 and 2024
    year = random.randint(1900, 2024)
    
    # Generate random month and day
    month = random.randint(1, 12)
    day = random.randint(1, 28)  # Limit day to 28 for simplicity, you may need to adjust this
    
    # Combine into a date object
    random_date = datetime(year, month, day)
    
    # Format the date as YYYY-MM-DD
    return random_date.strftime('%Y-%m-%d')

def random_time():
    # Generate random values for hours, minutes, and seconds
    hour = random.randint(0, 23)
    minute = random.randint(0, 59)
    second = random.randint(0, 59)
    
    # Format the time as HH:MM:SS
    return f"{hour:02d}:{minute:02d}:{second:02d}"

def random_timestamp(start_year, end_year):
    # Generate random values for year, month, day, hour, minute, second, and microsecond
    year = random.randint(start_year, end_year)
    month = random.randint(1, 12)
    day = random.randint(1, 28)  # Assuming all months have 28 days for simplicity
    hour = random.randint(0, 23)
    minute = random.randint(0, 59)
    second = random.randint(0, 59)
    microsecond = random.randint(0, 999999)

    # Create a datetime object with the random values
    random_datetime = datetime(year, month, day, hour, minute, second, microsecond)

    return random_datetime

# Generate data type for the table column
def get_data_type(filename):
    global ctype_data
    ctype_data = ''
    with open(filename, 'r') as file:
        lines = file.readlines()
        data_type = random.choice(lines).strip()
    
    ctype_data = gen_random_data(data_type)
    if ( data_type == "BIT" ):
        return data_type  + "(" + str(random.choice([8, 16, 32, 64])) + ")" 
    elif ( data_type == "REAL" or data_type == "DOUBLE" or data_type == "FLOAT" or data_type == "DECIMAL" ):
        return data_type  + "(" + str(random.choice(["2,2", "4,2", "8,2", "16,2"])) + ")" 
    elif ( data_type == "VARCHAR" or data_type == "VARBINARY" ):
        return data_type  + "(" + str(random.randint(0, 100)) + ")" 
    elif ( data_type == "ENUM" or data_type == "SET" ):
        return data_type  + "('1','2','3','4')" 
    else:
        return data_type

# Generate random data
def gen_random_data(ctype):    
    global rand_data
    rand_data = ''
    if ( ctype == "BIT" ):
        rand_data = bin(random.randint(0, 4096))[2:]  
    elif ( ctype == "REAL" or ctype == "DOUBLE" or ctype == "FLOAT" or ctype == "DECIMAL" ):
        rand_data  = round(random.uniform(1, 100000), 2)
    elif ( ctype == "TINYINT" or ctype == "SMALLINT" or ctype == "MEDIUMINT" or ctype == "INT"  or ctype == "BIGINT" or ctype == "INTEGER" or ctype == "NUMERIC" ):
        rand_data  = random.getrandbits(8)
    elif ( ctype == "VARCHAR" or ctype == "VARBINARY" or ctype == "CHAR" or ctype == "BINARY" or ctype == "TINYBLOB" or ctype == "BLOB" 
          or ctype == "MEDIUMBLOB" or ctype == "LONGBLOB" or ctype == "TINYTEXT" or ctype == "TEXT" or ctype == "MEDIUMTEXT" or ctype == "LONGTEXT"):
        rand_data = rand_alpha_num_string(random.randint(0, 255)) 
    elif ( ctype == "DATE" ):
        rand_data  = random_date()
    elif ( ctype == "TIME"): 
        rand_data  = random_time()
    elif ( ctype == "DATETIME"):
        rand_data  = f"{random_date()} {random_time()}"
    elif ( ctype == "TIMESTAMP"):
        rand_data  = random_timestamp(1900, 2024)
    elif ( ctype == "YEAR"):
        rand_data  = random.randint(1900, 2024)
    elif (ctype == "JSON"):
        rand_data  = json.dumps(random_json_value, indent=4)
    elif ( ctype == "ENUM" or ctype == "SET" ):
        rand_data  = random.choice(['1','2','3','4']) 
    else:
        rand_data = rand_alpha_num_string(random.randint(0, 32)) 

    return rand_data

def select_statement(column_count):
    columns = random.randint(1, column_count)
    select_columns = ""
    for i in range(columns):
        if i == columns - 1:
            select_columns += "c" + str(i) 
        else:
            select_columns += "c" + str(i) + ","
    where_column_count = random.randint(1, column_count)
    where_columns = ""
    for i in range(where_column_count):
        if i == where_column_count - 1:
            where_columns += "c" + str(i) 
        else:
            where_columns += "c" + str(i) + ","

    stmt = "SELECT " + random.choice(select_opts) + " " + select_columns + " FROM " + tname + " WHERE " 
    print(stmt)

# Get table columns
def tbl_columns(column_nos):
    global ctype_names, column_name, column_type, column_name_type
    ctype_names = ''
    column_name_type = {}
    column_name = ''
    column_type = ''
    for i in range(column_nos):
        column_name = "c" + str(i) 
        column_type = get_data_type('ctype.txt')
        #ctype_data = gen_random_data(column_type[i])
        if i == 0:
            if column_nos == 1:
                ctype_names += column_name + " " + column_type + " " + random.choice(column_def)  
            else:
                ctype_names += column_name + " " + column_type + " " + random.choice(column_def) + ", "
        elif i == column_nos - 1:
            ctype_names += column_name + " " + column_type
        else:
            ctype_names += column_name + " " + column_type + ", " 

        column_name_type[column_name] =  ctype_data

# Generate indexes for table columns
def indexes(column_count):
    global index_columns
    columns = random.randint(1, column_count)
    index_columns = ""
    for i in range(columns):
        index_columns += ",  INDEX (c" + str(i) + ") "

# Generate alter statement
def alter_statement(tname, cname):
    column_type = get_data_type('ctype.txt')
    column_def = ""
    column_def = cname + " " + column_type 
    alg_options = [ 'DEFAULT', 'INPLACE', 'COPY', 'NOCOPY', 'INSTANT' ]
    lock_opts = [ 'DEFAULT', 'NONE', 'SHARED', 'EXCLUSIVE' ]
    opts1 = random.choice(['ONLINE', 'IGNORE', ''])
    opts2 = random.choice(['WAIT ' + str(random.randint(1, 5)), 'NOWAIT'])
    opts3 = random.choice(['ALGORITHM = ' + random.choice(alg_options) , 'LOCK = ' + random.choice(lock_opts)])
    opts4 = random.choice(['ADD', 'MODIFY', 'CHANGE', 'RENAME' ])
    if opts4 == "ADD":
        tbl_columns(1)
        column_def = "ADD COLUMN " + ctype_names
        column_def = column_def.replace("c0", "c" + str(random.randint(11, 20)))
        print("ALTER " + opts1 + " TABLE " + tname + " " + column_def + ", " + opts3 + ";")
    elif opts4 == "CHANGE":
        tbl_columns(1)
        column_def = ctype_names.replace("c0", "c" + str(random.randint(11, 20)))
        column_def = "CHANGE " + cname + " " + column_def
        print("ALTER " + opts1 + " TABLE " + tname + " " + column_def + ", " + opts3 + ";")
    elif opts4 == "MODIFY":
        tbl_columns(1)
        column_def = "MODIFY " + ctype_names
        print("ALTER " + opts1 + " TABLE " + tname + " " + column_def + ", " + opts3 + ";")
    elif opts4 == "RENAME":
        tbl_columns(1)
        column_def = "MODIFY " + ctype_names
        print("ALTER " + opts1 + " TABLE " + tname + " RENAME COLUMN " + column_def + "TO  " + opts3 + ";")

    

# Generate OPTIMIZE/ANALYZE statements
def optimize_table_statements(tname):
    optimize_table_stmt = random.choice(['OPTIMIZE', 'ANALYZE', 'REPAIR'])
    opts1 = random.choice(['NO_WRITE_TO_BINLOG', 'LOCAL'])
    opts2 = random.choice(['WAIT ' + str(random.randint(1, 5)), 'NOWAIT'])
    opts3 = random.choice(['PERSISTENT FOR ALL', 'PERSISTENT FOR () INDEXES ()', 'PERSISTENT FOR (' + str(random.randint(1, 5)) + ') INDEXES (' + str(random.randint(1, 5)) + ')'])
    opts4 = random.choice(['QUICK', 'EXTENDED', 'USE_FRM'])

    if optimize_table_stmt == "OPTIMIZE":
        print(optimize_table_stmt + " " + opts1 + " TABLE " + tname + " " + opts2 + ";")
    elif optimize_table_stmt == "REPAIR":
        print(optimize_table_stmt + " " + opts1 + " TABLE " + tname + " " + opts4 + ";")
    else:
        print(optimize_table_stmt + " " + opts1 + " TABLE " + tname + " " + opts3 + ";")

def partition_stmt():
    part_count = random.randint(1, 10)
    part_stmt = ""
    for i in range(part_count):
        if i == part_count - 1:
            part_stmt += "PARTITION p" + str(i) + " VALUES LESS THAN (" +  str(100*i) + ")"
        else:
            part_stmt += "PARTITION p" + str(i) + " VALUES LESS THAN (" + str(100*i) + "),"
    return part_stmt

# Print all permutations
def create_partition_tbls(iteration):
    for i in range(iteration):
        tpname = 'tp' + str(random.randint(0, 32))
        tname = 't' + str(random.randint(0, 32))
        engine = ["INNODB", "INNODB", "MYISAM", "MEMORY", "ARIA" ]
        alg_options = [ 'DEFAULT', 'INPLACE', 'COPY', 'NOCOPY', 'INSTANT' ]
        lock_opts = [ 'DEFAULT', 'NONE', 'SHARED', 'EXCLUSIVE' ]
        alg_lock_opts = random.choice(['ALGORITHM = ' + random.choice(alg_options) , 'LOCK = ' + random.choice(lock_opts)])
        print("CREATE OR REPLACE TABLE " + tpname + "(id INT NOT NULL ) ENGINE=" + random.choice(engine) + " PARTITION BY RANGE (id) ( " + str(partition_stmt()) + " ) ;")
        print("CREATE OR REPLACE TABLE " + tname + "(id INT NOT NULL ) ENGINE=" + random.choice(engine) + ";")
        print("INSERT INTO " + tpname + f" SELECT seq FROM seq_1_to_1001;")
        print("ALTER TABLE " +  tpname + " ADD COLUMN c1 INT, " + alg_lock_opts + ";")
        print("ALTER TABLE " +  tpname + " EXCHANGE PARTITION p" + str(random.randint(1, 10)) + " WITH TABLE t" + tname + " " + random.choice(['WITH VALIDATION', 'WITHOUT VALIDATION', '']) + ";")
        print("LOCK TABLE " + tpname + " READ;")
        print("ALTER TABLE " +  tpname + " REORGANIZE PARTITION p" + str(random.randint(1, 10)) + " INTO ( PARTITION  p" + str(random.randint(1, 10)) + "a VALUES LESS THAN (900))");
        print("LOCK TABLE " + tpname + " WRITE;")
        print("ALTER TABLE " +  tpname + " " + random.choice(['ANALYZE', 'CHECK','TRUNCATE','REPAIR', 'OPTIMIZE']) + " PARTITION " + random.choice(['p0', 'p1', 'p0,p1', 'p1,p2', 'p0,p3' ]) + ";")
        print("UNLOCK TABLES;")
        print("ALTER TABLE " +  tpname + " REMOVE PARTITIONING;")
        print("DROP TABLE " + tpname + ";")
        print("DROP TABLE " + tname + ";")

# Get random user privileges
def user_privs():
    user_privileges = [ 'ALL', 'USAGE', 'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'CREATE', 'DROP', 'RELOAD', 'SHUTDOWN', 'PROCESS', 'FILE', 'REFERENCES', 'INDEX', 'ALTER', 'SHOW DATABASES', 'SUPER', 'CREATE TEMPORARY TABLES', 'LOCK TABLES', 'EXECUTE', 'REPLICATION SLAVE', 'BINLOG MONITOR', 'CREATE VIEW', 'SHOW VIEW', 'CREATE ROUTINE', 'ALTER ROUTINE', 'CREATE USER', 'EVENT', 'TRIGGER', 'CREATE TABLESPACE', 'DELETE HISTORY', 'SET USER', 'FEDERATED ADMIN', 'CONNECTION ADMIN', 'READ_ONLY ADMIN', 'REPLICATION SLAVE ADMIN', 'REPLICATION MASTER ADMIN', 'BINLOG ADMIN', 'BINLOG REPLAY', 'SLAVE MONITOR' ]
    random_user_privs =  random.sample(user_privileges, random.randint(1, 6))
    grant_user_privs = ''
    for i in range(len(random_user_privs)):
        if i == len(random_user_privs) - 1:
            grant_user_privs += random_user_privs[i]
        else:
            grant_user_privs += random_user_privs[i] + ", "
    return grant_user_privs  

def dcl_stmt():
    uname = rand_alpha_num_string(random.randint(2, 32))
    host = random.choice(["localhost", "%", "127.%" ])
    print("CREATE USER " + random.choice(['IF NOT EXISTS', '']) + " " + uname + "@'" + host + "';")
    print("GRANT " + user_privs() + " ON *.* TO " + uname + "@'" + host + "';")
    print("SELECT * FROM sys.table_privileges;")
    print("GRANT " + user_privs() + " ON *.* TO " + uname + "@'" + host + "';")
    print("SELECT * FROM sys.table_privileges;")
    print("DROP USER " + random.choice(['IF NOT EXISTS', '']) + " " + uname + "@'" + host + "';")

# Get all permutations of 2 ASCII letters
permutations = itertools.product(string.ascii_letters, repeat=2)

# Print all permutations
#for i in range(random.randint(1, 2)):
for code_point in range(1000): 
    tbl_columns(random.randint(1, 10))
    # get_char_set_collation('char_set_collation.txt')
    char_set = random.choice(["utf8mb3", "utf8mb4"])
    if char_set == "utf8mb3":
        collation_name = "utf8mb3_general1400_as_ci"
    else:
        collation_name = "utf8mb4_general1400_as_ci"
    table_options = " CHARACTER SET = " + char_set + " COLLATE = " + collation_name 
    tname = 't' + str(random.randint(0, 32))
    indexes(len(column_name_type))
    print(f"CREATE OR REPLACE TABLE " + tname + f" (  {ctype_names} {index_columns} ) ENGINE = " + random.choice(engine) + table_options + ";")
    # Generate INSERT permutations based on the columns
    for key, value in column_name_type.items():
        print(f"{random.choice(['START TRANSACTION;', 'BEGIN;'])}")
        print(f"INSERT INTO " + tname + f"({key}) VALUES ('{value}');") 
        lock_stmt(random.choice([tname, '']))
        print(f"UPDATE " + tname + f" SET {key} = '{value}{rand_alpha_num_string(1)}' WHERE {key} {random.choice(['=','>','<','>=', '<=', '<>'])} '{value}';") 
        print(f"DELETE FROM " + tname + f" WHERE {key} {random.choice(['=','>','<','>=', '<=', '<>'])} '{value}';") 
        print(f"SELECT {random.choice(select_opts)} {key} FROM " + tname + f" WHERE {key} {random.choice(['=','>','<','>=', '<=', '<>'])} '{value}' {random.choice(where_condition)} {key} ;") 
        print("HANDLER " + tname + " OPEN;") 
        print("HANDLER " + tname + " READ " + random.choice(['FIRST','NEXT']) + ";") 
        print("HANDLER " + tname + " READ c" + str(random.randint(0, 2)) + " " + random.choice(['FIRST','NEXT','LAST','PREV']) + ";") 
        print("HANDLER " + tname + " CLOSE;") 
        print("UNLOCK TABLES;")
        select_statement(len(column_name_type))
        set_session_stmt()
        optimize_table_statements(tname)
        print("COMMIT;")
        alter_statement(tname, "c" + str(random.randint(1,len(column_name_type)))) 
        dcl_stmt()
    optimize_table_statements(tname)
    #create_partition_tbls(10)
    
       


    
