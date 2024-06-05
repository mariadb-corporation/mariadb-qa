# Any invalid CHANGE MASTER TO leading to Slave I.O: Got fatal error 1236 from master when reading data from binary log.*Binary log is not open.*Internal MariaDB error code: 1236, like for example
SET default_master_connection='m1';
SET GLOBAL server_id=200;
CHANGE MASTER TO master_host='127.0.0.1',master_port=16000,master_user='root',master_connect_retry=1, MASTER_SSL_VERIFY_SERVER_CERT=0;
START SLAVE;
# [ERROR] Master 'm1': Error reading packet from server: Binary log is not open (server_errno=1236)
# [ERROR] Master 'm1': Slave I/O: Got fatal error 1236 from master when reading data from binary log: 'Binary log is not open', Internal MariaDB error code: 1236
