# удалить токен что бы не было ошибок у тулз хашикорпа типа:
#* one of token or service account key file must be specified, not both
set -e YC_TOKEN


#export YC_FOLDER_NAME="infra"
#export YC_FOLDER_ID="b1gshdlom4ja7p28n0fl"
export YC_FOLDER_NAME=$(yc config get folder-name)
export YC_FOLDER_ID=$(yc config get folder-id)

export YC_VPC_NAME="app-network"
export YC_SUBNET_NAME="app-subnet"
#export YC_ZONE="ru-central1-a"
export YC_ZONE=$(yc config get compute-default-zone)

export YC_VM_NAME="reddit-app"
export YC_VM_CONFIG="vm-config.txt"
export YC_STATIC_IP_NAME="infra-static-ip1"

export YC_SUBNET_ID=""
export YC_IMAGE_ID=""
export YC_STATIC_IP_ADDRESS=""

export YC_S3_BUCKET_NAME="diletech-terraform-state"
export YC_S3_ENDPOINT_URL="https://storage.yandexcloud.net"


set objects 'compute instance
compute image
load-balancer network-load-balancer
load-balancer target-group
vpc subnet
vpc network
vpc address
storage bucket
iam service-account'


#======= START BLOCK CALLBACK FUNCTIONS ================================
function yc_get_variables
    export YC_SUBNET_ID="$(yc vpc subnet list --format json | jq -r --arg name $YC_SUBNET_NAME '.[] | select(.name == $name) | .id')"
    export YC_IMAGE_ID="$(yc compute image list --format json | jq -r '.[0].id')"
    export YC_STATIC_IP_ADDRESS="$(yc vpc address list --format json | jq -r --arg name $YC_STATIC_IP_NAME '.[] | select(.name == $name) | .external_ipv4_address.address')"
end

function yc_list_object
    yc $argv list
end

function yc_delete_enum
    set obj $argv

    #если эти то удаляем по name и выходим
    if test "$obj" = "storage bucket"
        for name in (yc $obj list --format json | jq -r '.[].name')
            clean_bucket
            yc $obj delete --name=$name
        end
        return 0
    end

    #остальные удаляем по id
    for id in (yc $obj list --format json | jq -r '.[].id')
        yc $obj delete --id=$id
    end
end

function yc_list_key
    # перебор ключей для сервисных акков
    set IDs (yc iam service-account list --format=json | jq -r '.[].id')
    for ID in $IDs
        echo $ID
        for t in key api-key access-key
            echo $t
            yc iam $t list --service-account-id=$ID
        end
    end
end

function clean_bucket
    set -l key_file (find $HOME/.yc -name '*static*' -exec grep -l 'secret:' {} +|head -n1)
    if test -z "$key_file"
        return
    end
    set -l BUCKETNAME $YC_S3_BUCKET_NAME
    if not test (count $argv) -ne 1
        set BUCKETNAME $argv[1]
    end
    set -l KEYID (grep "key_id" $key_file | cut -d: -f2 | tr -d '[:space:]')
    set -l KEYSECRET (grep "secret" $key_file | cut -d: -f2 | tr -d '[:space:]')
    AWS_ACCESS_KEY_ID=$KEYID \
        AWS_SECRET_ACCESS_KEY=$KEYSECRET \
        S3_ENDPOINT_URL=$YC_S3_ENDPOINT_URL \
        S3_BUCKET_NAME=$BUCKETNAME \
        ./clean-S3-bucket.py #питоновский скрипт очищающий бакет
end
#======= END BLOCK CALLBACK FUNCTIONS ==================================


#======= START BLOCK INFO FUNCTIONS ====================================
function yc_list_all
    for object in (echo $objects)
        echo LIST: $object
        eval yc_list_object $object
    end
    yc_list_key
end

function yc_print_variables
    for var in (env | grep "^YC_")
        echo $var
    end
end
#======= END BLOCK INFO FUNCTIONS ======================================


#======= BEGIN CREATE NETWORK =================================
function yc_vpc_network_create
    yc vpc network create \
        --name $YC_VPC_NAME
end

function yc_vpc_subnet_create
    set -l SUBNET_NAME $argv[1]

    if test -z "$SUBNET_NAME"
        set SUBNET_NAME $YC_SUBNET_NAME
    end

    set -l oct2 (shuf -i 0-255 -n 1)
    set -l oct3 (shuf -i 0-255 -n 1)

    yc vpc subnet create \
        --name $SUBNET_NAME \
        --network-name $YC_VPC_NAME \
        --zone $YC_ZONE \
        --range "10.$oct2.$oct3.0/24"
end

function yc_vpc_address_create
    yc vpc address create \
        --name $YC_STATIC_IP_NAME \
        --external-ipv4 zone=$YC_ZONE
end

function yc_vpc_prepare
    yc_vpc_network_create
    yc_vpc_subnet_create
    #yc_vpc_address_create
end


