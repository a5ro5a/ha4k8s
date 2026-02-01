# 必ずマスターサーバーが他で動いていることを確認する
cd /opt/postgres-ha
DOCKER_DIR=/opt/postgres-ha

cd $DOCKER_DIR
source ./env

docker stop postgres-`hostname`
sleep 10

\rm -r postgres_data/
sleep 10
docker-compose -p postgres-standby -f docker-compose-postgres-standby.yml up -d
sleep 10
docker exec -it postgres-$(hostname) /scripts/init-standby.sh
docker restart postgres-`hostname`
bash /opt/postgres-ha/scripts/check-role.sh 
PGPASSWORD=$PGPASSWD psql -h $MY_IP -p 5432 -U k3s -d k3s -c 'SELECT current_timestamp, inet_server_addr(), pg_is_in_recovery();'
PGPASSWORD=$PGPASSWD psql -h $OPPOSING_IP -p 5432 -U k3s -d k3s -c 'SELECT current_timestamp, inet_server_addr(), pg_is_in_recovery();'
PGPASSWORD=$PGPASSWD psql -h $VIP -p 6432 -U k3s -d k3s -c 'SELECT current_timestamp, inet_server_addr(), pg_is_in_recovery();'

