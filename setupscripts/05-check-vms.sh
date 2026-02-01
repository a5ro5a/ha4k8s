#!/bin/bash

# host-aで実行

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

echo "=== 全VMの起動確認 ==="

# host-aのVMチェック
echo "--- host-aのVM ---"
for vm in $VM_A_MASTER $VM_A_WORKER01 $VM_A_WORKER02 ; do
    echo -n "$vm: "
    if (export LANG=C ; virsh domstate $vm | grep -q "running"); then
        echo "✓ 起動中"
    else
        echo "✗ 停止中。起動します..."
        virsh start $vm
        sleep 5
    fi
done

# host-bのVMチェック
echo ""
echo "--- host-bのVM ---"
ssh $HOST_B <<'EOF'
for vm in $VM_B_MASTER $VM_B_WORKER01 $VM_B_WORKER02 ; do
    echo -n "$vm: "
    if (export LANG=C ; virsh domstate $vm | grep -q "running"); then
        echo "✓ 起動中"
    else
        echo "✗ 停止中。起動します..."
        virsh start $vm
        sleep 5
    fi
done
EOF

# 接続テスト
echo ""
echo "=== VM接続テスト ==="

TEST_VMS=(
    "$VM_A_MASTER:$VM_A_MASTER_IP"
    "$VM_A_WORKER01:$VM_A_WORKER01_IP"
    "$VM_A_WORKER02:$VM_A_WORKER02_IP"
    "$VM_B_MASTER:$VM_B_MASTER_IP"
    "$VM_B_WORKER01:$VM_B_WORKER01_IP"
    "$VM_B_WORKER02:$VM_B_WORKER02_IP"
)

for vm_info in "${TEST_VMS[@]}"; do
    IFS=':' read -r vm_name vm_ip <<< "$vm_info"
    
    echo -n "$vm_name ($vm_ip): "
    
    # SSH接続テスト
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no k3sadmin@$vm_ip "echo OK" 2>/dev/null; then
        echo "✓ SSH接続成功"
    else
        echo "✗ SSH接続失敗。VMが起動するまで待機..."
        sleep 10
        # 再試行
        if ssh -o ConnectTimeout=10 k3sadmin@$vm_ip "echo OK" 2>/dev/null; then
            echo "✓ 2回目でSSH接続成功"
        else
            echo "✗ SSH接続失敗。手動で確認してください"
        fi
    fi
done

echo "=== VM起動確認完了 ==="
