FROM php:7.4-apache

RUN apt-get update && apt-get install -y cron git-core jq unzip vim zip \
  libjpeg-dev libpng-dev libpq-dev libsqlite3-dev libwebp-dev libzip-dev && \
  rm -rf /var/lib/apt/lists/* && \
  docker-php-ext-configure zip --with-zip && \
  docker-php-ext-configure gd --with-jpeg --with-webp && \
  docker-php-ext-install exif gd mysqli opcache pdo_pgsql pdo_mysql zip

RUN pecl install -o -f redis \
&&  rm -rf /tmp/pear \
&&  docker-php-ext-enable redis

RUN { \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.interned_strings_buffer=8'; \
    echo 'opcache.max_accelerated_files=4000'; \
    echo 'opcache.revalidate_freq=2'; \
    echo 'opcache.fast_shutdown=1'; \
    echo 'opcache.enable_cli=1'; \
  } > /usr/local/etc/php/conf.d/docker-oc-opcache.ini

RUN { \
    echo 'log_errors=on'; \
    echo 'display_errors=off'; \
    echo 'upload_max_filesize=32M'; \
    echo 'post_max_size=32M'; \
    echo 'memory_limit=128M'; \
  } > /usr/local/etc/php/conf.d/docker-oc-php.ini

ENV COMPOSER_ALLOW_SUPERUSER=1

RUN curl -sS https://getcomposer.org/installer | php -- --1 --install-dir=/usr/local/bin --filename=composer && \
  /usr/local/bin/composer global require hirak/prestissimo

RUN a2enmod rewrite

ENV OCTOBERCMS_TAG v1.1.5
ENV DB_CONNECTION sqlite
ENV DB_DATABASE storage/database.sqlite

RUN git clone https://github.com/octobercms/october.git -b $OCTOBERCMS_TAG --depth 1 . && \
  echo "Update composer.json: Set explicit build references for october module dependencies" && \
  sed -i.orig "s/\(\"october\/\([rain|system|backend|cms]*\)\": \"\(1.1.*\)\"\)/\"october\/\2\": \"<=${OCTOBERCMS_TAG#v}\"/g" composer.json && \
  egrep -o "['\"]october\/[rain|system|backend|cms]*['\"]\s*:\s*['\"](.+?)['\"]" composer.json && \
  composer install --no-interaction --prefer-dist --no-scripts && \
  composer clearcache && \
  git status && git checkout modules/. && \
  rm -rf .git && \
  echo 'APP_ENV=docker' > .env && \
  touch storage/database.sqlite && \
  chmod 666 storage/database.sqlite && \
  php artisan october:install && \
  php artisan plugin:install october.drivers && \
  chown -R www-data:www-data /var/www/html && \
  find . -type d \( -path './plugins' -or  -path './storage' -or  -path './themes' -or  -path './plugins/*' -or  -path './storage/*' -or  -path './themes/*' \) -exec chmod g+ws {} \;

RUN echo "* * * * * /usr/local/bin/php /var/www/html/artisan schedule:run > /proc/1/fd/1 2>/proc/1/fd/2" > /etc/cron.d/october-cron && \
  crontab /etc/cron.d/october-cron

RUN echo 'exec php artisan "$@"' > /usr/local/bin/artisan && \
  echo 'exec php artisan tinker' > /usr/local/bin/tinker && \
  echo '[ $# -eq 0 ] && exec php artisan october || exec php artisan october:"$@"' > /usr/local/bin/october && \
  sed -i '1s;^;#!/bin/bash\n[ "$PWD" != "/var/www/html" ] \&\& echo " - Helper must be run from /var/www/html" \&\& exit 1\n;' /usr/local/bin/artisan /usr/local/bin/tinker /usr/local/bin/october && \
  chmod +x /usr/local/bin/artisan /usr/local/bin/tinker /usr/local/bin/october

COPY docker-oc-entrypoint /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-oc-entrypoint

ENTRYPOINT ["docker-oc-entrypoint"]
CMD ["apache2-foreground"]
