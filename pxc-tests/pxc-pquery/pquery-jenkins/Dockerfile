FROM pqueryjenkins
WORKDIR /
RUN mkdir mysql
RUN wget https://downloads.mariadb.com/MariaDB/mariadb-10.3.31/bintar-linux-systemd-x86_64/mariadb-10.3.31-linux-systemd-x86_64.tar.gz
RUN tar -xzf mariadb-10.3.31-linux-systemd-x86_64.tar.gz -C /mysql --strip-components=1
RUN groupadd -r mysql
RUN useradd -M -r -d /var/lib/mysql -s /bin/bash  -g mysql mysql
RUN /mysql/scripts/mysql_install_db --basedir=/mysql --user=mysql
EXPOSE 3306 4567 4568
