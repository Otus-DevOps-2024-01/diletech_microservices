#/bin/bash
export USER_SSH_KEY=$(cat ~/.ssh/id_rsa.pub)
export USER_NAME=yc-user
export USER_PASSWORD=$(pwgen -1)
export USER_SALT=$(pwgen -1)
export USER_HASH=$(openssl passwd -6 -salt $USER_SALT $USER_PASSWORD)

echo $USER_NAME $USER_PASSWORD $USER_HASH
envsubst < vm-init.tpl > vm-config.txt
