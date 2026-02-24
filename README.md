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

Two configuration files are required before starting the stack:

| File | Contents |
|------|----------|
| `.env` | Infrastructure settings: hostname, database passwords, SSL/cert options |
| `.env.app` | Application settings: locale, mailer, passkeys, app secret, … |

Use `.env.dist` and `.env.app.dist` as reference templates.

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

The container asks a few questions (hostname, SSL mode, language), generates passwords and writes `.env` and `.env.app`.

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

```sh
docker compose -f docker-compose.no-ssl.yml up -d
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

Optional: load sample data (guests, reservations, invoices)

```sh
docker compose exec --user www-data php sh -c 'php fewohbee/bin/console doctrine:fixtures:load --append --group settings --group customer --group reservation --group invoices'"
```
## Updates

```sh
chmod +x update-docker.sh
./update-docker.sh
```

The script pulls new images, restarts the stack and automatically syncs any new application environment variables into `.env.app`. New variables should be reviewed and adjusted after the update.

## Documentation

Full setup and configuration documentation:
[https://github.com/developeregrem/fewohbee/wiki/Docker-Setup](https://github.com/developeregrem/fewohbee/wiki/Docker-Setup)
