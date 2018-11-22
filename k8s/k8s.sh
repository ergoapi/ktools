#!/bin/bash

set -e

iplist=$1
KUBE_VERSION="1.12.2"

function download_k8s(){
    if [ ! -f "hyperkube_v${KUBE_VERSION}" ]; then
        wget https://storage.googleapis.com/kubernetes-release/release/v${KUBE_VERSION}/bin/linux/amd64/hyperkube -O hyperkube_v${KUBE_VERSION}
        chmod +x hyperkube_v${KUBE_VERSION}
    fi
    cp hyperkube_v${KUBE_VERSION} /usr/local/bin/hyperkube
    ln -s /usr/local/bin/hyperkube /usr/local/bin/kubectl
}

function k8s_ssl(){
    KUBEAPI_IPS=""
    for node in $(echo $iplist | tr "," "\n" | sort -u)
    do
        member="\"$node\""
        if [ -z $KUBEAPI_IPS ];then
            KUBEAPI_IPS=$member
        else
            KUBEAPI_IPS="$KUBEAPI_IPS,$member"
        fi
    done
pushd ./conf/ssl
    echo "create k8s ssl"
    if [ ! -z "$iplist" ];then
    cat > kube-apiserver-csr.json <<EOF
{
    "CN": "kubernetes",
    "hosts": [
        "127.0.0.1",
        "10.254.0.1",
        ${KUBEAPI_IPS},
        "kubeapi.k8s.ysicing.me",
        "*.kubeapi.k8s.ysicing.me",
        "*.kubernetes.master",
        "localhost",
        "kubernetes",
        "kubernetes.default",
        "kubernetes.default.svc",
        "kubernetes.default.svc.cluster",
        "kubernetes.default.svc.cluster.local"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "ST": "BeiJing",
            "L": "BeiJing",
            "O": "k8s",
            "OU": "System"
        }
    ]
}
EOF
    fi
   cfssl gencert --initca=true k8s-root-ca-csr.json | cfssljson --bare k8s-root-ca
   for targetName in kube-apiserver admin kube-proxy; do
    cfssl gencert --ca k8s-root-ca.pem --ca-key k8s-root-ca-key.pem --config k8s-gencert.json --profile kubernetes $targetName-csr.json | cfssljson --bare $targetName
done
   popd

}

function kubecfg(){
    KUBE_APISERVER="https://10.20.20.200:6443"
    BOOTSTRAP_TOKEN=$(head -c 16 /dev/urandom | od -An -t x | tr -d ' ')
    echo "Tokne: ${BOOTSTRAP_TOKEN}"
    pushd ./conf
    cat > token.csv <<EOF
${BOOTSTRAP_TOKEN},kubelet-bootstrap,10001,"system:bootstrappers"
EOF
    echo "Create kubelet bootstrapping kubeconfig..."
# 设置集群参数
kubectl config set-cluster kubernetes \
  --certificate-authority=ssl/k8s-root-ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=bootstrap.kubeconfig
# 设置客户端认证参数
kubectl config set-credentials kubelet-bootstrap \
  --token=${BOOTSTRAP_TOKEN} \
  --kubeconfig=bootstrap.kubeconfig
# 设置上下文参数
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kubelet-bootstrap \
  --kubeconfig=bootstrap.kubeconfig
# 设置默认上下文
kubectl config use-context default --kubeconfig=bootstrap.kubeconfig

echo "Create kube-proxy kubeconfig..."
# 设置集群参数
kubectl config set-cluster kubernetes \
  --certificate-authority=ssl/k8s-root-ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=kube-proxy.kubeconfig
# 设置客户端认证参数
kubectl config set-credentials kube-proxy \
  --client-certificate=ssl/kube-proxy.pem \
  --client-key=ssl/kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig
# 设置上下文参数
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig
# 设置默认上下文
kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig

echo "Create admin kubeconfig..."
kubectl config set-cluster kubernetes \
  --certificate-authority=ssl/k8s-root-ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER}
# 设置客户端认证参数
kubectl config set-credentials admin \
  --client-certificate=ssl/admin.pem \
  --embed-certs=true \
  --client-key=ssl/admin-key.pem
# 设置上下文参数
kubectl config set-context kubernetes \
  --cluster=kubernetes \
  --user=admin
# 设置默认上下文
kubectl config use-context kubernetes
cp  -a  ~/.kube/config ./admin.kubeconfig
# 创建高级审计配置
cat >> audit-policy.yaml <<EOF
# Log all requests at the Metadata level.
apiVersion: audit.k8s.io/v1beta1
kind: Policy
rules:
- level: Metadata
EOF
    popd
}


function preinstall(){
    getent group kube >/dev/null || groupadd -r kube
    getent passwd kube >/dev/null || useradd -r -g kube -d / -s /sbin/nologin -c "Kubernetes user" kube
}

function install_k8s(){
    echo -e "\033[32mINFO: Copy hyperkube...\033[0m"
    cp hyperkube_v${KUBE_VERSION} /usr/bin/hyperkube

    echo -e "\033[32mINFO: Create symbolic link...\033[0m"
    (cd /usr/bin && hyperkube --make-symlinks)

    echo -e "\033[32mINFO: Copy kubernetes config...\033[0m"
    cp -r conf/ /etc/kubernetes
    if [ -d "/etc/kubernetes/ssl" ]; then
        chown -R kube:kube /etc/kubernetes/ssl
    fi

    echo -e "\033[32mINFO: Copy kubernetes systemd config...\033[0m"
    cp systemd/*.service /etc/systemd/system
    systemctl daemon-reload
}

function postinstall(){
    if [ ! -d "/var/log/kube-audit" ]; then
        mkdir /var/log/kube-audit
    fi
    
    if [ ! -d "/var/lib/kubelet" ]; then
        mkdir /var/lib/kubelet
    fi
    if [ ! -d "/usr/libexec" ]; then
        mkdir /usr/libexec
    fi
    if [ ! -d "/var/run/kubernetes" ]; then
        mkdir /var/run/kubernetes
    fi
    chown -R kube:kube /var/log/kube-audit /var/lib/kubelet /usr/libexec /var/run/kubernetes
}

function run(){
    systemctl daemon-reload
    systemctl start kube-apiserver
    systemctl start kube-controller-manager
    systemctl start kube-scheduler
    systemctl enable kube-apiserver
    systemctl enable kube-controller-manager
    systemctl enable kube-scheduler
}

download_k8s
k8s_ssl
kubecfg
preinstall
install_k8s
postinstall
run