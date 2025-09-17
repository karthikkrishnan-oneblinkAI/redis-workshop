#!/bin/bash

# Install RDI
run_rdi_installation() {
    local retries=5
    local count=0
    local success=false

    while [ $count -lt $retries ]; do
        echo "Attempt $((count + 1)) of $retries to run the rdi  installation..."
        install_output=$(bash install.sh -f silent.toml 2>&1)

        # Check for "non-zero exit status 1" in the output
        if echo "$install_output" | grep -qE "non-zero exit status 1|Error while attempting to install RDI"; then
            echo "Installation failed with an error. Check the installation log for more info. '/opt/rdi/logs/'"
            count=$((count + 1))
        else
            echo "Installation succeeded."
            success=true
            break
        fi
    done

    if [ "$success" = false ]; then
        echo "Installation failed after $retries attempts."
        return 1
    fi

    # installation success
    return 0 
}

# ---------------------------------------------------------------------------
: ${DOMAIN?"Need to set DOMAIN"}
[ -z "$PASSWORD" ] && export PASSWORD=redislabs

sudo chmod -R 777 grafana/

apt-get update
apt-get install jq -y

export HOSTNAME=$(hostname -s)
export PASSWORD=$PASSWORD
export HOST_IP=$(hostname -I | awk '{print $1}')

envsubst '${NAVIGATION_BAR}' < nginx.conf.template > nginx.conf
envsubst < ./grafana_config/grafana.ini.template > ./grafana_config/grafana.ini
envsubst < ./prometheus/prometheus.yml.template > ./prometheus/prometheus.yml

export RE_USER=admin@rl.org

#Total hack.  There are instances where /snap/bin is not ready before docker-compose leading to error
#So sleep a little.

while [ ! -x /snap/bin ]; do
    sleep 5
done

docker-compose up -d --build 

main_nodes=( re-n1 )
all_nodes=( re-n1 )
ssh_nodes=( re-n1 loadgen )

for i in "${all_nodes[@]}"
do
   #wait for admin port
   docker cp wait-for-code.sh $i:/tmp/wait-for-code.sh
   docker exec -e URL=https://$i:9443/v1/bootstrap -e CODE=200 $i /bin/bash /tmp/wait-for-code.sh

   #enable port 53
   docker exec --user root --privileged $i /bin/bash /tmp/init_script.sh
done

#create cluster 1
export CLUSTER=re-cluster1.ps-redislabs.org
export IP=172.16.22.21
server="re-n1"

cluster_file="redis/create_cluster.json.template"

envsubst < $cluster_file > create_cluster.json
docker cp create_cluster.json $server:/tmp/create_cluster.json
docker exec $server curl -k -v --silent --fail -H 'Content-Type: application/json' -d @/tmp/create_cluster.json  https://$server:9443/v1/bootstrap/create_cluster

#wait for admin port
docker cp wait-for-code.sh $server:/tmp/wait-for-code.sh
docker exec -e URL=https://$server:9443/v1/bootstrap -e CODE=200 $server /bin/bash /tmp/wait-for-code.sh


#set up ssh for bastion
docker exec terminal sh -c "mkdir ~/.ssh/ && ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -q -N \"\""
rm -rf .sshtmp/
docker cp terminal:/root/.ssh/ .sshtmp/
for i in "${ssh_nodes[@]}"
do
   docker exec --user labuser $i /bin/bash -c "mkdir -p /home/labuser/.ssh"
   docker cp .sshtmp/id_rsa.pub $i:/home/labuser/.ssh/authorized_keys
   docker exec --user root $i /bin/bash -c "chown -R labuser:labuser /home/labuser/.ssh/"
   docker exec terminal sh -c "ssh-keyscan -H $i >> ~/.ssh/known_hosts"
   #docker exec --user labuser $i sh -c "ssh-keyscan -H terminal >> ~/.ssh/known_hosts"
done

for i in "${ssh_nodes[@]}"
do
   docker exec --user labuser $i /bin/bash -c "mkdir -p ~labuser/.ssh"
   docker cp .sshtmp/id_rsa.pub $i:/home/labuser/.ssh/authorized_keys_1
   docker exec --user root $i bash -c "cat /home/labuser/.ssh/authorized_keys_1 >> /home/labuser/.ssh/authorized_keys"
   docker exec --user root $i rm /home/labuser/.ssh/authorized_keys_1
