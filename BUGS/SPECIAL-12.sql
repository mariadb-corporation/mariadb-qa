create TABLE t1 (x int) engine=merge union=(t2);
BINLOG 'AMqaOw8BAAAAdAAAAHgAAAAAAAQANS42LjM0LTc5LjEtZGVidWctbG9nAAAAAAAAAAAAAAAAAAAA AAAAAAAAAAAAAAAAAAAAAAAAEzgNAAgAEgAEBAQEEgAAXAAEGggAAAAICAgCAAAACgoKGRkAAYVx w2w=';
BINLOG 'wlZOTxMBAAAAKgAAADwCAAAAACkAAAAAAAEABHRlc3QAAnQxAAIDAwAC wlZOTxcBAAAAJgAAAGICAAAAACkAAAAAAAEAAv/8AgAAAAgAAAA=';
# ERROR 1168 (HY000): Unable to open underlying table which is differently defined or of non-MyISAM type or doesn't exist
# [ERROR]  BINLOG_BASE64_EVENT: Error executing row event: 'Unable to open underlying table which is differently defined or of non-MyISAM type or doesn't exist', Internal MariaDB error code: 1168
