import random
import string
import itertools
import json
from itertools import permutations
from itertools import combinations
from datetime import datetime, timedelta
# Define a global variables

def rand_alpha_num_string(length):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

# Get all permutations of 2 ASCII letters
permutations = itertools.product(string.ascii_letters, repeat=3)

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
for i in range(1000):
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