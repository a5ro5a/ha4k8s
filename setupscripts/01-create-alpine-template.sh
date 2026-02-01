#!/bin/bash
# host1で実施

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

echo "=== Alpine Linux VMテンプレート作成（完全版） ==="
echo "このスクリプトは以下の処理を自動実行します："
echo "1. ISOダウンロード"
echo "2. VM作成とインストール"
echo "3. SSH経由での自動設定"
echo "4. VM停止"
echo "5. テンプレート作成"

VM_NAME="alpine-installer"
TEMPLATE_NAME="alpine-template.qcow2"

echo "=== Alpine Linux VMテンプレート作成 ==="


# Alpine Linux 3.23 のダウンロード
# ==================== 1. ISO準備 ====================
cd $OS_DIR
echo ""
echo "1. ISOファイル準備..."
# https://dl-cdn.alpinelinux.org/alpine/
ALPINE_VERSION_MAJOR="3.23"
ALPINE_VERSION_MINER="2"
ALPINE_VERSION="${ALPINE_VERSION_MAJOR}.${ALPINE_VERSION_MINER}"
ISO_FILE="alpine-virt-${ALPINE_VERSION}-x86_64.iso"

if [ ! -f "$ISO_FILE" ]; then
    echo "Alpine Linux ${ALPINE_VERSION} をダウンロード中..."
    wget -q --show-progress \
        "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION_MAJOR}/releases/x86_64/$ISO_FILE"
    echo "✓ ダウンロード完了"
else
    echo "✓ 既存のISOを使用: $ISO_FILE"
fi

# ==================== 2. ディスク作成 ====================
echo ""
echo "2. 仮想ディスク作成..."

# 既存のVMがあればクリーンアップ
virsh destroy "$VM_NAME" 2>/dev/null || true
virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true

cd "$WORK_DIR"
DISK_FILE="${VM_NAME}.qcow2"
rm -f "$DISK_FILE"
echo "テンプレートディスクを作成中..."
qemu-img create -f qcow2 "$DISK_FILE" 10G
echo "✓ ディスク作成完了: $DISK_FILE"

# ==================== 4. network-config.yaml作成 ====================
echo "4. network-config.yaml作成..."
mkdir -p /tmp/alpine-setup

cat > /tmp/alpine-setup/network-config.yaml <<'EOF'
version: 2
ethernets:
  eth0:
    dhcp4: true
    dhcp6: false
EOF

# クラウド-init用設定
cat > /tmp/alpine-setup/user-data.yaml << EOF
hostname: $VM_NAME
EOF

# meta-dataも必要
cat > /tmp/alpine-setup/meta-data << EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

# ==================== 5. seed.iso作成 ====================
echo "5. seed.iso作成..."
cloud-localds -N /tmp/alpine-setup/network-config.yaml \
    /tmp/alpine-setup/seed.iso \
    /tmp/alpine-setup/user-data.yaml \
    /tmp/alpine-setup/meta-data

# ==================== 6. VM作成とインストール ====================
echo ""
echo "3. VM作成とAlpineインストール開始..."

virt-install \
    --name "$VM_NAME" \
    --memory 1024 \
    --vcpus 2 \
    --disk "path=$DISK_FILE,format=qcow2" \
    --disk "path=/tmp/alpine-setup/seed.iso,device=cdrom" \
    --cdrom "$OS_DIR/$ISO_FILE" \
    --network "bridge=$BRIDGE" \
    --graphics vnc,listen=0.0.0.0 \
    --noautoconsole \
    --os-variant "alpinelinux3.13" \
    --features acpi=on,apic=on \
    --clock offset=localtime \
    --controller type=scsi,model=virtio-scsi \
    --boot cdrom \
    --import

# note
# how to get os-variant
# apt install libosinfo-bin
# osinfo-query os --fields short-id,name,version | grep -i alpine

echo ""
echo "========================================"
echo "✅ VM作成完了！"
echo "========================================"
echo ""
echo "次の手順を実行してください:"
echo ""
echo "1. VNCで接続:"
echo "   virsh vncdisplay $VM_NAME"
echo ""
echo "2. Alpineを手動インストール（VNC内で）:"
echo ""
echo "   a. login: root (パスワードなし)"
echo "   b. setup-alpine コマンドを実行"
echo ""
echo "  Keymap"
echo "  Select keyboard layout: [none] jp"
echo "  Hostname: $VM_NAME"
echo " テンプレートなのでDHCPのままにする。"
echo "Which one do you want to initialize? (or '?' or 'done') [eth0]"
echo "Ip address for eth0? (or 'dhcp', 'none') [dhcp]"
echo "Do you want to do any manual network configuration? (y/n) [n]"
echo "Timezone : Asia/Tokyo"
echo "      - パスワード: （空でOK）"
echo " APK Mirror"
echo " (c)    Community repo enable これをいれないと各パッケージが入らない"
echo "Enter mirror number or URL: [1] "
echo " User"
echo "Setup a user? (enter a lower-case loginname, or 'no') [no] Full name for user k3sadmin"
echo ""
echo "install先デバイスの指定"
echo "sda を選択して「sys」でインストール（フォーマット）"
echo "これをやらないとOS書き込みされません。"
echo ""

