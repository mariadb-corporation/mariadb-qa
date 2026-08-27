BINLOG ' a';
SELECT @@pseudo_slave_mode;
SET pseudo_slave_mode=1;
SHOW WARNINGS;

BINLOG '';
SELECT @@pseudo_slave_mode;
SET pseudo_slave_mode=1;
SHOW WARNINGS;

BINLOG ' ';
SELECT @@pseudo_slave_mode;
SET pseudo_slave_mode=1;
SHOW WARNINGS;

BINLOG 'tR2NahNkAAAALQAAAG4CAAAAABIAAAAAAAEABHRlc3QAAnQxAAEDAAFDVLB/tR2NahdkAAAAJgAAAJQCAAAAABIAAAAAAAEAAQH+BwAAAEUYH2g=';
SELECT @@pseudo_slave_mode;
SET pseudo_slave_mode=1;
SHOW WARNINGS;
