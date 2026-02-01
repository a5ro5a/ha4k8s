# K8s High Availability Laboratory

Kubernetesマルチマスタークラスターの高可用性(HA)設定とテスト環境。

## 特徴
- Keepalived + HAProxyによる仮想IPとロードバランシング
- コントロールプレーン冗長化構成
- 各種障害シナリオのテスト用アプリケーション
- 詳細なトラブルシューティングガイド

## 物理構成
```text
tx100s3-01 (Debian 11, 16GB)                tx100s3-02 (Debian 11, 16GB)
├── KVMゲスト1: ha-master1 (3GB)        ├── KVMゲスト1: hb-master (3GB)
├── KVMゲスト2: ha-worker1 (4GB)        ├── KVMゲスト2: hb-worker1 (4GB)
├── KVMゲスト2: ha-worker2 (4GB)        ├── KVMゲスト2: hb-worker2 (4GB)
```

## 論理構成
```text
                [ 高可用性K3sクラスター ] ------------ Keepalived + HAProxyで冗長化
                           ↓
                   [ 外部PostgreSQL ] ------------ Keepalived + HAProxyで冗長化
                (ホストA or B のどちらかで稼働)
                           ↓
          [ ストレージ: Longhorn (4ノード分散) ]
                           ↓
            [ メールサーバー + その他サービス ]
```

## 技術スタック
- QEMU/KVM
- libvirtd/virt-manager
- Kubernetes 1.24+
- Keepalived
- HAProxy
- Containerd
- PostgreSQL
- Debian11,Ubuntu 20.04/22.04,Alpine
- Longhorn

## テスト可能な障害シナリオ
1. コントロールプレーンノード障害
2. ネットワーク分離
3. アプリケーションPodの障害
4. ストレージの障害

## 構成
```text
├── README.md
├── postgres-ha
│   ├── config
│   ├── docker-compose-haproxy.yml
│   ├── docker-compose-postgres-primary.yml
│   ├── docker-compose-postgres-standby.yml
│   ├── env
│   ├── postgres_data
│   ├── scripts
│   └── templates
└── setupscripts
    ├── 01-create-alpine-template.sh
    ├── 02-copy-template-to-host-b.sh
    ├── 03-create-vms-host-a.sh
    ├── 04-create-vms-host-b.sh
    ├── 05-check-vms.sh
    ├── 06-setup-postgres-ha.sh
    ├── 07-deploy-k3s-ha-cluster.sh
    ├── 08-add-k3s-cert-alpine.sh
    ├── env
    └── manage-configs.sh
```

## how to
- こちらのレポジトリで管理していないkeepalived,HAProxyでVRRP構成を先に構築しておく必要があります。(VRRP不要の場合でもk3s冗長化でHAProxyは必要となります。）
- setupscriptsはお好きな場所へ配備してください。
  - k3s/envを環境に合わせて編集
  - 01から順番に実施
- postgres-ha は/opt/へ配備してください。
  - /opt/postgres-ha/envを環境に合わせて編集
  - 06-setup-postgres-ha.sh で構築
