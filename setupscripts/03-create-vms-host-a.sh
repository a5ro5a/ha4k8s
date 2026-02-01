#!/bin/bash

set -e

# やり直す場合
# for x in ha-master ha-worker1 ha-worker2 ; do virsh shutdown $x ; virsh destroy $x ;  virsh undefine $x  --remove-all-storage ; done

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/env" ]; then
    source "$SCRIPT_DIR/env"
    echo "環境変数を読み込みました"
else
    echo "エラー: $SCRIPT_DIR/env ファイルが見つかりません"
    exit 1
fi

echo "=== host-aのVM作成開始 ==="

# VM定義
declare -A VMS=(
    ["ha-master"]="3072 2 30G $VM_A_MASTER_IP"
    ["ha-worker1"]="4096 2 100G $VM_A_WORKER01_IP"
    ["ha-worker2"]="2048 1 50G $VM_A_WORKER02_IP"
)


# VM作成関数
create_vm() {
    local vm_name=$1
    local memory_mb=$2
    local vcpus=$3
    local disk_gb=$4
    local ip_addr=$5

    # 1. ディスク作成
    DISK_PATH="$IMAGE_DIR/${vm_name}.qcow2"
    if [ ! -f "$DISK_PATH" ]; then
        echo "ディスクを作成中: $disk_gb"
        qemu-img create -f qcow2 \
            -b "$IMAGE_DIR/$TEMPLATE_NAME" \
            -F qcow2 "$DISK_PATH" "$disk_gb"
    fi
    
    # 2. VMが既に存在する場合は削除
    if virsh list --all | grep -q " $vm_name "; then
        echo "既存のVMを削除: $vm_name"
        virsh destroy "$vm_name" 2>/dev/null || true
        virsh undefine "$vm_name" --remove-all-storage 2>/dev/null || true
        sleep 2
    fi
    

    virt-install \
        --name "$vm_name" \
        --memory $memory_mb \
        --vcpus $vcpus \
        --cpu host-passthrough \
        --disk "path=$DISK_PATH,format=qcow2,bus=virtio" \
        --network bridge=$BRIDGE,model=virtio \
        --graphics vnc,listen=0.0.0.0 \
        --console pty,target_type=serial \
        --boot hd \
        --noautoconsole \
        --os-variant "alpinelinux3.13" \
        --features acpi=on,apic=on \
        --clock offset=localtime \
        --import
        #--graphics none \
    
    echo "✓ $vm_name 作成完了"
    sleep 10
}

# メイン実行
for vm_name in "${!VMS[@]}"; do
    IFS=' ' read -r memory vcpu disk ip <<< "${VMS[$vm_name]}"
    create_vm "$vm_name" "$memory" "$vcpu" "$disk" "$ip"
done

# ステータス確認
echo ""
echo "=== host-aのVMステータス ==="
virsh list --all

echo "vncでログインしIPアドレスとhostnameをへんこうしてください"
