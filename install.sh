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
    if [ ! -d "/etc/cron.d/" ]; then
        echo "Could not create cronjob. Path /etc/cron.d/ does not exists."
        return 1
    fi
    targetCron="/etc/cron.d/$1"
    ln -s $PWD/cron.d/$1 $targetCron    
    if [ $? -ne 0 ]
    then
        echo "Could not create symlink $targetCron. Do you have the permission to write there?"
        exit 1
    fi
    echo "A cronjob was created in $targetCron."
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
$(sed "s/HOST_NAME=fewohbee/HOST_NAME=$pveHost/" $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)

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
        echo "Backups will be stored in ../dbbackup."
    fi
    chmod +x backup-db.sh  
fi

read -p "Enable automatic updates of docker images? (yes/no) [$cronDefault]:" cronDocker
cronDocker="${cronDocker:-${cronDefault}}"

if [ "$cronDocker" == "$cronDefault" ]
then
    createCron "update-docker"
fi

########## setup symfony env ##########
pveEnvDefault="prod"
pveEnv=""
while ! [[ "$pveEnv" =~ ^(prod|dev)$ ]] 
do
    read -p "Do you want to run the tool in productive mode oder development mode (prod/dev) [$pveEnvDefault]:" pveEnv
    pveEnv="${pveEnv:-${pveEnvDefault}}"
done

### when prod is used, use redis caching
if [ "$pveEnv" == "prod" ]
then
    pveEnv="redis"
fi

### select language ###
pveLangDefault="de"
pveLang=""
while ! [[ "$pveLang" =~ ^(de|en)$ ]] 
do
    read -p "Please choose the language of the tool (de/en) [$pveLangDefault]:" pveLang
    pveLang="${pveLang:-${pveLangDefault}}"
done

$(sed 's@APP_ENV=prod@APP_ENV='"$pveEnv"'@g' $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)
echo "Setting up $pveEnv environment."

echo "Generating secrets and passwords."
mariadbRootPw=$(openssl rand -base64 32 | shasum | cut -f 1 -d " ")
mariadbPw=$(openssl rand -base64 32 | shasum | cut -f 1 -d " ")
mysqlBackupPw=$(openssl rand -base64 32 | shasum | cut -f 1 -d " ")
appSecret=$(openssl rand -base64 23)

$(sed 's@MARIADB_ROOT_PASSWORD=<pw>@MARIADB_ROOT_PASSWORD='"$mariadbRootPw"'@g' $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)
$(sed 's@MARIADB_PASSWORD=<pw>@MARIADB_PASSWORD='"$mariadbPw"'@g' $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)
$(sed "s@MYSQL_BACKUP_PASSWORD=<backuppassword>@MYSQL_BACKUP_PASSWORD=$mysqlBackupPw@g" $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)
$(sed "s@APP_SECRET=<secret>@APP_SECRET=$appSecret@g" $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)
$(sed "s@LOCALE=de@LOCALE=$pveLang@g" $envTmp > $envTmp.tmp && mv $envTmp.tmp $envTmp)

# replace db password in db string
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

########## ssl setup ##########
echo "Initiating certificate creation ..."
sleep 3
$dockerComposeBin exec acme /bin/sh -c "./run.sh"

########## application setup ##########
echo "Setting up application ..."
echo "Pulling app dependencies and setting up the database (this will take some time)."
# this check depends on the script entrypoint.sh from fewohbee-phpfpm image
until [ "`$dockerComposeBin exec -T php /bin/sh -c 'cat /firstrun'`" == "1"  ]
do 
    echo "still waiting ..."
    sleep 10
done

########## create db backup user ##########
echo "Creating db backup user ..."
sleep 3
dbQuery="GRANT LOCK TABLES, SELECT ON *.* TO \"backupuser\"@\"%\" IDENTIFIED BY \"$mysqlBackupPw\""
$dockerComposeBin exec db /bin/sh -c "mariadb -p$mariadbRootPw -uroot -e '$dbQuery'"

########## init tool ##########
$dockerComposeBin exec --user www-data php /bin/sh -c "php fewohbee/bin/console app:first-run"

########## load test data ##########
## always load templates
$dockerComposeBin exec --user www-data php /bin/sh -c "php fewohbee/bin/console doctrine:fixtures:load --append --group templates"
testDataDefault="no"
testData=""
while ! [[ "$testData" =~ ^(yes|no|y|n)$ ]] 
do
    read -p "Do you want to load some initial test data into the application? (yes/no) [$testDataDefault]:" testData
    testData="${testData:-${testDataDefault}}"
done

# default is self-signed
if [ "$testData" == "yes" ]
then
    $dockerComposeBin exec --user www-data php /bin/sh -c "php fewohbee/bin/console doctrine:fixtures:load --append --group settings --group customer --group reservation --group invoices"
fi

echo "done"
echo "You can now open a browser and visit https://$pveHost."
echo "If you want to use the conversation feature please modify the section in the .env file accordingly."
echo "  > see https://github.com/developeregrem/fewohbee/wiki/Konfiguration#e-mails"
echo "To use the city lookup feature please refer to: https://github.com/developeregrem/fewohbee/wiki/City-Lookup"

exit 0
