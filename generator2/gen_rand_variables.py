import sys
import getopt
import threading
import mysql.connector
from queue import Queue
import time
import random

# Function to get script usage info
def usage():
    print("Usage: python gen_rand_variables.py [OPTIONS]")
    print("Options:")
    print("  --help                     Display this help message")
    print("  -u, --user <USERNAME>      Specify mariadb/mysql username")
    print("  -p, --password <PASSWORD>  Specify mariadb/mysql password")
    print("  -h, --hostname <HOSTNAME>  Specify mariadb/mysql hostname")
    print("  -d, --database <DATABASE>  Specify mariadb/mysql database")
    print("  -v, --verbose              Enable verbose mode")

# Define default values
username = 'root'
password=''
port=3306
database = 'test'
hostname = 'localhost'
verbose_mode = False

# Get parsed command-line arguments
def get_options(argv):
    global username, password, hostname, database, port
    
    try:
        opts, args = getopt.getopt(argv, "u:p:H:d:P:v", ["help", "user=", "password=", "hostname=", "database=", "port=", "verbose"])
    except getopt.GetoptError as err:
        print(err)
        usage()
        sys.exit(2)
    
    for opt, arg in opts:
        if opt in ("--help"):
            usage()
            sys.exit()
        elif opt in ("-u", "--user"):
            username = arg
        elif opt in ("-p", "--password"):
            password = arg
        elif opt in ("-H", "--hostname"):
            hostname = arg
        elif opt in ("-P", "--port"):
            port = arg
        elif opt in ("-d", "--database"):
            database = arg
        elif opt in ("-v", "--verbose"):
            verbose_mode = True
    
get_options(sys.argv[1:])

# Function to execute MySQL SELECT query
def execute_query():
    try:
        # Connect to MySQL
        connection = mysql.connector.connect(
            host=hostname,
            port=port,
            database=database,
            user=username,
            password=password
        )
        
        # Execute the query
        cursor = connection.cursor()
        #cursor.execute(query)
        
        sql_query = "SELECT lower(VARIABLE_NAME),NUMERIC_MIN_VALUE,NUMERIC_MAX_VALUE from INFORMATION_SCHEMA.SYSTEM_VARIABLES where ENUM_VALUE_LIST is null and NUMERIC_MIN_VALUE is not null and VARIABLE_NAME not in ('INNODB_MAX_DIRTY_PAGES_PCT','INNODB_MAX_DIRTY_PAGES_PCT_LWM');"
        #sql_query = "SELECT VARIABLE_NAME,ENUM_VALUE_LIST from INFORMATION_SCHEMA.SYSTEM_VARIABLES where ENUM_VALUE_LIST is not null;"
        # Execute the query
        cursor.execute(sql_query)

        # Fetch all the rows
        rows = cursor.fetchall()

        # Print the fetched rows
        for row in rows:
            print("--" + str(row[0]) + "=" + str(int(row[1]) - 10))
            print("--" + str(row[0]) + "=" + row[1])
            print("--" + str(row[0]) + "=" + row[2])
            print("--" + str(row[0]) + "=" + str(int(row[1]) + 100))
            random_numbers = [random.randint(int(row[1]), int(row[2])) for _ in range(10)]
            for i in range(len(random_numbers)):
                print("--" + str(row[0]) + "=" + str(random_numbers[i]))

        sql_query = "SELECT LOWER(VARIABLE_NAME),ENUM_VALUE_LIST from INFORMATION_SCHEMA.SYSTEM_VARIABLES where ENUM_VALUE_LIST is not null;"
        # Execute the query
        cursor.execute(sql_query)

        # Fetch all the rows
        rows = cursor.fetchall()
        
        # Print the fetched rows
        for row in rows:
            values = row[1].split(',')
            for i in range(len(values)):
                print("--" + str(row[0]) + "=" + values[i])

        # Close cursor and connection
        cursor.close()
        connection.close()
    except Exception as e:
        print(f"Error executing query: {e}")

execute_query()