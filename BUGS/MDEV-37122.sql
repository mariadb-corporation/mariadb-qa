INSTALL PLUGIN server_audit SONAME 'server_audit';
SET GLOBAL server_audit_logging=ON;
SET GLOBAL server_audit_output_type=0;
SET GLOBAL init_slave="none";
CHANGE MASTER TO master_host='0.0.0.0';
START SLAVE;
SET GLOBAL server_audit_file_buffer_size=0;

DROP DATABASE test;
CREATE DATABASE test;
INSTALL PLUGIN server_audit SONAME 'server_audit';
SET GLOBAL init_slave='SELECT 1';
SET GLOBAL server_audit_logging=ON;
SET GLOBAL server_audit_output_type=SYSLOG;
CHANGE MASTER TO master_host='dummy';
START SLAVE SQL_THREAD;
