RESET MASTER;
CREATE TABLE t (c BLOB,c2 DOUBLE (0,0) ZEROFILL,c3 CHAR CHARACTER SET 'utf8' COLLATE 'utf8_bin') ENGINE=InnoDB;
CREATE TABLE t2 (c INT,c2 DOUBLE (0,0) ZEROFILL,c3 FLOAT(0,0) ZEROFILL,KEY(c)) ENGINE=InnoDB;
CREATE TABLE t3 (c TIME KEY,c2 GEOMETRYCOLLECTION,c3 DATE) ENGINE=InnoDB;
# [ERROR] Error reading packet from server: The binlog on the master is missing the GTID 0-2-130 requested by the slave (even though both a prior and a subsequent sequence number does exist), and GTID strict mode is enabled (server_errno=1236)
# [ERROR] Slave I/O: Got fatal error 1236 from master when reading data from binary log: 'The binlog on the master is missing the GTID 0-2-130 requested by the slave (even though both a prior and a subsequent sequence number does exist), and GTID strict mode is enabled', Internal MariaDB error code: 1236

RESET MASTER;
CREATE TABLE t33 (c CHAR(1));#ERROR: 1-xaer_rmfail: ���� �ܧ�ާѧߧէ� �ߧ֧ݧ�٧� �ӧ����ݧߧ��� �ܧ�ԧէ� �ԧݧ�ҧѧݧ�ߧѧ� ���ѧߧ٧ѧܧ�ڧ� �ߧѧ��էڧ��� �� �������ߧڧ�''#NOERROR;
CREATE TABLE t1 (a CHAR(1));
INSERT INTO t1 VALUES (1),(1),(1);

RESET MASTER;
CREATE TABLE ti1 (a INT,b INT,c INT) ENGINE=FEDERATED COMMENT='WRAPPER "mysql",SRV "srv",TABLE "t"' COMMENT='WRAPPER "mysql",SRV "srv",TABLE "t"';
CREATE TABLE t1 (a INT KEY,b INT,c INT,UNIQUE (b)) ENGINE=InnoDB;
CREATE TABLE mysql.host (c INT) ENGINE=InnoDB;

RESET MASTER;
CREATE TABLE t8 (HOST CHAR(1) BINARY DEFAULT'',Db CHAR(1) BINARY DEFAULT'',USER CHAR(1) BINARY DEFAULT'',select_priv ENUM ('','') COLLATE utf8_general_ci DEFAULT'',insert_priv ENUM ('','') COLLATE utf8_general_ci DEFAULT'',update_priv ENUM ('','') COLLATE utf8_general_ci DEFAULT'',delete_priv ENUM ('','') COLLATE utf8_general_ci DEFAULT'',create_priv ENUM ('','') COLLATE utf8_general_ci DEFAULT'',drop_priv ENUM ('','') COLLATE utf8_general_ci DEFAULT'',grant_priv ENUM ('','') COLLATE utf8_general_ci DEFAULT'',references_priv ENUM ('','') COLLATE utf8_general_ci DEFAULT'',index_priv ENUM ('','') COLLATE utf8_general_ci DEFAULT'',alter_priv ENUM ('','') COLLATE utf8_general_ci DEFAULT'',create_tmp_table_priv ENUM ('','') COLLATE utf8_general_ci DEFAULT'',lock_tables_priv ENUM ('','') COLLATE utf8_general_ci DEFAULT'',create_view_priv ENUM ('','') COLLATE utf8_general_ci DEFAULT'',show_view_priv ENUM ('','') COLLATE utf8_general_ci DEFAULT'',create_routine_priv ENUM ('','') COLLATE utf8_general_ci DEFAULT'',alter_routine_priv ENUM ('','') COLLATE utf8_general_ci DEFAULT'',execute_priv ENUM ('','') COLLATE utf8_general_ci DEFAULT'',KEY USER (USER)) CHARACTER SET utf8 COLLATE utf8_bin COMMENT='DATABASE PRIVILEGES';
