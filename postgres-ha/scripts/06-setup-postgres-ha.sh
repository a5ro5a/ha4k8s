#!/bin/bash

set -e


DOCKER_DIR=/opt/postgres-ha

cd $DOCKER_DIR
source ./env

##############################################
# docker-compose haproxy
##############################################
TEMPLATE_FILE=templates/docker-compose-haproxy.yml.template
FILE=docker-compose-haproxy.yml
export HAPROXY_VERSION
envsubst < "$TEMPLATE_FILE" > "$FILE"

##############################################
# haproxy.cfg
##############################################
TEMPLATE_FILE=templates/haproxy.cfg.template
FILE=config/haproxy.cfg
export VIP OPPOSING_IP
envsubst < "$TEMPLATE_FILE" > "$FILE"

##############################################
# docker-compose postgresql primary
##############################################
TEMPLATE_FILE=templates/docker-compose-postgres-primary.yml.template
FILE=docker-compose-postgres-primary.yml
export PGSQL_VERSION PGPASSWD HOSTNAME
envsubst < "$TEMPLATE_FILE" > "$FILE"

##############################################
# docker-compose postgresql standby
##############################################
TEMPLATE_FILE=templates/docker-compose-postgres-standby.yml.template
FILE=docker-compose-postgres-standby.yml
export OPPOSING_IP PGREPLICAPASSWD PGSQL_VERSION PGPASSWD HOSTNAME OPPOSING_IP PGREPLICAPASSWD
envsubst '${PGREPLICAPASSWD} ${PGSQL_VERSION} ${PGPASSWD} ${HOSTNAME} ${OPPOSING_IP} ${PGREPLICAPASSWD}' < "$TEMPLATE_FILE" > "$FILE"

##############################################
# init-db.sh
##############################################
TEMPLATE_FILE=templates/init-db.sh.template
FILE=scripts/init-db.sh
export PGPASSWD PGREPLICAPASSWD
envsubst '${PGPASSWD} ${PGREPLICAPASSWD}' < "$TEMPLATE_FILE" > "$FILE"

##############################################
# init-standby.sh
##############################################
TEMPLATE_FILE=templates/init-standby.sh.template
FILE=scripts/init-standby.sh
export OPPOSING_IP PGREPLICAPASSWD
envsubst '${OPPOSING_IP} ${PGREPLICAPASSWD} < "$TEMPLATE_FILE" > "$FILE"

##############################################
# primary 昇格スクリプト
##############################################
TEMPLATE_FILE=templates/promote-to-primary.sh.template
FILE=scripts/promote-to-primary.sh
#そのまま使える
cp -p $TEMPLATE_FILE $FILE

##############################################
# standby 降格スクリプト
##############################################
TEMPLATE_FILE=templates/demote-to-standby.sh.template
FILE=scripts/demote-to-standby.sh
export OPPOSING_IP PGREPLICAPASSWD
envsubst '${OPPOSING_IP} ${PGREPLICAPASSWD}' < "$TEMPLATE_FILE" > "$FILE"

##############################################
# check script
##############################################
TEMPLATE_FILE=templates/check-role.sh.template
FILE=scripts/check-role.sh
export VIP
envsubst '${VIP}' < "$TEMPLATE_FILE" > "$FILE"

#############################################
# スクリプトに実行権限を付与
#############################################
chmod +x /opt/postgres-ha/scripts/*.sh

#############################################
# host-bに設定ファイルをコピー
#############################################
# start_do_not_rsync_on_host-b_to_host-a
rsync --delete -avz $DOCKER_DIR/ -e ssh $OPPOSING_IP:$DOCKER_DIR/ \
  --exclude="postgres_data" \
  --exclude="*.log" \
  --exclude="*.pid"

# host-b用にconfigファイルを調整
ssh $OPPOSING_IP "sed -i -e '/OPPOSING_IP/s/${OPPOSING_IP}/${MY_IP}/' \
  -e '/MY_IP/s/${MY_IP}/${OPPOSING_IP}/' \
  ${DOCKER_DIR}/env"

# host-bからhost-aへ同期させない対応
ssh $OPPOSING_IP "sed -i '/start_do_not_rsync_on_host-b_to_host-a/,/end_do_not_rsync_on_host-b_to_host-a/s/^/#/' $DOCKER_DIR/scripts/06-setup-postgres-ha.sh"

echo "host-b にて $DOCKER_DIR/env 確認してください。"
# end_do_not_rsync_on_host-b_to_host-a

#############################################
# keepalived 完了後
#############################################
echo "起動"
echo "VIPがlistenしているホストにて"
echo "cd /opt/postgres-ha"
echo "docker-compose -p postgres-primary -f docker-compose-postgres-primary.yml up -d"
#echo "init"
#echo "./scripts/init-db.sh"
echo "docker exec -it postgres-\$(hostname) /scripts/init-db.sh"
echo ""
echo "対向ホスト にて"
echo "cd /opt/postgres-ha"
echo "docker-compose -p postgres-standby -f docker-compose-postgres-standby.yml up -d"
#echo "init"
#echo "./scripts/init-standby.sh"
echo "docker exec -it postgres-\$(hostname) /scripts/init-standby.sh"
echo "standby を反映させるため再起動"
echo "docker restart postgres-\$(hostname)"

echo "VIP接続テスト:"
echo "PGPASSWORD=$PGPASSWD psql -h $VIP -p 6432 -U k3s -d k3s -c 'SELECT current_timestamp, inet_server_addr(), pg_is_in_recovery();'"

