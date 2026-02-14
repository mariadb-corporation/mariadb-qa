# LSAN memory loss and CLI/ERR bugs (ref kb for OPENTABLE UniqueIDs):
INSTALL SONAME 'ha_connect';
CREATE TABLE t (a INT) ENGINE=CONNECT table_type=ODBC CATFUNC=Drivers;
SELECT * FROM t;
SHUTDOWN;
# CLI: ERROR 1296 (HY000): Got error 174 'Invalid flag 0 for column a' from CONNECT
# ERR: OpenTable: Invalid flag 0 for column a

INSTALL SONAME 'ha_connect';
CREATE TABLE t (a INT) ENGINE=CONNECT table_type=ODBC;
SELECT * FROM t;
SHUTDOWN;
# CLI: ERROR 1296 (HY000): Got error 174 'SQLDriverConnect: [unixODBC][Driver Manager]Data source name not found and no default driver
# ERR: OpenTable: SQLDriverConnect: [unixODBC][Driver Manager]Data source name not found and no default driver specified
