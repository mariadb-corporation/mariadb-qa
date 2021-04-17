Galera SST QA Script
====================

Galera SST QA script will help us to test state snapshot transfers(SSTs) in MariaDB Galera Cluster. There are three
different ways to transfer data from one node to another. This script will test all three methods with multiple 
mysqld/sst combinations.

Script usage info:

```
$ ~/mariadb-qa/galera-sst-qa/mariadb-galera-sst-test.sh --help
Usage:
./mariadb-galera-sst-test.sh  --basedir=PATH

Options:
  -b, --basedir=PATH                                 Specify MariaDB Galera base directory, mention full path
  -s, --sst-test=[all|mysql_dump|rsync|mariabackup]  Specify SST method for cluster data transfer
```

Default work directory is $PWD and for each test the logs will be saved in respective test directory ($PWD/logs/<test_name>).

```
$ ls -1 logs/
total 176
drwxrwxr-x 2 ramesh ramesh  4096 Apr 16 13:37 mariabackup_inno_page_size_16K_clear
drwxrwxr-x 2 ramesh ramesh  4096 Apr 16 13:37 mariabackup_inno_page_size_16K_crypt
drwxrwxr-x 2 ramesh ramesh  4096 Apr 16 13:38 mariabackup_inno_page_size_8K_clear
drwxrwxr-x 2 ramesh ramesh  4096 Apr 16 13:39 mariabackup_inno_page_size_8K_crypt
drwxrwxr-x 2 ramesh ramesh  4096 Apr 16 13:36 rsync_conf3_cnf-node_clear
drwxrwxr-x 2 ramesh ramesh  4096 Apr 16 13:36 rsync_conf3_cnf-node_crypt
drwxrwxr-x 2 ramesh ramesh  4096 Apr 16 13:33 rsync_inno_page_size_16K_clear
drwxrwxr-x 2 ramesh ramesh  4096 Apr 16 13:34 rsync_inno_page_size_16K_crypt
drwxrwxr-x 2 ramesh ramesh  4096 Apr 16 13:35 rsync_inno_page_size_4K_clear
drwxrwxr-x 2 ramesh ramesh  4096 Apr 16 13:35 rsync_inno_page_size_4K_crypt
drwxrwxr-x 2 ramesh ramesh  4096 Apr 16 13:34 rsync_inno_page_size_8K_clear
drwxrwxr-x 2 ramesh ramesh  4096 Apr 16 13:34 rsync_inno_page_size_8K_crypt
[..]
```

Script output
```
$ ~/mariadb-qa/galera-sst-qa/mariadb-galera-sst-test.sh -b$PWD/GAL_EMD150421-mariadb-10.5.10-7-linux-x86_64-opt --sst-test=all
Initiating SST test
Work directory: /test/mtest/galera-sst-qa
Log directory: /test/mtest/galera-sst-qa/logs
================================================================================================================
TEST                                                                                        RESULT     TIME(s)
----------------------------------------------------------------------------------------------------------------
galera_sst_rsync - # innodb_page_size(16K),clear                                            [passed]   19
galera_sst_rsync - # innodb_page_size(16K),crypt                                            [passed]   25
galera_sst_rsync - # innodb_page_size(8K),clear                                             [passed]   18
galera_sst_rsync - # innodb_page_size(8K),crypt                                             [passed]   24
galera_sst_rsync - # innodb_page_size(4K),clear                                             [passed]   19
galera_sst_rsync - # innodb_page_size(4K),crypt                                             [passed]   25
galera_sst_rsync - # [sst] xbstream + encrypt3 - clear                                      [passed]   18
galera_sst_rsync - # [sst] xbstream + encrypt3 - crypt                                      [passed]   24
================================================================================================================
================================================================================================================
TEST                                                                                        RESULT     TIME(s)
----------------------------------------------------------------------------------------------------------------
galera_sst_mariabackup - # innodb_page_size(16K),clear                                      [passed]   28
galera_sst_mariabackup - # innodb_page_size(16K),crypt                                      [passed]   35
galera_sst_mariabackup - # innodb_page_size(8K),clear                                       [passed]   28
galera_sst_mariabackup - # innodb_page_size(8K),crypt                                       [passed]   32
galera_sst_mariabackup - # innodb_page_size(4K),clear                                       [passed]   27
galera_sst_mariabackup - # innodb_page_size(4K),crypt                                       [passed]   36
galera_sst_mariabackup - # [sst] rlimit+time+progress - clear                               [passed]   38
galera_sst_mariabackup - # [sst] rlimit+time+progress - crypt                               [passed]   45
galera_sst_mariabackup - # [sst] xbstream - clear                                           [passed]   29
galera_sst_mariabackup - # [sst] xbstream - crypt                                           [passed]   32
galera_sst_mariabackup - # [sst] xbstream + encrypt3 - clear                                [passed]   29
galera_sst_mariabackup - # [sst] xbstream + encrypt3 - crypt                                [passed]   34
galera_sst_mariabackup - # [mariabackup] parallel [sst] progressfile+time - clear           [passed]   27
galera_sst_mariabackup - # [mariabackup] parallel [sst] progressfile+time - crypt           [passed]   37
galera_sst_mariabackup - # [sst] progressfile+time+xbstream - clear                         [passed]   28
galera_sst_mariabackup - # [sst] progressfile+time+xbstream - crypt                         [passed]   33
galera_sst_mariabackup - # [sst] xbstream+nc+progress+rlimit+time - clear                   [passed]   37
galera_sst_mariabackup - # [sst] xbstream+nc+progress+rlimit+time - crypt                   [passed]   43
galera_sst_mariabackup - # [mariabackup] parallel + [sst] sockopt - clear                   [passed]   28
galera_sst_mariabackup - # [mariabackup] parallel + [sst] sockopt - crypt                   [passed]   32
galera_sst_mariabackup - # [mysqld] external-log-bin  - clear                               [passed]   31
galera_sst_mariabackup - # [mysqld] external-log-bin  - crypt                               [passed]   34
galera_sst_mariabackup - # lost+found test - clear                                          [passed]   30
galera_sst_mariabackup - # lost+found test - crypt                                          [passed]   29
================================================================================================================
================================================================================================================
TEST                                                                                        RESULT     TIME(s)
----------------------------------------------------------------------------------------------------------------
galera_sst_mysqldump - # innodb_page_size(16K),clear                                        [passed]   24
galera_sst_mysqldump - # innodb_page_size(16K),crypt                                        [passed]   28
galera_sst_mysqldump - # innodb_page_size(8K),clear                                         [passed]   24
galera_sst_mysqldump - # innodb_page_size(8K),crypt                                         [passed]   32
galera_sst_mysqldump - # innodb_page_size(4K),clear                                         [passed]   25
galera_sst_mysqldump - # innodb_page_size(4K),crypt                                         [passed]   31
================================================================================================================
$
```
