SET SESSION pseudo_slave_mode=1;
XA BEGIN 'a';
XA END 'a';
XA PREPARE 'a';
XA COMMIT 'a';
SELECT SLEEP(5);
