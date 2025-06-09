BINLOG ' SOgWTg8BAAAAbgAAAHIAAAAAAAQANS42LjMtbTUtZGVidididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididididWctbG9nAAAAAAAAAAAAAAAAAAAAAAAA AAAAAAAAAAAAAAAAAABI6BZOEzgNAAgAEgAEBAQEEgAAVgAEGggAAAAICAgCAAAAAAVAYI8=';
# This clearly corrupt BINLOG stmt will result in an assertion indicating it's corruption, on debug builds only:
# ERR: mariadbd: /test/11.4_dbg/sql/log_event.cc:2344: enum_binlog_checksum_alg get_checksum_alg(const uchar *, ulong): Assertion `ret == BINLOG_CHECKSUM_ALG_OFF || ret == BINLOG_CHECKSUM_ALG_UNDEF || ret == BINLOG_CHECKSUM_ALG_CRC32' failed.
# And it fails as incorrect on optimized builds:
# CLI: ERROR 1149 (42000): You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use
