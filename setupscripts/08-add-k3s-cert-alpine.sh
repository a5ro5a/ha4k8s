#!/bin/bash

set -e

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/env" ]; then
    source "$SCRIPT_DIR/env"
    echo "環境変数を読み込みました"
else
    echo "エラー: $SCRIPT_DIR/env ファイルが見つかりません"
    exit 1
fi

for master in $VM_A_MASTER_IP $VM_B_MASTER_IP ; do
    echo "修正: $master"
    #ssh k3sadmin@$master "sudo sed -e \"/'--tls-san'/{n;s/'$VIP,$EXTERNAL_IP'/'$VIP,$EXTERNAL_IP,更に追加する場合はここを変更する'/}\" /etc/init.d/k3s"
    ssh k3sadmin@$master "sudo sed -i \"/'--tls-san'/{n;s/'$VIP'/'$VIP,$EXTERNAL_IP'/}\" /etc/init.d/k3s && sudo rc-service k3s restart"
done
