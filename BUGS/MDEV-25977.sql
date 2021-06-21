SET GLOBAL wsrep_sst_auth=USER;
SHUTDOWN;
# Will lead to 'Warning: Memory not freed: 32' or similar
