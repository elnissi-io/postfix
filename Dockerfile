FROM debian:bullseye-slim

# Prevent apt from prompting during install
ENV DEBIAN_FRONTEND=noninteractive

# Update and install all necessary packages including wget
RUN apt-get update --quiet --quiet && \
    apt-get install --quiet --quiet --yes --no-install-recommends --no-install-suggests \
    wget \
    ca-certificates \
    diceware \
    dovecot-imapd \
    dovecot-lmtpd \
    gettext-base \
    mailutils \
    opendkim \
    opendkim-tools \
    opendmarc \
    postfix \
    procmail \
    sasl2-bin && \
    # Clean up APT when done to reduce image size
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Download yq and set permissions
RUN wget https://github.com/mikefarah/yq/releases/download/v4.43.1/yq_linux_amd64 -O /usr/bin/yq && \
    chmod +x /usr/bin/yq

# Create a non-privileged user for mail handling
RUN useradd -r -s /usr/sbin/nologin -c "Mail Archive" archive

WORKDIR /root

COPY config config
COPY entrypoint.sh entrypoint.sh

VOLUME ["/var/log", "/var/spool/postfix"]
EXPOSE 25 587 993

ENTRYPOINT ["./entrypoint.sh"]
CMD ["postfix", "-v", "start-fg"]
