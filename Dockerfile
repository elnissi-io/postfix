FROM debian:bullseye-slim

# Prevent apt from prompting during install
ENV DEBIAN_FRONTEND=noninteractive

# Update and install all necessary packages including curl
RUN apt-get update --quiet --quiet && \
    apt-get install --quiet --quiet --yes --no-install-recommends --no-install-suggests \
    curl \
    ca-certificates \
    diceware \
    #dovecot-imapd \
    #dovecot-lmtpd \
    gettext-base \
    mailutils \
    sasl2-bin \
    libsasl2-2 \
    libsasl2-dev \
    libsasl2-modules \
    libsasl2-modules \
    opendkim \
    opendkim-tools \
    opendmarc \
    postfix-pcre \
    procmail \
    sasl2-bin && \
    # Clean up APT when done to reduce image size
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*


# Download yq and set permissions
RUN curl -sL https://github.com/mikefarah/yq/releases/download/v4.43.1/yq_linux_amd64 -o /usr/bin/yq && \
    chmod +x /usr/bin/yq

# Create a non-privileged user for mail handling
RUN useradd -r -s /usr/sbin/nologin -c "Mail Archive" archive

RUN adduser noreply
RUN adduser noreply sasl && adduser postfix sasl

# Add 'opendkim' group and 'opendkim' user
RUN groupadd -r opendkim && useradd -r -g opendkim -d /var/run/opendkim -s /usr/sbin/nologin -c "OpenDKIM" opendkim

# Set appropriate permissions and ownership for OpenDKIM directories
RUN mkdir -p /etc/opendkim /var/run/opendkim && \
    chown -R opendkim:opendkim /etc/opendkim /var/run/opendkim && \
    chmod -R 750 /etc/opendkim /var/run/opendkim

WORKDIR /root

COPY config/ /config
COPY entrypoint.sh entrypoint.sh

VOLUME ["/var/log", "/var/spool/postfix"]
EXPOSE 25 587 993

ENTRYPOINT ["./entrypoint.sh"]
CMD ["postfix", "-v","start-fg"]
