# Requires MTR to reproduce
INSTALL PLUGIN server_audit SONAME 'server_audit2';
SET GLOBAL server_audit_file_path= 'a.log';
SET GLOBAL server_audit_logging= ON;
SET GLOBAL server_audit_query_log_limit= 0;
SET GLOBAL server_audit_file_rotations= 0;
--let $D= `SELECT @@datadir`
--let SWEEP= $MYSQLTEST_VARDIR/tmp/m2469_overrun.sql
--perl
open(my $o, '>', $ENV{SWEEP}) or die "cannot write $ENV{SWEEP}: $!";
for (my $len = 800; $len <= 6400; $len += 2) {
  print $o ("'" x $len), ";\n";
}
close $o;
EOF
--exec $MYSQL --force test < $SWEEP > /dev/null 2>&1 || true
