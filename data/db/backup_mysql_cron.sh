#!/bin/sh

pass=$MYSQL_BACKUP_PASSWORD
user=$MYSQL_BACKUP_USER
localFolder=/root/mysql_backup
targetfolder=/dbbackup


#wenn Ordner nicht existiert
if [ ! -d $localFolder ]
then
	mkdir $localFolder
	if [ $? -ne 0 ]
	then
#		echo $localFolder existiert nicht
		exit 2
	fi
fi

# perform a mysql_backup first if tehre was an automated version upgrade before
mysql_upgrade -uroot -p$MYSQL_ROOT_PASSWORD


#-c : complete-insert
#-n : if exists
#-R : SP/functions
#wochentag 1=Mo, 7=So
date=`date +%u`
mysqldump -c -n -R -p$pass -u$user $MYSQL_DATABASE > $localFolder/$MYSQL_DATABASE'_'$date.sql


#packen
cd $localFolder
tar -czf mysql_$date.tar.gz *_$date.sql
if [ $? -ne 0 ]
then
	exit 2
fi

#wenn Ordner nicht existiert, anlegen
if [ ! -d $targetfolder ]
then
	mkdir -p $targetfolder
	if [ $? -ne 0 ]
	then
		exit 5
	fi
fi

cp $localFolder/mysql_$date.tar.gz $targetfolder
#sql Dateien löschen
rm -rf $localFolder/*.sql
rm $localFolder/mysql_$date.tar.gz

exit 0