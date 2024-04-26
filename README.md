# postfix-docker 📮🐳 #

Creates a Docker container with an installation of the [postfix](http://postfix.org) MTA.
All email is BCC'd to the `archive` account.

## Running ##

### Running with Docker ###

To run the `/postfix` image via Docker:

```console
docker run quay.io/elnissi-io/postfix:0.0.4
```

### Running with Docker Compose ###

1. Create a `docker-compose.yml` file similar to the one below to use [Docker Compose](https://docs.docker.com/compose/)
or use the [sample `docker-compose.yml`](docker-compose.yml) provided with
this repository.

```yaml
---
services:
  postfix:
    image: quay.io/elnissi-io/postfix
    init: true
    restart: always
    environment:
      PRIMARY_DOMAIN: example.com
      RELAY_IP: 172.16.202.1/32
      AUTHS_FILE: /config/auths.yaml
    networks:
      front:
        ipv4_address: 172.16.202.2
    ports:
      - "25:25/tcp"
    secrets:
      - ssl_cert
      - ssl_key

secrets:
  ssl_cert:
    file: ./config/certs/fullchain.pem
  ssl_key:
    file: ./config/certs/privkey.pem

networks:
  front:
    driver: bridge
    ipam:
      config:
        - subnet: 172.16.202.0/24
```

1. Start the container and detach:

```console
docker compose up --detach
```

## Volumes ##

| Mount point | Purpose |
|-------------|---------|
| `/var/log` | System logs |
| `/var/spool/postfix` | Mail queues |

## Ports ##

The following ports are exposed by this container:

| Port | Purpose        |
|------|----------------|
| 25 | SMTP relay |

The sample [Docker composition](docker-compose.yml) publishes the
exposed ports at 1025, 1587, and 1993, respectively.

## Environment variables ##

### Required ###

| Name  | Purpose |
|-------|---------|
| `PRIMARY_DOMAIN` | The primary domain of the mail server. |

### Optional ###

| Name  | Purpose | Default |
|-------|---------|---------|
| `RELAY_IP` | An IP address or CIDR range that is allowed to relay mail without authentication. | `null` |
| `EXTENSION` | An IP address that is allowed to relay mail without authentication. | `null` |

## Contributing ##

Contributions are welcome.
Please see [`CONTRIBUTING.md`](CONTRIBUTING.md) for details.

## License ##

Licensed under the MIT License.