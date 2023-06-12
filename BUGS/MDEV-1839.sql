set wsrep_on=0;
XA START 'a';
XA END 'a';
XA COMMIT 'a' ONE PHASE;
