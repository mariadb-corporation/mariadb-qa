INSTALL PLUGIN server_audit SONAME 'server_audit';
SET GLOBAL server_audit_logging=ON;
SET GLOBAL server_audit_file_buffer_size=8192;  # Apparent default of 8k
SELECT 1;
