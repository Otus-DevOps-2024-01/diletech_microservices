FROM ubuntu:18.04

# Установка необходимых пакетов
RUN apt-get update && \
    apt-get install -y mongodb-server ruby-full ruby-dev build-essential git && \
    gem install bundler -v 1.16.1

# Клонирование репозитория с кодом приложения
RUN git clone -b monolith https://github.com/express42/reddit.git /reddit

# Копирование конфигурационных файлов
COPY mongod.conf /etc/mongod.conf
COPY db_config /reddit/db_config
COPY start.sh /start.sh

# Настройка прав доступа к start.sh
RUN chmod 0777 /start.sh

# Установка зависимостей приложения
RUN cd /reddit && rm Gemfile.lock && bundle install

EXPOSE 9292

# Запуск скрипта при старте контейнера
CMD ["/start.sh"]
