XA START 'y';
XA END 'y';
LOAD INDEX INTO CACHE t2 KEY (`PRIMARY`,`inx_b`);
SET GLOBAL wsrep_on=OFF;
SET SESSION wsrep_trx_fragment_size = 0;
