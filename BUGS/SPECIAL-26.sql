FLUSH LOCAL LOGS;
RESET MASTER TO 0x7FFFFFFF;
# [ERROR] Error reading packet from server: could not find next log; the first event '.' at 4, the last event read from 'binlog.000002' at 339, the last byte read from 'binlog.000002' at 379. (server_errno=1236)
# [ERROR] Slave I/O: Got fatal error 1236 from master when reading data from binary log: 'could not find next log; the first event '.' at 4, the last event read from 'binlog.000002' at 339, the last byte read from 'binlog.000002' at 379.', Internal MariaDB error code: 1236
