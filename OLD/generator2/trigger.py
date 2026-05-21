import random
import string

engine = ["INNODB", "INNODB", "INNODB", "MYISAM", "MEMORY", "ARIA" ]

#Function to generate random alpha numeric string
def rand_alpha_num_string(length):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

for code_point in range(1000):
    tname1 = 'tbl_t' + str(random.randint(0, 32)) + "_1"
    tname2 = 'tbl_t' + str(random.randint(0, 32)) + "_2"
    print(f"CREATE OR REPLACE TABLE " + tname1 + f"(c1 INT ) ENGINE = " + random.choice(engine) + ";")
    print(f"CREATE OR REPLACE TABLE " + tname2 + f"(c1 INT ) ENGINE = " + random.choice(engine) + ";")
    print(f"INSERT INTO " + tname1 + f" VALUES (1),(2),(3),(4);")
    print(f"INSERT INTO " + tname2 + f" VALUES (1),(2),(3),(4);") 
    print(f"CREATE OR REPLACE TRIGGER " + tname1 + "_trg" + str(random.randint(0, 32)) + " AFTER INSERT ON " +  tname1  + " FOR EACH ROW UPDATE " + tname2 + f" SET c1 = c1+1;")
    print(f"CREATE OR REPLACE TRIGGER " + tname1 + "_trg" + str(random.randint(0, 32)) + " BEFORE INSERT ON " +  tname1  + " FOR EACH ROW UPDATE " + tname2 + f" SET c1 = c1+1;")
    print(f"CREATE OR REPLACE TRIGGER " + tname1 + "_trg" + str(random.randint(0, 32)) + " AFTER DELETE ON " +  tname1  + " FOR EACH ROW INSERT INTO " + tname2 + f" VALUES (100);")
    print(f"CREATE OR REPLACE TRIGGER " + tname1 + "_trg" + str(random.randint(0, 32)) + " BEFORE DELETE ON " +  tname1  + " FOR EACH ROW INSERT INTO " + tname2 + f" VALUES (200);")
    print(f"INSERT INTO " + tname1 + f" VALUES (1001);")
    print(f"DELETE FROM " + tname1 + f" LIMIT 1;")
    