read -p "VNCでの設定完了後 poweroff してください。、Enterを押してください..." -n 1 -r
read -p "インストール完了再起動後に追加パッケージ、設定を行います。" -n 1 -r

# 起動順序変更
echo "VM停止を確認..."
for i in {1..30}; do
    STATE=$(LANG=C ; virsh domstate "$VM_NAME" 2>/dev/null || echo "not found")
    if [ "$STATE" = "shut off" ]; then
        echo "✓ VM停止完了"
        break
    fi
    
    if [ $i -eq 15 ]; then
        echo "⚠ VMが停止しません"
        echo "手動で停止: virsh destroy $VM_NAME"
        virsh destroy "$VM_NAME" 2>/dev/null || true
    fi
    
    sleep 2
done

virsh dumpxml $VM_NAME > /tmp/$VM_NAME.xml
cp -ip /tmp/${VM_NAME}.xml{,.bk}
sed -ie "s#boot dev='cdrom'#boot dev='hd'#" /tmp/$VM_NAME.xml
diff alpine-installer.xml{,.bk}
virsh define /tmp/${VM_NAME}.xml

virsh start ${VM_NAME}
echo "   virsh vncdisplay $VM_NAME"

echo "   別のセッションから下記を実行してください。
# ==================== 7. SSH接続とmanual設定 ====================
ssh-copy-id k3sadmin@対象alpineserver-ip-address
ssh k3sadmin@対象alpineserver-ip-address
su
apk update
apk add docker curl bash sudo htop tmux e2fsprogs e2fsprogs-extra bridge
apk add cloud-init cloud-utils cloud-utils-growpart
# 自動起動設定
rc-update add docker boot
rc-update add cloud-init default
rc-update add cloud-init-local boot
rc-update add cloud-config default
rc-update add cloud-final default
service docker start
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
echo 'br_netfilter' >> /etc/modules 
modprobe br_netfilter
echo "net.bridge.bridge-nf-call-iptables = 1" >> /etc/sysctl.conf
echo "net.bridge.bridge-nf-call-ip6tables = 1" >> /etc/sysctl.conf

cat <<END>/etc/cloud/cloud.cfg.d/99_disable_metadata.cfg
# メタデータサーバーの無効化
datasource_list: [NoCloud, ConfigDrive]
disable_ec2_metadata: true
END

cat <<END>/etc/cloud/cloud.cfg.d/99_nocloud.cfg
datasource_list: [NoCloud]
datasource:
  NoCloud:
    seedfrom: /dev/sr0
    fs_label: cidata
END

poweroff
"

read -p "インストール完了後、Enterを押してください..." -n 1 -r
# ==================== 8. テンプレート作成 ====================
echo "8. VM停止を確認..."
for i in {1..30}; do
    STATE=$(LANG=C ; virsh domstate "$VM_NAME" 2>/dev/null || echo "not found")
    if [ "$STATE" = "shut off" ]; then
        echo "✓ VM停止完了"
        break
    fi
    
    if [ $i -eq 15 ]; then
        echo "⚠ VMが停止しません"
        echo "手動で停止: virsh destroy $VM_NAME"
        virsh destroy "$VM_NAME" 2>/dev/null || true
    fi
    
    sleep 2
done

# ==================== 9. テンプレート作成 ====================
echo "9. テンプレート作成..."
TEMPLATE_PATH="$WORK_DIR/$TEMPLATE_NAME"
if [ -f "$DISK_FILE" ]; then
    echo "ディスクをコピー: $DISK -> $TEMPLATE_PATH"
    cp "$DISK_FILE" "$TEMPLATE_PATH"
    
    # ディスク最適化
    echo "ディスクを最適化..."
    qemu-img convert -O qcow2 -c "$TEMPLATE_PATH" "${TEMPLATE_PATH}.tmp"
    mv "${TEMPLATE_PATH}.tmp" "$TEMPLATE_PATH"
    
    echo "✓ テンプレート作成完了: $TEMPLATE_PATH"
else
    echo "✗ ソースディスクが見つかりません: $DISK_FILE"
    exit 1
fi
# ==================== 10. クリーンアップ ====================
echo "10. クリーンアップ..."
virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
rm -rf /tmp/alpine-setup
rm -f "$DISK_FILE" 2>/dev/null || true

# ==================== 11. 最終確認 ====================
echo ""
echo "========================================"
echo "✅ Alpine Linux テンプレート作成完了！"
echo "========================================"
echo ""
echo "📋 テンプレート情報:"
ls -lh "$TEMPLATE_PATH"
echo ""
qemu-img info "$TEMPLATE_PATH" | head -5
echo ""
echo ""
echo "🚀 次のステップ:"
echo "1. host-bにコピー:"
echo "   scp '$TEMPLATE_PATH' host-b:'$WORK_DIR/'"
echo ""
echo "2. VM作成スクリプトを実行:"
echo "   bash 03-create-vms-host-a.sh"
echo "   bash 04-create-vms-host-b.sh"
