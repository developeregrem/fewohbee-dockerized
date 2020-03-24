#!/bin/sh

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
        echo "docker, docker-compose and openssl must be installed!"
        exit 1
    fi
}

checkRequirements(){
    isAvailable "openssl"
    opensslBin=$(which openssl)
    isAvailable "docker"
    dockerBin=$(which docker)
    isAvailable "docker-compose"
    dockerComposeBin=$(which docker-compose)
}

checkRequirements

echo "This script will guide you through the installation of the tool."

# use env.dist as template and replace specific values during script execution
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
$(sed "s/HOST_NAME=pve/HOST_NAME=$pveHost/" $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)

########## setup certificate self-signed or letsencrypt ##########
sslDefault="self-signed"
ssl=""
while ! [[ "$ssl" =~ ^(self-signed|letsencrypt)$ ]] 
do
    read -p "SSL Certificate: Using self-signed or letsencrypt? [$sslDefault]:" ssl
    ssl="${ssl:-${sslDefault}}"
done

# default is self-signed
if [ "$ssl" == "letsencrypt" ]
then
    $(sed 's@LETSENCRYPT=false@LETSENCRYPT=true@g' $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)
    $(sed 's@SELF_SIGNED=true@SELF_SIGNED=false@g' $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)
fi

########## setup symfony env ##########
pveEnvDefault="prod"
pveEnv=""
while ! [[ "$pveEnv" =~ ^(prod|dev)$ ]] 
do
    read -p "Do you want to run the tool in productive (prod) mode oder development (dev) mode [$pveEnvDefault]:" pveEnv
    pveEnv="${pveEnv:-${pveEnvDefault}}"
done

$(sed 's@APP_ENV=prod@APP_ENV='"$pveEnv"'@g' $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)
echo "Setting up $pveEnv environment."

echo "Generating secrets and passwords."
mysqlRootPw=$(openssl rand -base64 32)
mysqlPw=$(openssl rand -base64 32 | shasum | cut -f 1 -d " ")
mysqlBackupPw=$(openssl rand -base64 32 | shasum | cut -f 1 -d " ")
appSecret=$(openssl rand -base64 23)

$(sed 's@MYSQL_ROOT_PASSWORD=<pw>@MYSQL_ROOT_PASSWORD='"$mysqlRootPw"'@g' $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)
$(sed 's@MYSQL_PASSWORD=<pw>@MYSQL_PASSWORD='"$mysqlPw"'@g' $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)
$(sed "s@MYSQL_BACKUP_PASSWORD=<backuppassword>@MYSQL_BACKUP_PASSWORD=$mysqlBackupPw@g" $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)
$(sed "s@APP_SECRET=<secret>@APP_SECRET=$appSecret@g" $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)

# replace db password in db string
$(sed "s@db_password@$mysqlPw@" $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)

mv $envTmp $envEnd

########## pull, build and start environment ##########
echo "Preparing and starting docker-compose setup ..."
$dockerComposeBin up -d

if [ $? -ne 0 ]
then
    echo "error during docker-compose up"
    exit 1
fi

########## ssl setup ##########
echo "Initiating certificate creation ..."
sleep 3
$dockerComposeBin exec acme /bin/sh -c "./run.sh"

########## application setup ##########
echo "Setting up application ..."
echo "Pulling app dependencies and setting up the database (this will take some time)."
# this check depends on the script entrypoint.sh from pve-phpfpm image
until [ "`$dockerComposeBin exec -T php /bin/sh -c 'cat /firstrun'`" == "1"  ]
do 
    echo "waiting to finish initilization ..."
    sleep 10
done

########## create db backup user ##########
echo "Creating db backup user ..."
sleep 3
dbQuery="GRANT LOCK TABLES, SELECT ON *.* TO \"backupuser\"@\"%\" IDENTIFIED BY \"$mysqlBackupPw\""
docker-compose exec db /bin/sh -c "mysql -p$mysqlRootPw -uroot -e '$dbQuery'"

########## init tool ##########
$dockerComposeBin exec --user www-data php /bin/sh -c "php pve/bin/console app:first-run"

echo "done"
echo "You can now open a browser and visit https://$pveHost."
echo "If you want to use the conversation feature please modify the section in the .env file accordingly."
echo "  > see https://github.com/developeregrem/pve/wiki/Konfiguration#e-mails"

exit 0
