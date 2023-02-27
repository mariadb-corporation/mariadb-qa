FOR rec IN cur (2) DO SELECT * a;
SHUTDOWN;

FOR rec IN cur (0) DO SELECT * cur;
SET GLOBAL session_track_system_variables='a';
SHUTDOWN;

# Then check error log for:  # Warning: Memory not freed: 280/264/256/312
