import threading
import time
import mysql.connector
import random
import string

#Function to generate random alpha numeric string
def rand_string(length):
    return ''.join(random.choices(string.ascii_letters, k=length))

#Function to generate random alpha numeric string
def rand_alpha_num_string(length):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

# Function to perform database operations in a thread
def db_operations_thread(conn_params, duration):
    conn = mysql.connector.connect(**conn_params)
    cursor = conn.cursor()

    start_time = time.time()
    end_time = start_time + duration

    while time.time() < end_time:
        RowType = random.choice(['freeCode','semiExpiredCode','expiredCode','legacyLoansWithDecode','nextGenCodebase'])
        updateRowType = random.choice(['freeCode','semiExpiredCode','expiredCode','legacyLoansWithDecode','nextGenCodebase'])
        RedirectFunction = random.choice(['prepop','affiliateInformationOnly','unsubscribe'])
        DomainUrl = rand_string(random.randint(2,6)) + "." + random.choice(["co", "in", "eu"])
        shortCodeText = rand_alpha_num_string(4)
        # Generate random operation (insert, update, delete)
        operation = random.choice(["UPDATE", "DELETE"])
        if operation == "INSERT":    
            # Perform insert operation
            cursor.execute("INSERT INTO redirectData (shortDomainUrl,shortCodeText,rowType,redirectFunction) VALUES ('" + DomainUrl + "','" + shortCodeText +  "','" + RowType +  "','" + RedirectFunction +  "')")
        elif operation == "UPDATE":
            # Perform update operation
            cursor.execute("UPDATE redirectData SET rowType = '" + updateRowType + "' WHERE rowType = '" + RowType + "' limit 1")
        elif operation == "DELETE":
            # Perform delete operation
            cursor.execute("DELETE FROM redirectData WHERE RedirectFunction = '" + RedirectFunction + "' limit 1")

        # Commit the transaction
        conn.commit()

        # Sleep for a random interval between operations
        time.sleep(random.uniform(0.1, 0.5))

    cursor.close()
    conn.close()

# Define connection parameters
conn_params = {
    'host' : '127.0.0.1',
    'port' : '10655',
    'database' : 'test',
    'user' : 'test_user',
    'password' : 'password'
}

# Define duration for the threads to run (in seconds)
duration = 3000  # 

# Define the number of threads
num_threads = 5

# Create and start threads
threads = []
for _ in range(num_threads):
    thread = threading.Thread(target=db_operations_thread, args=(conn_params, duration))
    thread.start()
    threads.append(thread)

# Wait for all threads to complete
for thread in threads:
    thread.join()

print("All threads completed.")
