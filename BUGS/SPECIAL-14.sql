create TABLE t1(id INT,x INT)ENGINE=InnoDB;
ALTER TABLE t1 ENGINE=MRG_MyISAM UNION=(t1,t2)INSERT_METHOD=LAST;
BINLOG ' SOgWTg8BAAAAbgAAAHIAAAAAAAQANS42LjMtbTUtZGVidWctbG9nAAAAAAAAAAAAAAAAAAAAAAAA AAAAAAAAAAAAAAAAAABI6BZOEzgNAAgAEgAEBAQEEgAAVgAEGggAAAAICAgCAAAAAAVAYI8=';
BINLOG 'wlZOTxMBAAAAKgAAADwCAAAAACkAAAAAAAEABHRlc3QAAnQxAAIDAwAC wlZOTxcBAAAAJgAAAGICAAAAACkAAAAAAAEAAv/8AgAAAAgAAAA=';
# ERROR 1472 (HY000): Table 't1' is differently defined or of non-MyISAM type or doesn't exist
# [ERROR]  BINLOG_BASE64_EVENT: Error executing row event: 'Table 't1' is differently defined or of non-MyISAM type or doesn't exist', Internal MariaDB error code: 1472