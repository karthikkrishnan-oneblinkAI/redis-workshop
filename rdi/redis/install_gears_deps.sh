source /etc/opt/redislabs/redislabs_env_config.sh
mkdir -p $modulesdatadir/rg/10206/deps/
tar -xf /tmp/redisgears-jvm.Linux-ubuntu18.04-x86_64.1.2.6.tgz -C $modulesdatadir/rg/10206/deps
tar -xf /tmp/redisgears-python.Linux-ubuntu18.04-x86_64.1.2.6.tgz -C $modulesdatadir/rg/10206/deps
chown -R $osuser:$osuser $modulesdatadir/
