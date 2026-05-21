import random
import string

engine = ["INNODB", "INNODB", "INNODB", "MYISAM", "MEMORY", "ARIA" ]

def update_query(t1, t2=None):
    if t2 is None:
        query = "UPDATE " + t1 + " SET c1=" + str(random.choice(["NULL", "@FOO", random.randint(1,65535)])) + ";"
    else:
        query = "UPDATE " + t1 + " JOIN " + t2 + " ON SET " + t1 + ".c1=" + t2 + ".c1;"

    return query
for code_point in range(10):
    tname1 = 't' + str(random.randint(0, 32))
    tname2 = 't' + str(random.randint(0, 32))
    print("CREATE OR REPLACE TABLE " + tname1 + f"(c1 INT ) ENGINE = " + random.choice(engine) + ";")
    print("CREATE OR REPLACE TABLE " + tname2 + f"(c1 INT ) ENGINE = " + random.choice(engine) + ";")
    print("INSERT INTO " + tname1 + f" SELECT seq FROM seq_10_to_20;")
    print("INSERT INTO " + tname1 + f" SELECT 5;")
    print("INSERT INTO " + tname1 + f" VALUES (1),(2),(3),(4);")
    print("INSERT INTO " + tname2 + f" SELECT seq FROM seq_10_to_20;")
    print("INSERT INTO " + tname2 + f" SELECT 5;")
    print("INSERT INTO " + tname2 + f" VALUES (1),(2),(3),(4);")
    print("SELECT * FROM " + tname1 + " JOIN " + tname2 + " ON " + tname1 + ".c1=" + tname2 + ".c1 ORDER BY " + tname2 + ".c1;")
    print("UPDATE " + tname1 + " JOIN " + tname2 + " SET " + tname1 + ".c1= " + str(random.choice(["NULL", "@FOO", random.randint(1,65535)])) + " ORDER BY " + tname2 + ".c1;")
    print("SELECT * FROM " + tname1 + " JOIN " + tname2 + " ORDER BY " + tname2 + ".c1;")
    print("UPDATE " + tname1 + f" SET c1=NULL;")
    print("UPDATE " + tname1 + f" SET c1=@FOO;")
    print("UPDATE " + tname1 + f" SET c1=128;")
    print("DELETE FROM " + tname1 + f" LIMIT 1;")
    print("DELETE " + tname1 + " FROM " + tname1 + " JOIN " + tname2 + " LIMIT 10;")
    