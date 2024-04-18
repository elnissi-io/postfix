FROM debian:bullseye-slim

ARG APT_POSTFIX_VERSION
ARG DOCKER_POSTFIX_VERSION
# Prevent apt from prompting during install
ENV DEBIAN_FRONTEND=noninteractive

# Optionally use the Docker-specific version in labels or for other purposes
LABEL postfix_version=$DOCKER_POSTFIX_VERSION


# Install all dependencies in one layer to keep image size down
RUN apt-get update --quiet --quiet && \
    apt-get upgrade --quiet --quiet -y && \
    apt-get install --quiet --quiet --yes --no-install-recommends --no-install-suggests \
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
    apt-get --quiet --quiet clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    wget https://github.com/mikefarah/yq/releases/download/v4.43.1/yq_linux_amd64 -O /usr/bin/yq && \
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
