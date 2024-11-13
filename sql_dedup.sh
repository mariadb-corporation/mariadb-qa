md5sum *.sql | sort | awk '{if ($1 == prev) system("rm \"" $2 "\"")} {prev=$1}'
