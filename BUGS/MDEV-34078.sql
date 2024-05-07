SET SESSION sql_mode='';
CREATE TABLE t (a DATE,b INT,c INT,d INT,e INT,f INT,g INT,h INT,i DATE,j INT,k INT,l INT,m INT,n INT,o INT,p INT,q DATE,r INT,s INT,t INT,u INT,v INT,w INT,x INT,y DATE,z INT,aa INT,ab INT,ac INT,ad INT,ae INT,af INT,PRIMARY KEY(a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z,aa,ab,ac,ad,ae,af)) ENGINE=InnoDB PARTITION BY KEY(a) (PARTITION p, PARTITION p2);
INSERT INTO t (a) VALUES (0);
SELECT SLEEP(2);  # Allow server to finish slow-crashing
