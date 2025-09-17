export GRAFANA_VERSION=$(docker exec grafana grafana server -v | grep -oP 'Version \K[^\s]+')
export RE_VERSION=$(docker exec re-n1 bash -c "curl -u $RE_USER:$PASSWORD https://localhost:9443/v1/nodes -k --fail | jq '.'" | grep software_version | uniq | awk -F ":" '{print $2}' | awk -F '\"' '{print $2}')

export HOST_IP=$(hostname -I | awk '{print $1}')
export RDI_VERSION=$(redis-di --version | awk '{print $NF}')

export IP_INSIGHT=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' redis-insight-2)
export REDIS_INSIGHT_VERSION=$(curl http://$IP_INSIGHT:5540/api/info | awk -F'"appVersion":' '{print $2}' | awk -F ',' '{print $1}' | tr -d '"')

envsubst < index.html.template > about.index.html
envsubst < ../README.template.md > README.md

docker cp README.md nginx:/www/data/README.md
docker cp about.index.html nginx:/www/data/index.html
