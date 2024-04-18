#!/bin/bash

set -e
#set -x

# Default values for environment variables
: "${ARCHIVE_USER:=archive}"
: "${PRIMARY_DOMAIN:=example.com}"
: "${AUTHS_FILE:=/config/auths.yaml}"
: "${SSL_CERT_PATH:=/config/certs/fullchain.pem}"
: "${SSL_KEY_PATH:=/config/certs/privkey.pem}"
: "${RELAY_IP:=}"

setup_dovecot_ssl() {
  echo "Setting up SSL for Dovecot..."
  if [[ ! -f "$SSL_CERT_PATH" || ! -f "$SSL_KEY_PATH" ]]; then
    echo "SSL certificates not found. Generating self-signed certificates..."
    openssl req -x509 -newkey rsa:4096 -keyout "$SSL_KEY_PATH" -out "$SSL_CERT_PATH" \
      -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Organization/CN=${PRIMARY_DOMAIN}"
    chown root:root "$SSL_CERT_PATH" "$SSL_KEY_PATH"
    chmod 600 "$SSL_KEY_PATH"
  else
    echo "Using provided SSL certificates."
  fi

  # Updating Dovecot's configuration with new paths
  sed -i "s|ssl_cert = <.*|ssl_cert = <${SSL_CERT_PATH}|" /etc/dovecot/dovecot.conf
  sed -i "s|ssl_key = <.*|ssl_key = <${SSL_KEY_PATH}|" /etc/dovecot/dovecot.conf
}

generate_configs() {
  echo "Generating configurations for ${PRIMARY_DOMAIN}..."
  
  # Postfix configurations
  envsubst '\$PRIMARY_DOMAIN \$RELAY_IP' < templates/main.cf.tmpl > /etc/postfix/main.cf
  cp /etc/postfix/master.cf.orig /etc/postfix/master.cf
  envsubst '\$PRIMARY_DOMAIN \$RELAY_IP' < templates/master.cf.tmpl >> /etc/postfix/master.cf
  
  # OpenDKIM configurations
  setup_opendkim
  
  # OpenDMARC configurations
  setup_opendmarc
  
  # Dovecot configurations
  envsubst '\$PRIMARY_DOMAIN \$RELAY_IP' < templates/dovecot.conf.tmpl > /etc/dovecot/dovecot.conf

  echo "All configurations generated for ${PRIMARY_DOMAIN}"
}

setup_opendkim() {
  echo "Setting up OpenDKIM..."
  mkdir -p "/etc/opendkim/keys/${PRIMARY_DOMAIN}"
  opendkim-genkey --verbose --bits=1024 --selector=mail --directory="/etc/opendkim/keys/${PRIMARY_DOMAIN}"
  envsubst '\$PRIMARY_DOMAIN \$RELAY_IP' < templates/opendkim.conf.tmpl > /etc/opendkim.conf
  cp /etc/default/opendkim.orig /etc/default/opendkim
  echo 'SOCKET="inet:12301"' >> /etc/default/opendkim
  chown -R opendkim:opendkim /etc/opendkim
}

setup_opendmarc() {
  echo "Setting up OpenDMARC..."
  mkdir -p "/etc/opendmarc/"
  envsubst '\$PRIMARY_DOMAIN \$RELAY_IP' < templates/opendmarc.conf.tmpl > /etc/opendmarc.conf
  echo "localhost" > /etc/opendmarc/ignore.hosts
  cp /etc/default/opendmarc.orig /etc/default/opendmarc
  echo 'SOCKET="inet:54321"' >> /etc/default/opendmarc
  chown -R opendmarc:opendmarc /etc/opendmarc
}

generate_users() {
  echo "Generating users from ${AUTHS_FILE}..."
  yq e '.auths[]' "$AUTHS_FILE" | while read -r auth; do
    username=$(echo "$auth" | yq e '.username' -)
    password=$(echo "$auth" | yq e '.password' -)

    if [[ -n "$username" && -n "$password" ]]; then
      adduser "$username" --quiet --disabled-password --shell /usr/sbin/nologin --gecos "" --force-badname || true
      echo "$username:$password" | chpasswd || true
    else
      echo "Missing username or password for an entry, skipping..."
    fi
  done
}

main() {
  if [ "$1" = 'postfix' ]; then
    echo "Starting mail server with PRIMARY_DOMAIN=${PRIMARY_DOMAIN} and RELAY_IP=${RELAY_IP}"
    
    setup_dovecot_ssl
    [[ ! -f ok || $(< ok) != "${PRIMARY_DOMAIN}" ]] && generate_configs && echo "${PRIMARY_DOMAIN}" > ok
    generate_users

    # Ensure postfix has access to necessary system files
    cp /etc/{hosts,localtime,nsswitch.conf,resolv.conf,services} /var/spool/postfix/etc/

    echo "DKIM DNS entry:"
    cat "/etc/opendkim/keys/${PRIMARY_DOMAIN}/mail.txt"

    opendmarc
    opendkim
    dovecot
    exec "$@"
  fi
}

main "$@"
