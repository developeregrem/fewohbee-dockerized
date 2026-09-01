#!/bin/bash

if [ -f ".env" ]; then
    echo "Already installed. If you want to change settings please modify the file .env manually."
    exit 0
fi

opensslBin=""
dockerBin=""
dockerComposeBin=""

isAvailable() {
    tmp=$(which echo $1)
    if [ $? -ne 0 ]
    then
        echo "docker and openssl must be installed!"
        exit 1
    fi
}

isPluginAvailable() {
    tmp=$($dockerBin $1 > /dev/null 2>&1)
    if [ $? -ne 0 ]
    then
        echo "docker compose plugin must be installed!"
        exit 1
    fi
}

createCron() {
    local cronDirectory="${2:-/etc/cron.d}"
    local cronName="$1"
    local sourceCron="$PWD/cron.d/$cronName"
    local targetCron="$cronDirectory/$cronName"

    if [ ! -d "$cronDirectory" ]; then
        echo "Could not create cronjob. Path $cronDirectory does not exist."
        return 1
    fi

    if [ ! -f "$sourceCron" ]; then
        echo "Could not create cronjob. Source file $sourceCron does not exist."
        return 1
    fi

    if [ -L "$targetCron" ]; then
        if [ "$(readlink "$targetCron")" = "$sourceCron" ]; then
            echo "Cronjob $targetCron already exists."
            return 0
        fi

        if ln -sfn "$sourceCron" "$targetCron"; then
            echo "Cronjob symlink $targetCron was updated."
            return 0
        fi

        echo "Could not update symlink $targetCron. Do you have permission to write there?"
        return 1
    fi

    if [ -e "$targetCron" ]; then
        echo "Cronjob target $targetCron already exists and is not a symlink. Keeping it unchanged."
        return 0
    fi

    if ! ln -s "$sourceCron" "$targetCron"; then
        echo "Could not create symlink $targetCron. Do you have permission to write there?"
        return 1
    fi

    echo "A cronjob was created in $targetCron."
}

