FOR rec IN cur (2) DO SELECT * a;
SHUTDOWN;

# Then check error log for:  # Warning: Memory not freed: 280/264/256
