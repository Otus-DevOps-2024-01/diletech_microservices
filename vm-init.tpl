#cloud-config

package_update: true
packages:
  - vim
  - fish

datasource:
  Ec2:
    strict_id: false
ssh_pwauth: yes
users:
  - name: "${USER_NAME}"
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    passwd: "${USER_HASH}"
    lock_passwd: false
    groups: docker, google-sudoers
    ssh-authorized-keys:
      - "${USER_SSH_KEY}"
  - name: docker-user
    shell: /bin/bash
    groups: docker
    ssh-authorized-keys:
      - "${USER_SSH_KEY}"
