SET @@global.wsrep_on=OFF;
XA START 'a';
SELECT GET_LOCK('test', 0) = 0 expect_1;
XA END 'a';
CACHE INDEX t1 PARTITION (ALL) KEY (`inx_b`,`PRIMARY`) IN default;
SELECT SLEEP(3);
