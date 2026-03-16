#!/bin/sh
set -e

# Select site config based on SSL mode
if [ "${REVERSE_PROXY:-false}" = "true" ]; then
    cp /etc/nginx/conf.d/site.conf.no-ssl /etc/nginx/conf.d/site.conf
fi

# Generate the active server_name config from template
envsubst < /etc/nginx/conf.d/templates/server_name.template > /etc/nginx/conf.d/server_name.active

if [ "${REVERSE_PROXY:-false}" != "true" ]; then
    # Wait for SSL certificates to be provided by the acme container.
    # On first start the certs volume is empty; acme writes the files shortly after launch.
    echo "Waiting for SSL certificates ..."
    while [ ! -f "/certs/fullchain.pem" ] || [ ! -f "/certs/privkey.pem" ] || [ ! -f "/certs/dhparams.pem" ]; do
        sleep 2
    done
    echo "Certificates found, starting nginx."
fi

# Start nginx in the background so we can watch for cert changes
nginx -g 'daemon off;' &
NGINX_PID=$!

if [ "${REVERSE_PROXY:-false}" != "true" ]; then
    # Record the initial cert fingerprint
    CERT_HASH=$(md5sum /certs/fullchain.pem | cut -d' ' -f1)

    # Watch for certificate renewal every 60 seconds and reload nginx when changed.
    # This replaces the previous approach of restarting the container via the Docker socket.
    while kill -0 "$NGINX_PID" 2>/dev/null; do
        sleep 60
        NEW_HASH=$(md5sum /certs/fullchain.pem 2>/dev/null | cut -d' ' -f1)
        if [ -n "$NEW_HASH" ] && [ "$NEW_HASH" != "$CERT_HASH" ]; then
            CERT_HASH="$NEW_HASH"
            echo "Certificate changed, reloading nginx ..."
            nginx -s reload 2>/dev/null || true
        fi
    done
else
    # In reverse proxy mode just wait for nginx to exit
    while kill -0 "$NGINX_PID" 2>/dev/null; do
        sleep 60
    done
fi

wait "$NGINX_PID"
