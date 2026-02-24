# fewohbee-dockerized

This docker compose setup is part of the [fewohbee guesthouse administration tool](https://github.com/developeregrem/fewohbee). It provides all necessary services to run fewohbee out of the box.

## Services

| Service | Image | Description |
|---------|-------|-------------|
| `web` | [nginx](https://hub.docker.com/_/nginx/) | Web server |
| `php` | [fewohbee-phpfpm](https://github.com/developeregrem/fewohbee-phpfpm) | PHP 8 FPM – clones and runs the app on first start |
| `cron` | [fewohbee-phpcli](https://github.com/developeregrem/fewohbee-phpfpm) | PHP CLI for scheduled tasks |
| `db` | [mariadb](https://hub.docker.com/_/mariadb) | Database |
| `redis` | [redis](https://hub.docker.com/_/redis) | In-memory cache |
| `acme` | [fewohbee-acme](https://github.com/developeregrem/fewohbee-acme) | SSL certificate management (Let's Encrypt or self-signed) |

## Configuration

All settings are stored in a single `.env` file. Use `.env.dist` as the reference template.

## Setup

### Option A – Setup container (recommended, all platforms)

Works on Linux, macOS and Windows — requires only Docker.

```sh
# Clone the repository first
git clone https://github.com/developeregrem/fewohbee-dockerized.git
cd fewohbee-dockerized

# Linux / macOS
docker run --rm -it -v $(pwd):/config developeregrem/fewohbee-setup

# Windows PowerShell
docker run --rm -it -v ${PWD}:/config developeregrem/fewohbee-setup
```

The container asks a few questions (hostname, SSL mode, language), generates passwords and writes `.env`.

### Option B – install.sh (Linux only)

A Bash script that additionally sets up optional cron jobs for database backups and automatic updates:

```sh
git clone https://github.com/developeregrem/fewohbee-dockerized.git
cd fewohbee-dockerized
chmod +x install.sh
sudo ./install.sh
```

## Starting the application

### Standard mode (with SSL)

For servers with direct internet access. Manages SSL certificates automatically via the `acme` container (self-signed or Let's Encrypt).

```sh
docker compose up -d
```

### Reverse proxy mode (no internal SSL)

For deployments behind an external reverse proxy (Traefik, Nginx Proxy Manager, Caddy, etc.) that handles SSL termination. No `acme` container — the web container serves plain HTTP.

Set `COMPOSE_FILE=docker-compose.no-ssl.yml` in `.env` (done automatically by the setup scripts when choosing `reverse-proxy`) and then:

```sh
docker compose up -d
```

Configure the exposed HTTP port via `LISTEN_PORT` in `.env` (default: `80`).

## First-run initialisation

After starting the stack, the PHP container clones the app and installs dependencies (~2 minutes). Monitor progress:

```sh
docker compose logs -f php
```

Once `ready to handle connections` appears, run once to create the first admin user:

```sh
docker compose exec --user www-data php /bin/sh -c "php fewohbee/bin/console app:first-run"
```

## Updates

```sh
chmod +x update-docker.sh
./update-docker.sh
```

The script pulls new images, restarts the stack and automatically syncs any new environment variables into `.env` and both compose files. New variables should be reviewed and adjusted after the update.

## Documentation

Full setup and configuration documentation:
[https://github.com/developeregrem/fewohbee/wiki/Docker-Setup](https://github.com/developeregrem/fewohbee/wiki/Docker-Setup)
