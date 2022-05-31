
 # fewohbee-dockerized

This docker-compose setup is part of the [guesthouse administration tool](https://github.com/developeregrem/fewohbee). fewohbee-dockerized provides all necessary software/images in order to run the guesthouse administration tool (Pensionsverwaltung) out of the box.

The setup contains:  

-  [nginx](https://hub.docker.com/_/nginx/) as web server or reverse proxy

-  [mariadb](https://hub.docker.com/_/mariadb) as database management system

-  [PHP 8.1-fpm-alpine](https://hub.docker.com/_/php/) with [composer](https://hub.docker.com/_/composer) which [installs](https://github.com/developeregrem/fewohbee-phpfpm) the guesthouse administration tool when the container is started.

-  [redis](https://hub.docker.com/_/redis) as in-memory cache

- ACME for letsencrypt or self-signed certificates (with automatic renew)

## Installation

Clone the master branch of the repository.

  ````
  cd /opt
  git clone https://github.com/developeregrem/fewohbee-dockerized.git
  cd fewohbee-dockerized
  ````
  
Run the interactive installtion script to generate the configuration file and setup the application.

  ````
  chmod +x install.sh
  ./install.sh
  ````

## Usage

Please refer to the documentation in the Wiki: [https://github.com/developeregrem/fewohbee/wiki/Docker-Setup](https://github.com/developeregrem/fewohbee/wiki/Docker-Setup)
