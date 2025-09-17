#using RE since grafana image doesn't have curl

docker cp prom_ds.json re-n1:/tmp/
docker exec re-n1 curl -k -v --silent --fail -H 'Content-Type: application/json' -d @/tmp/prom_ds.json  http://admin:${PASSWORD}@grafana:3000/api/datasources

docker cp loki_ds.json re-n1:/tmp/
docker exec re-n1 curl -k -v --silent --fail -H 'Content-Type: application/json' -d @/tmp/loki_ds.json  http://admin:${PASSWORD}@grafana:3000/api/datasources

#Note that for CRDB.json, you need to set id=null for the root dashboard, if the file changes.
all_dashboards=( database.json node.json cluster.json debezium-dashboard.json postgres_exporter.json rdi_dashboard.json )

for i in "${all_dashboards[@]}"
do 
	echo '{"dashboard":' > tmp.$i
	cat $i >> tmp.$i
	echo ',"inputs":[{"name":"DS_PROMETHEUS1", "type":"datasource", "pluginId": "prometheus", "value": "Prometheus"}]' >> tmp.$i
	echo ',"overwrite": true' >> tmp.$i
	echo '}' >> tmp.$i

	sed -i 's/now\-7d/now\-1h/g' tmp.$i

	docker cp tmp.$i re-n1:/tmp/$i

	docker exec re-n1 curl -k -v --silent --fail -H 'Content-Type: application/json' -d @/tmp/$i  http://admin:${PASSWORD}@grafana:3000/api/dashboards/import
done
