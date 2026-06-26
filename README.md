# fewohbee-dockerized

This docker compose setup is part of the [fewohbee guesthouse administration tool](https://github.com/developeregrem/fewohbee). It provides all necessary services to run fewohbee out of the box.

## Services

| Service | Image | Description |
|---------|-------|-------------|
| `web` | `ghcr.io/developeregrem/fewohbee-nginx` | nginx web server (app assets baked in) |
| `php` | `ghcr.io/developeregrem/fewohbee-phpfpm` | PHP 8 FPM with the app pre-built |
| `cron` | `ghcr.io/developeregrem/fewohbee-cli` | PHP CLI + crond for scheduled tasks |
| `db` | [mariadb](https://hub.docker.com/_/mariadb) | Database |
| `redis` | [redis](https://hub.docker.com/_/redis) | In-memory cache |
| `acme` | `developeregrem/fewohbee-acme` | SSL certificate management (Let's Encrypt or self-signed) |

The images are versioned via the `FEWOHBEE_VERSION` variable in `.env` (default: `latest`). Pin to a specific release (`4.6.0`), branch (`branch-feature-x`) or debug build (`4.6.0-debug`).

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

The full stack reaches a healthy state in roughly 30–60 seconds on a typical server (db takes ~10–15 s to initialize, php-fpm boots and runs Doctrine migrations afterwards). The app code is pre-built into the image — no runtime clone. Wait until the `php` container is reported as `healthy`:

```sh
docker compose ps
```

Then run once to create the first admin user, load base templates and optionally sample data:

```sh
docker compose exec --user www-data php /bin/sh -c "php bin/console app:first-run"
```

## Updates

```sh
chmod +x update-docker.sh
./update-docker.sh
```

The script pulls new images, restarts the stack and automatically syncs any new environment variables into `.env` and both compose files. New variables should be reviewed and adjusted after the update.

### Updating from a legacy install

When upgrading from an older `developeregrem/fewohbee-*` Docker Hub setup (with the runtime git clone), the new compose file includes a one-shot `uploads-migration` init container. It runs automatically on **every** `docker compose up` — no matter whether you trigger it through `update-docker.sh`, Portainer's stack redeploy, or plain `docker compose` on Windows. It copies your user uploads from the legacy `feb-data` volume into the new `uploads-export` and `uploads-roomcat` volumes once, then exits. The legacy `feb-data` volume is kept intact for rollback — you can remove it manually after verifying everything works:

```sh
docker volume rm fewohbee-dockerized_feb-data
```

## Debug builds

Each release has a corresponding `-debug` image with xdebug and dev dependencies. The image carries its own `APP_ENV=dev` setting — you only need to switch the tag:

```sh
# in .env
FEWOHBEE_VERSION=4.6.0-debug
```

Then `docker compose up -d --force-recreate php`.

## Documentation

Full setup and configuration documentation:
[Docker-Setup](https://github.com/developeregrem/fewohbee/wiki/Docker-Setup) and [Portainer-Setup](https://github.com/developeregrem/fewohbee/wiki/Portainer)
