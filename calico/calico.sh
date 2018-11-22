#!/bin/bash

set -e

K8S_MASTER_IP=${1:-10.20.20.200}
ETCD_ENDPOINTS=${2:-https://10.20.20.200:2379}
CALICO_VERSION="v3.3.1"

if [ -f "rbac.yaml" ];then
    kubectl apply -f ./rbac.yaml
else
    kubectl apply -f https://docs.projectcalico.org/v3.3/getting-started/kubernetes/installation/rbac.yaml
fi

HOSTNAME=`cat /etc/hostname`
ETCD_CERT=`cat /etc/etcd/ssl/etcd.pem | base64 | tr -d '\n'`
ETCD_KEY=`cat /etc/etcd/ssl/etcd-key.pem | base64 | tr -d '\n'`
ETCD_CA=`cat /etc/etcd/ssl/etcd-root-ca.pem | base64 | tr -d '\n'`

cp calico.example.yaml calico.yaml

sed -i "s@.*etcd_endpoints:.*@\ \ etcd_endpoints:\ \"${ETCD_ENDPOINTS}\"@gi" calico.yaml

sed -i "s@.*etcd-cert:.*@\ \ etcd-cert:\ ${ETCD_CERT}@gi" calico.yaml
sed -i "s@.*etcd-key:.*@\ \ etcd-key:\ ${ETCD_KEY}@gi" calico.yaml
sed -i "s@.*etcd-ca:.*@\ \ etcd-ca:\ ${ETCD_CA}@gi" calico.yaml

sed -i 's@.*etcd_ca:.*@\ \ etcd_ca:\ "/calico-secrets/etcd-ca"@gi' calico.yaml
sed -i 's@.*etcd_cert:.*@\ \ etcd_cert:\ "/calico-secrets/etcd-cert"@gi' calico.yaml
sed -i 's@.*etcd_key:.*@\ \ etcd_key:\ "/calico-secrets/etcd-key"@gi' calico.yaml

sed -i "s@K8S_MASTER_IP@${K8S_MASTER_IP}@gi" calico.yaml

wget https://github.com/projectcalico/calicoctl/releases/download/${CALICO_VERSION}/calicoctl-linux-amd64 -O /usr/bin/calicoctl
chmod +x /usr/bin/calicoctl

cp -a conf/ /etc/calico
cp -a /etc/etcd/ssl /etc/calico/ssl

kubectl apply -f ./calico.yaml

cp -a systemd/calico.service /etc/systemd/system/calico.service
systemctl daemon-reload
systemctl enable calico
systemctl start calico


sleep 60

cat << EOF >> /tmp/demo.deploy.yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: demo
  template:
    metadata:
      labels:
        app: demo
    spec:
      containers:
      - name: demo
        image: spanda/demo
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
EOF

kubectl create -f /tmp/demo.deploy.yml