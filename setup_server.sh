#!/bin/bash
# Created by Roel Van de Paar, Percona LLC
# Updated by Roel Van de Paar, MariaDB

# Handy command to see per-user pid max settings, and current status;
# cat /sys/fs/cgroup/pids/user.slice/user-${UID}.slice/pids.max  # or use ${EUID}, change pids.max to others
# cat /sys/fs/cgroup/pids/user.slice/user-${UID}.slice/pids.current

# References, with thanks
# https://www.ibm.com/support/knowledgecenter/SSEPGG_11.1.0/com.ibm.db2.luw.qb.server.doc/doc/t0008238.html
# https://www.serverwatch.com/server-tutorials/set-user-limits-with-pamlimits-and-limits.conf.html
# https://sigquit.wordpress.com/2009/03/13/the-core-pattern/

echo "Substantial changes will be made to the system configuration of this machine. Press CTRL+C within the next 7 seconds to abort if you are not sure if that is a wise idea."
echo "Script assumes that this machine is a Ubuntu 18.04 server!"
echo "Script assumes current user is sudo-enabled."
sleep 7

sudo snap install shellcheck
sudo snap install shfmt

# vimrc Script
touch ~/.vimrc
cat << EOF >> ~/.vimrc
" tabstop:          Width of tab character
" softtabstop:      Fine tunes the amount of white space to be added
" shiftwidth        Determines the amount of whitespace to add in normal mode
" expandtab:        When on uses space instead of tabs
set tabstop     =2
set softtabstop =2
set shiftwidth  =2
set expandtab
set nocompatible
colo torte
syntax on
EOF

# GDB Script
touch ~/.gdbinit
if [ -z "$(cat ~/.gdbinit|grep 'print elements')" ]; then cat << EOF > ~/.gdbinit
add-auto-load-safe-path /usr/lib/x86_64-linux-gnu/libthread_db.so
add-auto-load-safe-path /usr/lib/x86_64-linux-gnu/libthread_db.so.1
set auto-load safe-path /
set libthread-db-search-path /usr/lib/x86_64-linux-gnu/libthread_db.so
set debuginfod enabled on
#set pagination off
#set print pretty on
#set print frame-arguments all
EOF
fi

# Screen Script
touch ~/.screenrc
if [ -z "$(cat ~/.screenrc|grep 'termcapinfo xterm')" ]; then cat << EOF > ~/.screenrc
# General settings
vbell on
vbell_msg '!Bell!'
autodetach on
startup_message off
defscrollback 10000

