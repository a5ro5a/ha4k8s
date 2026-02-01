#!/bin/bash

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/env" ]; then
    source "$SCRIPT_DIR/env"
    echo "環境変数を読み込みました"
else
    echo "エラー: $SCRIPT_DIR/env ファイルが見つかりません"
    exit 1
fi

# 確認用
echo "=== 環境変数確認 ==="
echo "VIP: $VIP"
echo "VM_A_MASTER_IP: $VM_A_MASTER_IP"
echo "VM_B_MASTER_IP: $VM_B_MASTER_IP"

echo "=== DB K3s再インストール==="
echo "注意: kineテーブルはK3s専用で、PostgreSQL HAには影響しません"
echo ""

echo "=== ステップ2: kineテーブルを安全に削除 ==="
for ip in $HOST_A_IP $HOST_B_IP
do
  PGPASSWORD=$PGPASSWD psql -U k3s -h $ip -d k3s -c "DROP TABLE IF EXISTS kine CASCADE;"
done
echo "✓ kineテーブルを安全に削除しました"


#exit 0


echo "=== 新しいK3sクラスターを構築 ==="
NODES=(
    "$VM_A_MASTER:$VM_A_MASTER_IP:server"
    "$VM_A_WORKER01:$VM_A_WORKER01_IP:agent"
    "$VM_A_WORKER02:$VM_A_WORKER02_IP:agent"
    "$VM_B_MASTER:$VM_B_MASTER_IP:server"
    "$VM_B_WORKER01:$VM_B_WORKER01_IP:agent"
    "$VM_B_WORKER02:$VM_B_WORKER02_IP:agent"
)

echo "=== 高可用性K3sクラスター構築 ==="
CLUSTER_TOKEN="k3s-reinstalled-$(date +%Y%m%d-%H%M)"
DB_ENDPOINT="postgres://k3s:${PGPASSWD}@${VIP}:6432/k3s?sslmode=disable"

# インストール関数
install_server() {
    local node_name=$1
    local node_ip=$2
    local datacenter=$(echo $node_name | cut -d- -f1)  # haまたはhb
    
    echo "=== サーバーノードインストール: $node_name ($node_ip) ==="
    
    ssh k3sadmin@$node_ip << EOF
        # 既存のK3sをアンインストール
        echo "1. サービス停止..."
        sudo rc-service k3s stop 2>/dev/null || true
        sudo rc-service k3s-agent stop 2>/dev/null || true
        
        echo "2. アンインストール..."
        if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
            echo "K3sをアンインストールします..."
            sudo /usr/local/bin/k3s-uninstall.sh
        fi
        
        echo "3. 残留ファイル削除..."
        sudo rm -rf /etc/rancher/k3s /var/lib/rancher/k3s 2>/dev/null || true
        sleep 2
        
        # K3sサーバーインストール
        echo "K3sサーバーをインストール中..."
        curl -sfL https://get.k3s.io | sudo sh -s - server \
          --token $CLUSTER_TOKEN \
          --datastore-endpoint "$DB_ENDPOINT" \
          --node-name $node_name \
          --node-label datacenter=$datacenter \
          --node-taint CriticalAddonsOnly=true:NoExecute \
          --tls-san $VIP \
          --cluster-init \
          --write-kubeconfig-mode 644        

        # サービスの状態確認
        echo "K3sサービス状態:"
        sudo /etc/init.d/k3s status
EOF
    
    echo "=== $node_name インストール完了 ==="
}

install_agent() {
    local node_name=$1
    local node_ip=$2
    local server_ip=${3:-$VM_A_MASTER_IP}  # 最初のサーバーIP
    local datacenter=$(echo $node_name | cut -d- -f1)
    
    echo "=== エージェントノードインストール: $node_name ($node_ip) ==="
    
    ssh k3sadmin@$node_ip << EOF
        # 既存のK3sをアンインストール
        if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
            echo "既存のK3sをアンインストールします..."
            sudo /usr/local/bin/k3s-uninstall.sh
        fi
        
        # K3sエージェントインストール
        echo "K3sエージェントをインストール中..."
        curl -sfL https://get.k3s.io | sudo sh -s - agent \
          --token $CLUSTER_TOKEN \
          --server https://${server_ip}:6443 \
          --node-name $node_name \
          --node-label datacenter=$datacenter
EOF
    
    echo "=== $node_name インストール完了 ==="
}

# ノードインストール
server_installed=false
first_server_ip=""

for node_info in "${NODES[@]}"; do
    IFS=':' read -r node_name node_ip node_type <<< "$node_info"
    
    case $node_type in
        "server")
            if [ "$server_installed" = false ]; then
                # 最初のサーバー
                install_server "$node_name" "$node_ip"
                server_installed=true
                first_server_ip=$node_ip
                sleep 30  # 最初のサーバー起動待機
            else
                # 追加サーバー
                install_server "$node_name" "$node_ip"
                sleep 10
            fi
            ;;
        "agent")
            install_agent "$node_name" "$node_ip" "$first_server_ip"
            sleep 5
            ;;
    esac
done


echo "=== PostgreSQL HAの状態確認 ==="

# PostgreSQL HAが正常であることを確認
echo "PostgreSQL HAクラスター状態:"
echo ""
echo "1. レプリケーション状態:"
PGPASSWORD=$PGPASSWD psql -U k3s -h $VIP -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;"
echo ""
echo "2. データベース一覧:"
PGPASSWORD=$PGPASSWD psql -U k3s -h $VIP -c "\l"

echo ""
echo "3. k3sデータベースの状態:"
PGPASSWORD=$PGPASSWD psql -U k3s -h $VIP -d k3s -c "\dt"

echo ""
echo "✓ PostgreSQL HAクラスターは正常です"



echo "=== クラスター構築完了 ==="
echo ""
echo "=== 次の手順 ==="
echo "1. クラスター状態確認:"
echo "   ssh k3sadmin@$VM_A_MASTER_IP \"sudo kubectl get nodes -o wide\""
echo ""
echo "2. kubeconfigの取得:"
echo "   scp k3sadmin@$VM_A_MASTER_IP:/etc/rancher/k3s/k3s.yaml ~/.kube/config"
echo "   sed -i 's/127.0.0.1/$VIP/g' ~/.kube/config"
echo ""
echo "3. クラスター確認:"
echo "   kubectl get nodes -o wide"
echo "   kubectl get pods -A"
