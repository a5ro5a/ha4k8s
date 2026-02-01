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

echo "=== テンプレートをhost-bにコピー ==="

# SCPでコピー
scp -p ${IMAGE_DIR}/alpine-template.qcow2 \
    $HOST_B:${IMAGE_DIR}/.

# host-bでストレージプール設定
# 下記は設定済みのため省略
#ssh $HOST_B <<'EOF'
#sudo virsh pool-define-as default dir - - - - "/v/images"
#sudo virsh pool-start default
#sudo virsh pool-autostart default
#EOF

echo "=== テンプレートコピー完了 ==="
