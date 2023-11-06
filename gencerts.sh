#!/bin/bash

if [ ! -d ./certs ]; then
  mkdir ./certs
  if [ ! -d ./certs ]; then
    echo "Assert: could not create ./certs"
    exit 1
  fi
fi
cd ./certs

# Cleanup old certificates  # TAKE CARE BEFORE RUNNING THIS SCRIPT AS IT WILL DELETE ALL *.pem files
rm -f *.pem

# The CN for the server and client certs/keys must differ from the CN used for the CA. If not done correctly, the certs will not work for servers compiled using OpenSSL. Thus, notice the 'MYCA' in CA_CONFIG's CN.
CA_CONFIG="/C=AU/ST=NSW/L=SYDNEY/O=MARIADB/OU=IT/CN=MYCA/emailAddress=address@email.com"

SERVER_CONFIG="/C=AU/ST=NSW/L=SYDNEY/O=MARIADB/OU=IT/CN=$(cat /etc/hostname | tr -d '\n')/emailAddress=address@email.com"
CLIENT_CONFIG="/C=AU/ST=NSW/L=SYDNEY/O=MARIADB/OU=IT/CN=$(cat /etc/hostname | tr -d '\n')/emailAddress=address@email.com"
# Other options
#SERVER_CONFIG="/C=AU/ST=NSW/L=SYDNEY/O=MARIADB/OU=IT/CN=127.0.0.1/emailAddress=address@email.com"
#CLIENT_CONFIG="/C=AU/ST=NSW/L=SYDNEY/O=MARIADB/OU=IT/CN=127.0.0.1/emailAddress=address@email.com"
#SERVER_CONFIG="/C=AU/ST=NSW/L=SYDNEY/O=MARIADB/OU=IT/CN=localhost/emailAddress=address@email.com"
#CLIENT_CONFIG="/C=AU/ST=NSW/L=SYDNEY/O=MARIADB/OU=IT/CN=localhost/emailAddress=address@email.com"

# new ca-key
openssl genrsa 2048 > ca-key.pem
openssl req -new -x509 -nodes -days 9999 -key ca-key.pem -subj "${CA_CONFIG}" > ca-cert.pem

# server certs
openssl req -new -newkey rsa:2048 -nodes -keyout server-key.pem -subj "${SERVER_CONFIG}" -out server-req.pem
openssl x509 -req -in server-req.pem -days 3600 -CA ca-cert.pem -CAkey ca-key.pem -set_serial 01 -out server-cert.pem

# client certs
openssl req -newkey rsa:2048 -nodes -keyout client-key.pem -subj "${CLIENT_CONFIG}" -out client-req.pem
openssl x509 -req -in client-req.pem -days 3600 -CA ca-cert.pem -CAkey ca-key.pem -set_serial 02 -out client-cert.pem

# verify certs
openssl verify -CAfile ca-cert.pem server-cert.pem client-cert.pem

# Check files
ls -l *.pem

# Check certs
openssl x509 -noout -subject -in ca-cert.pem
openssl x509 -noout -subject -in server-cert.pem
openssl x509 -noout -subject -in client-cert.pem