# Termcapinfo for xterm
termcapinfo xterm* Z0=\E[?3h:Z1=\E[?3l:is=\E[r\E[m\E[2J\E[H\E[?7h\E[?1;4;6l   # Do not resize window
termcapinfo xterm* OL=1000                                                    # Increase output buffer for speed

# Remove various keyboard bindings
bind x    # Do not lock screen
bind ^x   # Idem
bind h    # Do not write out copy of screen to disk
bind ^h   # Idem
bind ^\   # Do not kill all windows/exit screen
bind .    # Disable dumptermcap

# Add keyboard bindings
bind } history
bind k kill
EOF
fi

# Enable true core file creation by disabling apport, with thanks https://askubuntu.com/a/93467
# Note that a server restart is needed for core files to work [again], even if the service is stopped
sudo systemctl stop apport.service
sudo systemctl disable apport.service
sudo systemctl mask apport.service

echo "These settings are for a 128GB Memory server (google cloud instance of that size or similar)"
# Do not add a fixed path to the kernel.core_pattern setting, it does not work correctly
# RV [12 Oct 2020] also found that specifying a long core pattern like 'kernel.core_pattern=core.%p.%u.%s.%e.%t', works less well - cores are generated few times then when just using 'kernel.core_pattern=core', at least no Ubuntu 20.04 LTS. More root cause analysis needed, issue is very illusive. Reverted to just using '=core' for the moment, which is sufficient for the framework. By disaling apport.service it would even seem that this setting is not strictly needed. The 'Unsafe core_pattern used with fs.suid_dumpable=2. Pipe handler or fully qualified core dump path required. Set kernel.core_pattern before fs.suid_dumpable.' can be considered expected and does not affect core file generation.
#if [ "$(grep -m1 '^kernel.core_pattern=core.%p.%u.%s.%e.%t' /etc/sysctl.conf)" != 'kernel.core_pattern=core.%p.%u.%s.%e.%t' ]; then
#  sudo bash -c 'echo "kernel.core_pattern=core.%p.%u.%s.%e.%t" >> /etc/sysctl.conf'  # Do NOT a core fixed path!
#fi
if [ "$(grep -m1 '^kernel.core_pattern=core' /etc/sysctl.conf)" != 'kernel.core_pattern=core' ]; then
  sudo bash -c 'echo "kernel.core_pattern=core" >> /etc/sysctl.conf'  # Do NOT a core fixed path!
fi
if [ "$(grep -m1 '^fs.suid_dumpable=2' /etc/sysctl.conf)" != 'fs.suid_dumpable=2' ]; then
  sudo bash -c 'echo "fs.suid_dumpable=2" >> /etc/sysctl.conf'
fi
if [ "$(grep -m1 '^fs.aio-max-nr=99999999' /etc/sysctl.conf)" != 'fs.aio-max-nr=99999999' ]; then
  sudo bash -c 'echo "fs.aio-max-nr=99999999" >> /etc/sysctl.conf'
fi
if [ "$(grep -m1 '^fs.file-max=99999999' /etc/sysctl.conf)" != 'fs.file-max=99999999' ]; then
  sudo bash -c 'echo "fs.file-max=99999999" >> /etc/sysctl.conf'
fi
if [ "$(grep -m1 '^kernel.pid_max=4194304' /etc/sysctl.conf)" != 'kernel.pid_max=4194304' ]; then
  sudo bash -c 'echo "kernel.pid_max=4194304" >> /etc/sysctl.conf'
fi
if [ "$(grep -m1 '^kernel.threads-max=99999999' /etc/sysctl.conf)" != 'kernel.threads-max=99999999' ]; then
  sudo bash -c 'echo "kernel.threads-max=99999999" >> /etc/sysctl.conf'
fi
if [ "$(grep -m1 '^kernel.sem = 32768 1073741824 2000 32768' /etc/sysctl.conf)" != 'kernel.sem = 32768 1073741824 2000 32768' ]; then
  sudo bash -c 'echo "kernel.sem = 32768 1073741824 2000 32768" >> /etc/sysctl.conf'
fi
if [ "$(grep -m1 '^kernel.shmmni=32768' /etc/sysctl.conf)" != 'kernel.shmmni=32768' ]; then
  sudo bash -c 'echo "kernel.shmmni=32768" >> /etc/sysctl.conf'  # 32768 is the effective max value
fi
if [ "$(grep -m1 '^kernel.msgmax=65536' /etc/sysctl.conf)" != 'kernel.msgmax=65536' ]; then
  sudo bash -c 'echo "kernel.msgmax=65536" >> /etc/sysctl.conf'
fi
if [ "$(grep -m1 '^kernel.msgmni=32768' /etc/sysctl.conf)" != 'kernel.msgmni=32768' ]; then
  sudo bash -c 'echo "kernel.msgmni=32768" >> /etc/sysctl.conf'  # 32768 is the effective max value
fi
if [ "$(grep -m1 '^kernel.msgmnb=65536' /etc/sysctl.conf)" != 'kernel.msgmnb=65536' ]; then
  sudo bash -c 'echo "kernel.msgmnb=65536" >> /etc/sysctl.conf'
fi
if [ "$(grep -m1 '^m.max_map_count=1048576' /etc/sysctl.conf)" != 'vm.max_map_count=1048576' ]; then
  sudo bash -c 'echo "vm.max_map_count=1048576" >> /etc/sysctl.conf'
fi
if [ "$(grep -m1 '^vm.swappiness=5' /etc/sysctl.conf)" != 'vm.swappiness=5' ]; then
  sudo bash -c 'echo "vm.swappiness=5" >> /etc/sysctl.conf'
fi
# Attempt to improve memory management for testing servers, with thanks:
# https://superuser.com/a/1150229/457699
# https://serverfault.com/a/142003/129146
# https://sysctl-explorer.net/vm/oom_dump_tasks/
# https://www.kernel.org/doc/Documentation/sysctl/vm.txt
if [ "$(grep -m1 '^vm.overcommit_memory=1' /etc/sysctl.conf)" != 'vm.overcommit_memory=1' ]; then
  sudo bash -c 'echo "vm.overcommit_memory=1" >> /etc/sysctl.conf'
fi
if [ "$(grep -m1 '^vm.oom_dump_tasks=0' /etc/sysctl.conf)" != 'vm.oom_dump_tasks=0' ]; then
  sudo bash -c 'echo "vm.oom_dump_tasks=0" >> /etc/sysctl.conf'
fi
if [ "$(grep -m1 '^vm.panic_on_oom=0' /etc/sysctl.conf)" != 'vm.panic_on_oom=0' ]; then
  sudo bash -c 'echo "vm.panic_on_oom=0" >> /etc/sysctl.conf'
fi
# On GCP test instances, set the number of hugepages to 0
if grep -qi 'vm.nr_hugepages' /etc/sysctl.conf; then
  sudo sed -i 's|^vm.nr_hugepages.*|vm.nr_hugepages=0|' /etc/sysctl.conf; sudo sysctl -p
else
  sudo bash -c 'echo "vm.nr_hugepages=0" >> /etc/sysctl.conf'
fi

# Note that a high number (>20480) for soft+hard nproc may cause system instability/hang on Centos7
# hard stack 16000000: based upon https://github.com/google/sanitizers/issues/856#issuecomment-2749596588
# soft stack set smaller to 400000 in attempt to speed up UBASAN builds, however no performance increase was observed
sudo bash -c "cat << EOF > /etc/security/limits.conf
* soft core unlimited
* hard core unlimited
* soft data unlimited
* hard data unlimited
* soft fsize unlimited
* hard fsize unlimited
* soft memlock unlimited
* hard memlock unlimited
* soft nofile 1048576
* hard nofile 1048576
* soft rss unlimited
* hard rss unlimited
* soft stack 400000
* hard stack 16000000
* soft cpu unlimited
* hard cpu unlimited
* soft nproc unlimited
* hard nproc unlimited
* soft as unlimited
* hard as unlimited
* soft maxlogins unlimited
* hard maxlogins unlimited
* soft maxsyslogins unlimited
* hard maxsyslogins unlimited
* soft locks unlimited
* hard locks unlimited
* soft sigpending unlimited
* hard sigpending unlimited
* soft msgqueue unlimited
* hard msgqueue unlimited
EOF"

if [ "$(grep -m1 '^UserTasksMax=infinity' /etc/systemd/logind.conf)" != 'UserTasksMax=infinity' ]; then
  sudo bash -c 'echo "UserTasksMax=infinity" >> /etc/systemd/logind.conf'
fi
# ^ Support for option UserTasksMax= has been removed in recent versions, instead:
USER_UID="$(id -u $(whoami))"
if [ "$(grep -m1 '^UserTasksMax=infinity' /etc/systemd/system/user-${USER_UID}.slice.d/50-limits.conf 2>/dev/null)" != 'UserTasksMax=infinity' ]; then
  sudo mkdir "/etc/systemd/system/user-${USER_UID}.slice.d"
  sudo bash -c "echo '[Slice]' >> /etc/systemd/system/user-${USER_UID}.slice.d/50-limits.conf"
  sudo bash -c "echo 'UserTasksMax=infinity' >> /etc/systemd/system/user-${USER_UID}.slice.d/50-limits.conf"
fi

# Ensuring nproc limiter is gone or not present
if [ -r /etc/security/limits.d/90-nproc.conf ]; then
  sudo rm -f /etc/security/limits.d/90-nproc.conf
  if [ -r /etc/security/limits.d/90-nproc.conf ]; then
    echo "Tried to remove the file /etc/security/limits.d/90-nproc.conf (to enable raising of nproc) without succes. Exiting prematurely."
    exit 1
  fi
fi

# Reload sysctl.conf file instantly
sudo sysctl -p

# Disable news
sudo sed -i 's|^ENABLED=1|ENABLED=0|' /etc/default/motd-news

# Avoids any local my.cnf etc.
# Note: do not install any database server on testing servers
# Rather, the framework will build/create BASEDIR's (simple tarball based directories containing all required binaries etc.)
# That can be used and started completely independently of each other (with their own socket files, unique TCP/IP port etc.)
sudo mv /etc/mysql /etc/mysql.old 2>/dev/null
sudo mv /etc/alternatives/my.cnf /etc/alternatives/my.old 2>/dev/null
sudo mv /etc/my.cnf /etc/my.old 2>/dev/null

# Add additional repo's
sudo add-apt-repository universe
sudo add-apt-repository multiverse
sudo add-apt-repository restricted

# Recent updates to list:
# Do not add 'terminator' to the list below, as it will install the desktop
# To remove the desktop on 20.04:
# https://askubuntu.com/questions/1233025/how-to-remove-gnome-shell-from-ubuntu-20-04-lts-to-install-other-desktop-environ
# Also removed libcrack2-dev, not sure what tool this lib was required for and not sure what purpose is? Re-add if missing lib problems found later, with updated comment here.

# Install apps for 18.04
#sudo apt install -y build-essential man-db wget patch make cmake automake autoconf bzr git htop lsof gdb gcc libtool bison valgrind strace screen hdparm openssl tree vim yum-utils lshw iotop bats lzma lzma-dev git linux-headers-generic g++ libncurses5-dev libaio1 libaio-dev libjemalloc1 libjemalloc-dev libdbd-mysql libssl-dev subversion libgtest-dev zlib1g zlib1g-dbg zlib1g-dev libreadline-dev libreadline7-dbg debhelper devscripts pkg-config dpkg-dev lsb-release libpam0g-dev libcurl4-openssl-dev libssh-dev fail2ban libz-dev libgcrypt20 libgcrypt20-dev libboost-all-dev python-mysqldb mdm clang libasan5 clang-format libbz2-dev gnutls-dev sysbench bbe libbsd-dev libedit-dev liblz4-dev chrpath dh-apparmor dh-exec dh-systemd libcurl4-openssl-dev libjudy-dev libkrb5-dev libpcre2-dev libsnappy-dev libsystemd-dev libxml2-dev libzstd-dev unixodbc-dev uuid-dev cpufrequtils rr socat libmysqlclient-dev libudev-dev groff

# Install apps for 20.04 & updated for 22.04
sudo apt install build-essential man-db sudo bc perl wget patch make cmake automake autoconf bzr git htop lsof gdb gcc libtool bison valgrind strace screen hdparm openssl tree vim lshw iotop bats lzma lzma-dev git linux-headers-generic g++ libncurses5-dev libaio1 libaio-dev libjemalloc-dev libdbd-mysql libssl-dev libboost-dev subversion libgtest-dev zlib1g libreadline-dev debhelper devscripts pkg-config dpkg-dev lsb-release libpam0g-dev libcurl4-openssl-dev libssh-doc libssh-dev fail2ban libz-dev libgcrypt20 libgcrypt20-dev libboost-all-dev mdm clang libasan5 clang-format libbz2-dev gnutls-dev sysbench bbe libbsd-dev libedit-dev liblz4-dev chrpath dh-apparmor dh-exec dh-systemd libcurl4-openssl-dev libjudy-dev libkrb5-dev libpcre2-dev libsnappy-dev libsystemd-dev libxml2-dev libzstd-dev unixodbc-dev uuid-dev cpufrequtils rr net-tools libasan5 gcc-9 libasan6 gcc-10 socat libmysqlclient-dev libudev-dev libpmem-dev silversearcher-ag groff  # Potentially only libasan6/gcc-10 is required.  # socat is needed for mariabackup  # libpmem-dev is required for -DWITH_PMEM=1  # TODO: to verify: groff is likely required to avoid 'troff: fatal error: can't find macro file m' during compilations (groff is a newer iteration of troff, includes troff, and often resolves troff issues)
# Fixup needed on 20.04 after updates (24/10/2020)  TODO: work in progress
sudo apt purge libasan4 libasan5 libasan6 gcc-7 gcc-8 gcc-9 gcc-10 gcc c-compiler
sudo apt autoremove
sudo apt install libasan6 gcc-9 g++-9 gcc g++ build-essential  # logout login  - drop gcc
sudo apt install libasio-dev check scons libboost-program-options-dev libboost-dev libssl-dev  # For Galera
sudo apt install libubsan1  # Added here, mostly as a reminder it is required for UBSAN testing; should be installed already

# Packages so far not available on 20.04:
# yum-utils: removed ftm
# libjemalloc1: not needed?
# zlib1g-dev: removed as it is auto-selected by libz-dev
# zlib1g-dbg: not available, but referred by another package, not needed [anymore?]
# libreadline7-dbg: libreadline-dev is present, which may be sufficient
# python-mysqldb: replacement?

sudo apt install libdata-dumper-simple-perl  # Required by mysql_install_db

# rr claimes to require perf on machines where it does not work, yet on rr server it works without having perf installed. Besides requiring or not requiring it, it is a handy tool to have.
# To use perf, do:  sudo perf top -p <pid_of_mysqld>  # And allow some time to sample
# Update: it was found that the reason is does not work is that the instances where it did not work was tht the guest CPU type property was empty (likely in the vm hypervisor or similar). Adding all possible guest CPU types (long list) resolved the issue. Bare metal also works without issues. dmesg | grep PMU can help to debug. The first one below is where software mode is enabled only, the second correctly recognizes the CPU and hence rr will work:
# Performance Events: unsupported p6 CPU model 94 no PMU driver, software events only.  # rr will fail, software VM
# Performance Events: Skylake events, Intel PMU driver.  # rr will work, correct cpu type

sudo apt install --reinstall linux-tools-common linux-tools-generic linux-tools-`uname -r`
# rr server Tuning (and perf)
if [ "${1}" == "rr" ]; then
  sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
  sudo sed -i 's|^#RemoveIPC=yes|RemoveIPC=no|' /etc/systemd/logind.conf; sudo systemctl restart systemd-logind.service
  if [ -r /etc/apt/apt.conf.d/20auto-upgrades ]; then
    sudo sed -i 's|Unattended-Upgrade "1"|Unattended-Upgrade "0"|' /etc/apt/apt.conf.d/20auto-upgrades
  if [ -r /etc/apt/apt.conf.d/50unattended-upgrades ]; then
    sudo sed -i 's|Unattended-Upgrade "1"|Unattended-Upgrade "0"|' /etc/apt/apt.conf.d/50unattended-upgrades
  fi
  sudo sed -i 's|vm.swappiness=5|vm.swappiness=1|'  /etc/sysctl.conf
  # Performance mode not necessary ftm it seems on 20.04, may be required on 18.04 for rr to work properly
  # In any case, still good to set on any test machine to achieve max QPS for testing? TODO
  #sudo bash -c 'echo "GOVERNOR=\"performance\"" >> /etc/default/cpufrequtils' && sudo systemctl restart cpufrequtils
  if [ "$(grep -m1 '^kernel.perf_event_paranoid=1' /etc/sysctl.conf)" != 'kernel.perf_event_paranoid=1' ]; then
    sudo bash -c 'echo "kernel.perf_event_paranoid=1" >> /etc/sysctl.conf' && sudo sysctl -p
  fi
fi

echo ""
echo "MariaDB QA Testing servers (pquery framework or squirrel fuzzer framework, both present in mariadb-qa) require a large"
echo "tmpfs space to be able to run much of the testing in memory. You should scale the tmpfs size to the memory size."
echo "As a guide, with ~120GB of memory you will want a tmpfs size of ~95GB. Below is a reference example of /etc/fstab"
echo "You can now edit/update your /etc/fstab as required. Some other optimizations for speed are made like noatime, etc."
echo "----------------------------------------------------------------------------------------------------------------"
echo "LABEL=somerootlabel                       /         ext4  defaults 0 0"
echo "LABEL=UEFI                                /boot/efi vfat  defaults 0 0"
echo "UUID=someuuid-uuid-uuid-uuid-uuidsomeuuid /data     ext4  defaults,discard,noatime,nofail 0 2"
echo "tmpfs                                     /dev/shm  tmpfs defaults,rw,nosuid,nodev,noatime,nofail,size=95G 0 0"
echo "/swapfile                                 swap      swap  defaults,sw,nofail 0 0"
echo "----------------------------------------------------------------------------------------------------------------"
echo "Note: do not blindly copy/paste the above, interpretation is required like changing the tmpfs size and the LABEL's"
echo ""
echo "Create the swapfile as follows:"
echo "  sudo fallocate -l 60G /swapfile"
echo "  sudo chmod 600 /swapfile"
echo "  sudo mkswap /swapfile"
echo "  sudo swapon /swapfile"
echo ""
echo "Then add the /swapfile line to the /etc/fstab file as shown above"
echo "Note that the swapfile (/swapfile) and tmpfs (/dev/shm) are two different items"
echo "Note that on some systems the first 'swap' after '/swapfile' should be 'none' instead (i.e. /swapfile none swap...)"
echo ""
echo "To set timezone per-user, do:"
echo "echo 'export TZ=\"/usr/share/zoneinfo/Australia/Sydney\"' >> ~/.basrc"
