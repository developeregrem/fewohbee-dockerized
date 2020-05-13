#!/bin/sh

privkey=/certs/privkey.pem
certfile=/certs/fullchain.pem

restart_containers(){
    containers=`curl -gGs --unix-socket /var/run/docker.sock http://${DOCKER_API_VERSION}/containers/json?all=true --data-urlencode 'filters={"label":{"com.docker.compose.service=web":true}}' | jq -r .[].Id`

    for container in $containers; do
        curl --unix-socket /var/run/docker.sock -X POST http:/${DOCKER_API_VERSION}/containers/$container/restart
    done
}

selfsignedcert(){
    cn="'/CN=${HOST_NAME}'"    
    eval openssl req -subj $cn -x509 -nodes -days 365 -newkey rsa:2048 -keyout $privkey -out $certfile
    restart_containers
}

letsencryptcert(){
    echo "Letsencryptcert"
    if [ "${DYNDNS_PROVIDER}" = "desec.io" ]
    then
        certbot --manual --non-interactive --agree-tos --manual-public-ip-logging-ok --renew-by-default --email "${EMAIL}" --manual-auth-hook /hook.sh --manual-cleanup-hook /hook.sh \
        --preferred-challenges dns -d "${DEDYN_NAME}" certonly 
    else
        certbot certonly \
    	    --agree-tos \
    	    --webroot \
    	    -w /var/www \
    	    -d ${HOST_NAME} \
    	    --renew-by-default \
    	    --quiet \
    	    --email "${EMAIL}"
    fi

        
    cp /etc/letsencrypt/live/${HOST_NAME}/fullchain.pem /certs
    cp /etc/letsencrypt/live/${HOST_NAME}/privkey.pem /certs
    restart_containers
}

method=""

if [ "${LETSENCRYPT}" = "true" ]
then
    method=letsencryptcert
elif [ "${SELF_SIGNED}" = "true" ]
then
    method=selfsignedcert
fi

if [ "${DYNDNS_PROVIDER}" = "desec.io" ] && [ ! -f ".dedynauth" ]
then
    echo "using desec provider and fetching hook script"
    wget https://raw.githubusercontent.com/desec-io/certbot-hook/master/hook.sh
    wget https://raw.githubusercontent.com/desec-io/certbot-hook/master/.dedynauth
	# replace credentials in fetched file with the one from .env file
    $(sed 's@^DEDYN_TOKEN=.*@DEDYN_TOKEN='"${DEDYN_TOKEN}"'@g' .dedynauth > .dedynauth.tmp && mv .dedynauth.tmp .dedynauth)
    $(sed 's@^DEDYN_NAME=.*@DEDYN_NAME='"${DEDYN_NAME}"'@g' .dedynauth > .dedynauth.tmp && mv .dedynauth.tmp .dedynauth)
    chmod +x /hook.sh
fi

# first run, when no certificate exists create one
if [ ! -f "$certfile" ]
then
    cp /dummyssl/* /certs
    
    restart_containers
	# generate dh params
#	openssl dhparam -out /certs/dhparams.pem 4096
    $method
fi

# check validity of certificate, < 30 days? => renew
if ! openssl x509 -checkend 2592000 -noout -in $certfile
then
    echo "renew"
    $method
fi
