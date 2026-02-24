FROM nginx:mainline-alpine

COPY . /etc/nginx/conf.d/

# Remove the default nginx config (replaced by site.conf) and the runtime-generated file
RUN rm -f /etc/nginx/conf.d/default.conf \
    /etc/nginx/conf.d/server_name.active \
    && chmod +x /etc/nginx/conf.d/docker-entrypoint.sh

ENTRYPOINT ["/bin/sh", "/etc/nginx/conf.d/docker-entrypoint.sh"]