done

docker exec loadgen /usr/sbin/sshd

#update license
if [[ -n $RE1_LICENSE ]];
then
   docker exec re-n1 curl -v -k -d "{\"license\": \"$(echo $RE1_LICENSE | sed -z 's/\n/\\n/g')\"}" -u $RE_USER:$PASSWORD -H "Content-Type: application/json" -X PUT https://localhost:9443/v1/license
fi


#create redis (No Gears)
envsubst < redis/create_target_db.json.template > redis/create_target_db.json
docker cp redis/create_target_db.json re-n1:/tmp/create_target_db.json
sleep 60

docker exec re-n1 curl -sk -u $RE_USER:$PASSWORD -H "Content-type: application/json" -d @/tmp/create_target_db.json -X POST https://localhost:9443/v1/bdbs

sleep 10

#create rdi database
envsubst < redis/create_rdi_db.json.template > redis/create_rdi_db.json
docker cp redis/create_rdi_db.json re-n1:/tmp/create_rdi_db.json
docker exec re-n1 curl -sk -u $RE_USER:$PASSWORD -H "Content-type: application/json" -d @/tmp/create_rdi_db.json -X POST https://localhost:9443/v1/bdbs


sleep 10


# create table in mysql
#docker exec -i mysql mysql -uroot -p${PASSWORD} inventory -e "CREATE TABLE inventory.Track ( TrackId INT PRIMARY KEY, Name VARCHAR(255) NOT NULL, AlbumId INT NOT NULL, MediaTypeId INT NOT NULL, GenreId INT NOT NULL, Composer VARCHAR(255) NOT NULL, Milliseconds INT NOT NULL, Bytes INT NOT NULL, UnitPrice DECIMAL(10,2) NOT NULL);"


docker-compose up -d

sleep 20

#rdi Installation
ORIGINAL_DIR=$(pwd)
echo $ORIGINAL_DIR

RDI_VERSION=1.14.0
if [ ! -f "/content/rdi-installation-$RDI_VERSION.tar.gz" ]; then
    curl --output /content/rdi-installation-$RDI_VERSION.tar.gz -O https://redis-enterprise-software-downloads.s3.amazonaws.com/redis-di/rdi-installation-$RDI_VERSION.tar.gz
else
    echo "File rdi-installation-$RDI_VERSION.tar.gz already exists."
fi
tar -xvf rdi-installation-$RDI_VERSION.tar.gz
sleep 5
cd rdi_install/$RDI_VERSION


#create silent.toml
cat <<EOF > silent.toml
title = "RDI Silent Installer Config"

nameservers = ["8.8.8.8", "8.8.4.4"]

high_availability = false
scaffold = false
deploy = false
db_index = 5
deploy_directory = "/opt/rdi/config"

[rdi.database]
host = "172.16.22.21"
port = 12001
use_existing_rdi = true
password = "redislabs"
ssl = false

[rdi.database.certificates]
ca = "/home/ubuntu/rdi/certs/ca.crt"
cert = "/home/ubuntu/rdi/certs/client.crt"
key = "/home/ubuntu/rdi/certs/client.key"
passphrase = "foobar"

[sources.default]
username = "postgres"
password = "postgres"
ssl = false

[targets.default]
username = ""
password = ""
ssl = false

[targets.default.certificates]
ca = "/home/ubuntu/rdi/certs/ca.crt"
cert = "/home/ubuntu/rdi/certs/client.crt"
key = "/home/ubuntu/rdi/certs/client.key"
passphrase = "foobar"
EOF

sleep 10


if run_rdi_installation; then
   cd $ORIGINAL_DIR

   cd grafana
   bash config_grafana.sh
   cd ..

   #create instructions
   cd about
   bash create_about.sh
   cd ..

else	
   docker-compose up -d
   sleep 10
    
   cd $ORIGINAL_DIR
   cd about
   docker cp error.html nginx:/www/data/index.html   
fi

wait $!
