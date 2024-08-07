# diletech_microservices
## docker-2
`docker-machine` неактуален, взамен для создания используются всевозможные средства автоматизации как облачные так и локальные, а для переключения между ними `docker context`
- локальная установка **Docker Desktop** или же **Podman Desktop**
- облачная установка ВМ с готовым контейнером (докерфайлом или доверкомпоз) в yc так `yc compute instance create-with-container`

создать имидж из докерфайла `docker build -t reddit:latest .` при этом ключ `--squash` схлопывает слои в один

загрузить имидж с тэгом на докерхаб:
```
docker tag reddit:latest diletech/otus-reddit:1.0
docker push diletech/otus-reddit:1.0
```

запустить в облаке
```fish
source yc-automate.fish  # шелл-автоматика для yc
yc_vpc_prepare  # создать сеть
set UPH (bash vm-make-config.sh)  # создать шаблон метадаты для cloud-ini, скрипт вернет пароль и запишется в переменную, другой вариант соль делать паролем :-)
yc_compute_instance_create_with_container  # создать ВМ с докером

#получить IP и подключиться
set -U IP (yc compute instance list --format json | jq -r '.[].network_interfaces[].primary_v4_address.one_to_one_nat.address')
while true; ssh -oConnectTimeout=3 -oServerAliveInterval=2 -oServerAliveCountMax=2 yc-user@$IP;if test $status -eq 0; break;end; sleep 2;end

yc_all_delete_confirm  # удалить всё
```

создать контекст, отобразить их и переключится туда и обратно и удалить созданный
```
docker context create \
    --docker host=ssh://docker-user@$IP \
    --description="YC container" \
    yc-docker-host

docker context ls
docker context use yc-docker-host
docker context use default
docker context rm yc-docker-host
```

### yc, cloud-init
- довольно странно себя ведет sudo при создании ВМ через `create-with-container`, sudo для пользователя отрабатывает только один раз :), но внезапно есть предустановленная группа google-sudoers
- так же странным образом строка пароля оказывается усеченная в shadow
- посмотреть всю инфу о хосте `yc compute instance get --full docker-host`
- подключиться по ssh `yc compute ssh --login yc-user -i ~/.ssh/id_rsa --name docker-host`

## docker-3
билдить так:
```sh
docker build -t diletech/post:1.0 ./post-py
docker build -t diletech/comment:1.0 ./comment
docker build -t diletech/ui:1.0 ./ui
```

запускать так:
```sh
docker run -d --network=reddit --network-alias=post_db --network-alias=comment_db -v reddit_db:/data/db --name mongo mongo:3.4.20
docker run -d --network=reddit --network-alias=post --name post diletech/post:1.0
docker run -d --network=reddit --network-alias=comment  --name comment diletech/comment:1.0
docker run -d --network=reddit -p 9292:9292 --name ui diletech/ui:1.0
```

остановить и очистить так:
```sh
docker kill $(docker ps -q)
docker container prune -f
docker network rm reddit
docker volume rm reddit_db
```

## docker-4
запуск в разных сетях так (билд в предыдущем):
```sh
# создать сети
docker network create back_net --subnet=10.0.2.0/24
docker network create front_net --subnet=10.0.1.0/24

# запустить контейнеры
docker run -d --network=front_net --network-alias=post_db --network-alias=comment_db -v reddit_db:/data/db --name mongo_db mongo:3.4.20
docker run -d --network=back_net --network-alias=post --name post diletech/post:1.0
docker run -d --network=back_net --network-alias=comment  --name comment diletech/comment:1.0
docker run -d --network=back_net -p 9292:9292 --name ui diletech/ui:1.0

# добавть сети в контейнеры
docker network connect front_net post
docker network connect front_net comment

# всё удалить (включая сети)
docker kill $(docker ps -q)
docker container prune -f
docker network rm {back_net,front_net}
```

### docker compose
для изменения имени проекта при запуске используется ключ `-p`, так же останаваливать `stop`, либо же `down`, необходимо с его указаним, потому как без указания используется значение по умолчанию (имя "папки" :-) или же указанное в `name:`
```
docker-compose -p myproject -d up
docker-compose -p myproject down
```