isValidPort() {
    local port="$1"

    [[ "$port" =~ ^[0-9]+$ ]] && [ "${#port}" -le 5 ] && ((10#$port >= 1 && 10#$port <= 65535))
}

# Returns 0 when a TCP port is in use and 1 when it is free. Docker mappings
# and socket inspection tools are preferred; Bash TCP connections are the fallback.
isPortInUse() {
    local port="$1"
    local listeners=""
    local publishedPorts=""

    if [ -n "$dockerBin" ] && publishedPorts=$("$dockerBin" ps --format '{{.Ports}}' 2>/dev/null); then
        if printf '%s\n' "$publishedPorts" | awk -v port="$port" '
            index($0, ":" port "->") { found = 1 }
            END { exit(found ? 0 : 1) }
        '; then
            return 0
        fi
    fi

    if command -v ss > /dev/null 2>&1 && listeners=$(ss -H -ltn 2>/dev/null); then
        printf '%s\n' "$listeners" | awk -v port="$port" '
            $4 ~ ("[.:]" port "$") { found = 1 }
            END { exit(found ? 0 : 1) }
        '
        return $?
    fi

    if command -v lsof > /dev/null 2>&1; then
        lsof -nP -iTCP:"$port" -sTCP:LISTEN -t > /dev/null 2>&1
        return $?
    fi

    if command -v netstat > /dev/null 2>&1 && listeners=$(netstat -an 2>/dev/null); then
        printf '%s\n' "$listeners" | awk -v port="$port" '
            toupper($0) ~ /LISTEN/ && $4 ~ ("[.:]" port "$") { found = 1 }
            END { exit(found ? 0 : 1) }
        '
        return $?
    fi

    if (: > "/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
        return 0
    fi

    if (: > "/dev/tcp/::1/$port") 2>/dev/null; then
        return 0
    fi

    return 1
}

configureHostPort() {
    local resultVariable="$1"
    local label="$2"
    local defaultPort="$3"
    local alternativePort="$4"
    local excludedPort="${5:-}"
    local selectedPort=""
    local checkStatus=0

    isPortInUse "$defaultPort" || checkStatus=$?
    if [ "$checkStatus" -eq 1 ]; then
        printf -v "$resultVariable" '%s' "$defaultPort"
        echo "$label port $defaultPort is available."
        return 0
    fi

    echo "$label port $defaultPort is already in use."

    while true; do
        read -r -p "Please enter an available host port for $label [$alternativePort]:" selectedPort
        selectedPort="${selectedPort:-$alternativePort}"

        if ! isValidPort "$selectedPort"; then
            echo "Please enter a port between 1 and 65535."
            continue
        fi

        if [ -n "$excludedPort" ] && [ "$selectedPort" = "$excludedPort" ]; then
            echo "$label must use a different port than $excludedPort."
            continue
        fi

        checkStatus=0
        isPortInUse "$selectedPort" || checkStatus=$?
        if [ "$checkStatus" -eq 0 ]; then
            echo "Port $selectedPort is already in use. Please choose another port."
            continue
        fi

        printf -v "$resultVariable" '%s' "$selectedPort"
        return 0
    done
}

checkRequirements(){
    isAvailable "openssl"
    opensslBin=$(which openssl)
    isAvailable "docker"
    dockerBin=$(which docker)
    isPluginAvailable "compose version"
    dockerComposeBin="$dockerBin compose"
}

checkRequirements

echo "This script will guide you through the installation of the tool."

# use .env.dist as template and replace specific values during script execution
umask 0177
envTemplate=.env.dist
envTmp=.env.tmp
envEnd=.env

cp $envTemplate $envTmp

########## setup host name ##########
pveHostDefault=$(hostname)
pveHost=""
read -p "Please enter the host name of your server [$pveHostDefault]:" pveHost
pveHost="${pveHost:-${pveHostDefault}}"
$(sed "s/HOST_NAME=fewohbee/HOST_NAME=$pveHost/" $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)
$(sed "s/RELYING_PARTY_ID=example.com/RELYING_PARTY_ID=$pveHost/" $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)

########## setup certificate ##########
sslDefault="self-signed"
ssl=""
while ! [[ "$ssl" =~ ^(self-signed|letsencrypt|reverse-proxy)$ ]]
do
    read -p "SSL Certificate: Using self-signed, letsencrypt or reverse-proxy? [$sslDefault]:" ssl
    ssl="${ssl:-${sslDefault}}"
done

if [ "$ssl" == "letsencrypt" ]
then
    # ask for email for letsencrypt
    leMailDefault=""
    leMail=""
    read -p "Please enter your email address to get informed when your letsencrypt certificate is about to expire:" leMail
    leMail="${leMail:-${leMailDefault}}"

    leDomains="$pveHost"

    # ask whether www should be added as letsencrypt domain
    leWwwDefault="yes"
    leWww=""
    read -p "Add www subdomain to your letsencrypt certificate: www.${pveHost}? (yes/no) [$leWwwDefault]:" leWww
    leWww="${leWww:-${leWwwDefault}}"

    if [ "$leWww" == "$leWwwDefault" ]
    then
        leDomains="${leDomains} www.${pveHost}"
    fi

    $(sed 's@LETSENCRYPT=false@LETSENCRYPT=true@g' $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)
    $(sed 's@SELF_SIGNED=true@SELF_SIGNED=false@g' $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)
    $(sed 's@LETSENCRYPT_DOMAINS="<domain.tld>"@LETSENCRYPT_DOMAINS='"$leDomains"'@g' $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)
    $(sed 's/EMAIL="<your mail address>"/EMAIL='"$leMail"'/g' $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)
fi

# reverse-proxy: SSL is terminated externally — disable internal SSL and switch compose file
if [ "$ssl" == "reverse-proxy" ]
then
    $(sed 's@SELF_SIGNED=true@SELF_SIGNED=false@g' $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)
    $(sed 's@COMPOSE_FILE=docker-compose.yml:docker-compose.override.yml@COMPOSE_FILE=docker-compose.no-ssl.yml:docker-compose.override.yml@g' $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)
fi

########## setup host ports ##########
listenPort=80
httpsListenPort=443
configureHostPort listenPort "HTTP (LISTEN_PORT)" 80 8080

if [ "$ssl" != "reverse-proxy" ]; then
    configureHostPort httpsListenPort "HTTPS (HTTPS_LISTEN_PORT)" 443 8443 "$listenPort"
fi

sed "s@^LISTEN_PORT=.*@LISTEN_PORT=$listenPort@" "$envTmp" > "$envTmp.tmp" && mv "$envTmp.tmp" "$envTmp"
sed "s@^HTTPS_LISTEN_PORT=.*@HTTPS_LISTEN_PORT=$httpsListenPort@" "$envTmp" > "$envTmp.tmp" && mv "$envTmp.tmp" "$envTmp"

if [ "$ssl" == "letsencrypt" ] && [ "$listenPort" != "80" ]; then
    echo "Warning: Let's Encrypt HTTP-01 validation requires public port 80."
    echo "Forward public port 80 to host port $listenPort or certificate issuance will fail."
fi

if [ "$ssl" == "letsencrypt" ] && [ "$httpsListenPort" != "443" ]; then
    echo "Note: Browsers use HTTPS port 443 by default."
    echo "Forward public port 443 to host port $httpsListenPort or include the port in the URL."
fi

########## setup cron ##########
cronDefault="yes"
cronDB=""
cronDocker=""
read -p "Enable automatic database backups? (yes/no) [$cronDefault]:" cronDB
cronDB="${cronDB:-${cronDefault}}"

if [ "$cronDB" == "$cronDefault" ]
then
    createCron "backup_mysql_docker"
    if [ $? -eq 0 ]
    then
        echo "Backups will be stored in the db-backup-vol Docker volume."
    fi
    chmod +x backup-db.sh
fi

read -p "Enable automatic updates of docker images? (yes/no) [$cronDefault]:" cronDocker
cronDocker="${cronDocker:-${cronDefault}}"

if [ "$cronDocker" == "$cronDefault" ]
then
    createCron "update-docker"
fi

### select language ###
pveLangDefault="de"
pveLang=""
while ! [[ "$pveLang" =~ ^(de|en)$ ]]
do
    read -p "Please choose the language of the tool (de/en) [$pveLangDefault]:" pveLang
    pveLang="${pveLang:-${pveLangDefault}}"
done

$(sed "s@LOCALE=de@LOCALE=$pveLang@g" $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)
echo "Setup uses the production image (fewohbee-phpfpm:latest). For development, set FEWOHBEE_VERSION=<version>-debug in .env after installation."

echo "Generating secrets and passwords."
mariadbRootPw=$(openssl rand -base64 32 | shasum | cut -f 1 -d " ")
mariadbPw=$(openssl rand -base64 32 | shasum | cut -f 1 -d " ")
mysqlBackupPw=$(openssl rand -base64 32 | shasum | cut -f 1 -d " ")
appSecret=$(openssl rand -base64 23)

$(sed 's@MARIADB_ROOT_PASSWORD=<pw>@MARIADB_ROOT_PASSWORD='"$mariadbRootPw"'@g' $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)
$(sed 's@MARIADB_PASSWORD=<pw>@MARIADB_PASSWORD='"$mariadbPw"'@g' $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)
$(sed "s@MYSQL_BACKUP_PASSWORD=<backuppassword>@MYSQL_BACKUP_PASSWORD=$mysqlBackupPw@g" $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)
$(sed "s@APP_SECRET=<secret>@APP_SECRET=$appSecret@g" $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)

# replace db password in DATABASE_URL
$(sed "s@db_password@$mariadbPw@" $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)

mv $envTmp $envEnd

########## pull, build and start environment ##########
echo "Preparing and starting docker-compose setup ..."
$dockerComposeBin up -d

if [ $? -ne 0 ]
then
    echo "error during docker-compose up"
    exit 1
fi

########## application setup ##########
echo "Waiting for the php container to become healthy ..."
waited=0
while true; do
    health=$($dockerComposeBin ps --format '{{.Service}} {{.Health}}' 2>/dev/null | grep '^php ' | awk '{print $2}')
    if [ "$health" = "healthy" ]; then
        break
    fi
    if [ $waited -ge 180 ]; then
        echo "Warning: php container did not become healthy within 180s. Continuing anyway."
        break
    fi
    echo "still waiting ..."
    sleep 5
    waited=$((waited + 5))
done

########## init tool ##########
$dockerComposeBin exec --user www-data php /bin/sh -c "php bin/console app:first-run"

echo "done"
if [ "$ssl" == "reverse-proxy" ]
then
    echo "You can now open a browser and visit http://$pveHost (via reverse proxy)."
else
    echo "You can now open a browser and visit https://$pveHost."
fi
echo "If you want to use the conversation feature please modify the section in the .env file accordingly."
echo "  > see https://github.com/developeregrem/fewohbee/wiki/Konfiguration#e-mails"
echo "To use the city lookup feature please refer to: https://github.com/developeregrem/fewohbee/wiki/City-Lookup"

exit 0
