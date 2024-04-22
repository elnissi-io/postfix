#!/bin/bash
set -e

# Define and export environment variables
export ARCHIVE_USER="${ARCHIVE_USER:-archive}"
export PRIMARY_DOMAIN="${PRIMARY_DOMAIN:-example.com}"
export AUTHS_FILE="${AUTHS_FILE:-/config/auths.yaml}"
export SSL_CERT_FILE="${SSL_CERT_FILE:-/config/certs/fullchain.pem}"
export SSL_KEY_FILE="${SSL_KEY_FILE:-/config/certs/privkey.pem}"
export RELAY_IP="${RELAY_IP:-}"
export OPENDKIM_DEFAULT_SELECTOR="${OPENDKIM_DEFAULT_SELECTOR:-mail}"
export OPENDKIM_KEYS_DIR="${OPENDKIM_KEYS_DIR:-/etc/opendkim/keys}"

# Echo out variables after setting defaults (for debugging purposes)
echo "After setting defaults:"
echo "ARCHIVE_USER=$ARCHIVE_USER"
echo "PRIMARY_DOMAIN=$PRIMARY_DOMAIN"
echo "AUTHS_FILE=$AUTHS_FILE"
echo "SSL_CERT_FILE=$SSL_CERT_FILE"
echo "SSL_KEY_FILE=$SSL_KEY_FILE"
echo "RELAY_IP=$RELAY_IP"
echo "OPENDKIM_DEFAULT_SELECTOR=$OPENDKIM_DEFAULT_SELECTOR"
echo "OPENDKIM_KEYS_DIR=$OPENDKIM_KEYS_DIR"

# Continue with the script logic...

setup_ssl_certificates() {
  echo "Checking SSL certificates..."
  if [[ ! -f "$SSL_CERT_FILE" || ! -f "$SSL_KEY_FILE" ]]; then
    echo "SSL certificates not found. Generating self-signed certificates..."
    
    # Extract the directory paths from the file paths
    ssl_cert_dir=$(dirname "$SSL_CERT_FILE")
    ssl_key_dir=$(dirname "$SSL_KEY_FILE")

    # Create directories if they do not exist
    [ ! -d "$ssl_cert_dir" ] && mkdir -p "$ssl_cert_dir"
    [ ! -d "$ssl_key_dir" ] && mkdir -p "$ssl_key_dir"

    echo "Directories for SSL certificates and keys have been ensured."
    openssl req -x509 -newkey rsa:4096 -keyout "$SSL_KEY_FILE" -out "$SSL_CERT_FILE" \
      -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Organization/CN=${PRIMARY_DOMAIN}"
    chown root:root "$SSL_CERT_FILE" "$SSL_KEY_FILE"
    chmod 600 "$SSL_KEY_FILE"
    echo "SSL certificates generated."
  else
    echo "Using provided SSL certificates."
  fi
}

update_ssl_configurations() {
  echo "Updating SSL configurations for services..."
  sed -i "s|ssl_cert = <.*|ssl_cert = <${SSL_CERT_FILE}|" /etc/dovecot/dovecot.conf
  sed -i "s|ssl_key = <.*|ssl_key = <${SSL_KEY_FILE}|" /etc/dovecot/dovecot.conf
  
  sed -i "s|smtpd_tls_cert_file=.*|smtpd_tls_cert_file=${SSL_CERT_FILE}|" /etc/postfix/main.cf
  sed -i "s|smtpd_tls_key_file=.*|smtpd_tls_key_file=${SSL_KEY_FILE}|" /etc/postfix/main.cf
}


generate_configs() {
  echo "Generating configurations for ${PRIMARY_DOMAIN}..."
  
  # Postfix configurations
  envsubst '\$PRIMARY_DOMAIN \$RELAY_IP \$ARCHIVE_USER \$EXTENSION \$SSL_CERT_FILE \$SSL_KEY_FILE' < /config/templates/main.cf.tmpl > /etc/postfix/main.cf
  envsubst '\$PRIMARY_DOMAIN \$RELAY_IP' < /config/templates/master.cf.tmpl > /etc/postfix/master.cf
  
  # OpenDKIM configurations
  setup_opendkim
  
  # OpenDMARC configurations
  setup_opendmarc
  
  # Dovecot configurations
  envsubst '\$SSL_CERT_FILE \$SSL_KEY_FILE' < /config/templates/dovecot.conf.tmpl > /etc/dovecot/dovecot.conf

  echo "All configurations generated for ${PRIMARY_DOMAIN}"
}


setup_opendkim() {
  echo "Setting up OpenDKIM..."
  if [[ -d "${OPENDKIM_KEYS_DIR}/${PRIMARY_DOMAIN}" ]]; then
    envsubst '\$PRIMARY_DOMAIN \$OPENDKIM_DEFAULT_SELECTOR' < /config/templates/opendkim.conf.tmpl > /etc/opendkim.conf
    cat /etc/opendkim.conf
    envsubst '\$PRIMARY_DOMAIN \$RELAY_IP' < /config/templates/TrustedHosts.tmpl > /etc/opendkim/TrustedHosts
    echo 'SOCKET="inet:12301"' >> /etc/default/opendkim
    chown -R opendkim:opendkim /etc/opendkim
  else
    echo "OpenDKIM key directory for ${PRIMARY_DOMAIN} not found. Ensure the keys are in place or update OPENDKIM_KEYS_DIR if necessary."
    echo "Make sure ${OPENDKIM_KEYS_DIR}/${PRIMARY_DOMAIN}/${OPENDKIM_DEFAULT_SELECTOR}.private exists."
  fi
}

setup_opendmarc() {
  echo "Setting up OpenDMARC..."
  mkdir -p "/etc/opendmarc/"
  envsubst '\$PRIMARY_DOMAIN \$RELAY_IP' < /config/templates/opendmarc.conf.tmpl > /etc/opendmarc.conf
  echo "localhost" > /etc/opendmarc/ignore.hosts
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
    
    setup_ssl_certificates
    [[ ! -f ok || $(< ok) != "${PRIMARY_DOMAIN}" ]] && generate_configs && echo "${PRIMARY_DOMAIN}" > ok
    update_ssl_configurations
    generate_users



    echo "--------------------------------------------------------------------------------------------------------"
    echo "You can generate the p record (public key) by executing:"
    echo "--------------------------------------------- COMMAND --------------------------------------------------"
    echo "  openssl rsa -in "${OPENDKIM_KEYS_DIR}/${PRIMARY_DOMAIN}/${OPENDKIM_DEFAULT_SELECTOR}.private" --pubout"
    echo "--------------------------------------------------------------------------------------------------------"
    echo "Please ensure the following DNS TXT records are configured for OpenDKIM:"
    echo "v=DKIM1; h=sha256; k=rsa; p=<PUBLIC_KEY>"
    echo "--------------------------------------------------------------------------------------------------------"

    # Ensure postfix has access to necessary system files
    cp /etc/{hosts,localtime,nsswitch.conf,resolv.conf,services} /var/spool/postfix/etc/


    dovecot
    opendmarc
    opendkim
    exec "$@"
  fi
}

main "$@"