#======= BEGIN CREATE INSTANCE ================================
function yc_compute_instance_create_with_imageId_and_staticIp
    if test -n $YC_IMAGE_ID
        yc compute instance create \
            --name $YC_VM_NAME \
            --hostname $YC_VM_NAME \
            --memory=4 \
            --cores=2 \
            --zone=$YC_ZONE \
            --create-boot-disk size=10GB,image-id=$YC_IMAGE_ID \
            --network-interface subnet-name=$YC_SUBNET_NAME \
            --metadata serial-port-enable=1 \
            --metadata-from-file user-data=$YC_VM_CONFIG
    else
        echo not exist YC_IMAGE_ID
    end

    if test -n $YC_STATIC_IP_ADDRESS
        yc compute instance add-one-to-one-nat \
            --name $YC_VM_NAME \
            --nat-address=$YC_STATIC_IP_ADDRESS \
            --network-interface-index=0
    else
        echo not exist YC_STATIC_IP_ADDRESS
    end
end

function yc_compute_instance_create_with_container
    set -l YC_VM_NAME docker-host
    set -l DOCKER_IMAGE 'diletech/otus-reddit:1.0'
    yc compute instance create-with-container \
        --name $YC_VM_NAME \
        --hostname $YC_VM_NAME \
        --memory=4 \
        --cores=2 \
        --zone=$YC_ZONE \
        --network-interface subnet-name=$YC_SUBNET_NAME,nat-ip-version=ipv4 \
        --metadata serial-port-enable=1 \
        --metadata-from-file user-data=$YC_VM_CONFIG \
        --container-image $DOCKER_IMAGE
end
#======= END CREATE ====================================================


#======= BEGIN CREATE BACKET ===========================================
function yc_backet_create_for_tfstate
    yc storage bucket create --name $YC_S3_BUCKET_NAME --max-size 10000000
end
#======= END CREATE ====================================================


#======= BEGIN CREATE SERVICE ACC ======================================
function yc_create_svc_acc
    set SVC_ACCT $argv[1]
    if test -z "$SVC_ACCT"
        echo Usage: (status current-command) NAME_ACC
        return
    end
    yc iam service-account create --name $SVC_ACCT --folder-id $YC_FOLDER_ID
    set ACCT_ID (yc iam service-account get $SVC_ACCT | grep ^id | awk '{print $2}')
    yc resource-manager folder add-access-binding --id $YC_FOLDER_ID \
        --role editor \
        --service-account-id $ACCT_ID
    # получаем приватный ключ для тераформа и статический ключ для бакета и сохраняем инфу
    yc iam access-key create --service-account-name $SVC_ACCT | tee ~/.yc/$SVC_ACCT-static_key.txt
    yc iam key create --service-account-id $ACCT_ID --output ~/.yc/$SVC_ACCT-key.json
    # выдаем права
    yc resource-manager folder add-access-binding --id $YC_FOLDER_ID \
        --role editor \
        --service-account-id $ACCT_ID
end
#======= END CREATE ====================================================


#======= BEGIN DELETE ALL =========================================
function yc_all_delete
    # Первый аргумент - режим удаления:
    # - 'all' (удалить все)
    # - 'excluding' (удалить с проверкой)
    set mode $argv[1]

    if test "$YC_CONFIRM_DELETE" = yes
        echo "Starting deletion process..."
        echo "You have 10 seconds to cancel the operation by pressing Ctrl+C"

        for i in (seq 10 -1 1)
            echo -n "Deletion will proceed in $i seconds... "
            sleep 1
            echo ""
        end

        # Исключаемые объекты из обработки удаления в зависимости от mode
        set excluding_objects 'vpc subnet
vpc network
compute image
storage bucket
iam service-account'

        # В зависимости от ключа удаляем всё или с исключением
        if test "$mode" = all
            for object in (echo $objects)
                echo DELETE: $object
                eval yc_delete_enum $object
            end
        else if test "$mode" = excluding
            set check_array (string split \n "$excluding_objects")

            for object in (echo $objects)
                # if string match -qr "$object" $check_array
                if contains -- "$object" $check_array
                    echo "Excluding: $object"
                    continue
                end
                echo DELETE: $object
                eval yc_delete_enum $object
            end
        else
            echo "Invalid mode specified. Please specify 'all' or 'excluding'."
            return 1
        end

        echo "Deleted successfully."
    else
        echo "Deletion canceled."
    end
end

function yc_all_delete_confirm
    # Проверка наличия ключа
    if test (count $argv) -ne 1
        echo "Usage: yc_all_delete_confirm [all|excluding]"
        return
    end

    # Проверка получаемого значения ключа
    set -l mode $argv[1]
    if test "$mode" != all -a "$mode" != excluding
        echo "Usage: yc_all_delete_confirm [all|excluding]"
        return
    end

    set -q YC_CONFIRM_DELETE || set -x YC_CONFIRM_DELETE (read -P "Are you sure you want to delete? (yes/no): ")
    if test "$YC_CONFIRM_DELETE" = yes
        # Передаем аргумент в функцию yc_all_delete для выбора режима удаления
        yc_all_delete $mode
    else
        echo "Deletion canceled."
    end
end
#======= END DELETE ====================================================
