FROM php:8.3-apache

RUN apt-get update && apt-get install -y \
    wget \
    tar \
    libicu-dev \
    libzip-dev \
    libpng-dev

RUN docker-php-ext-install mysqli zip gd intl

RUN mkdir -p /var/www/moodledata && \
    chmod -R 777 /var/www/moodledata

RUN wget https://download.moodle.org/download.php/direct/stable503/moodle-latest-503.tgz && \
    tar -xzf moodle-latest-503.tgz && \
    mv moodle/* /var/www/html/ && \
    rm -rf moodle moodle-latest-503.tgz

RUN sed -i 's#/var/www/html#/var/www/html/public#g' /etc/apache2/sites-available/000-default.conf

RUN echo "max_input_vars=5000" > /usr/local/etc/php/conf.d/moodle.ini
