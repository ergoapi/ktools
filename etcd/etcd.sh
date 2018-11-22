#!/bin/bash

set -e

iplist=$1
ETCD_VERSION="3.3.9"

function etcd_tls(){
ETCD_IPS=""
for node in $(echo $iplist | tr "," "\n" | sort -u)
do
	member="\"$node\""
	if [ -z $ETCD_IPS ];then
		ETCD_IPS=$member
	else
		ETCD_IPS="$ETCD_IPS,$member"
	fi
done
pushd ./conf/ssl
    echo "create etcd ssl"
    if [ ! -z "$iplist" ];then
    cat > etcd-csr.json <<EOF
{
    "key": {
      "algo": "rsa",
      "size": 2048
    },
    "names": [
      {
        "O": "etcd",
        "OU": "etcd Security",
        "L": "Beijing",
        "ST": "Beijing",
        "C": "CN"
      }
    ],
    "CN": "etcd",
    "hosts": [
      "127.0.0.1",
      "localhost",
      ${ETCD_IPS},
      "etcd.ysicing.me",
      "*.etcd.ysicing.me"
    ]
  }
EOF
    fi
    cfssl gencert --initca=true etcd-root-ca-csr.json | cfssljson --bare etcd-root-ca
    cfssl gencert --ca etcd-root-ca.pem --ca-key etcd-root-ca-key.pem --config etcd-gencert.json etcd-csr.json | cfssljson --bare etcd
popd

}

function download(){
    if [ ! -f "etcd-v${ETCD_VERSION}-linux-amd64.tar.gz" ]; then
        wget https://github.com/coreos/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-amd64.tar.gz
        tar -zxvf etcd-v${ETCD_VERSION}-linux-amd64.tar.gz
    fi
}

function preinstall(){
	getent group etcd >/dev/null || groupadd -r etcd
	getent passwd etcd >/dev/null || useradd -r -g etcd -d /var/lib/etcd -s /sbin/nologin -c "etcd user" etcd
}

function install(){
    echo -e "\033[32mINFO: Copy etcd...\033[0m"
	tar -zxvf etcd-v${ETCD_VERSION}-linux-amd64.tar.gz
	cp etcd-v${ETCD_VERSION}-linux-amd64/etcd* /usr/local/bin
	rm -rf etcd-v${ETCD_VERSION}-linux-amd64*

    echo -e "\033[32mINFO: Copy etcd config...\033[0m"
    cp -r conf/ /etc/etcd
    chown -R etcd:etcd /etc/etcd
    chmod -R 755 /etc/etcd/ssl

    echo -e "\033[32mINFO: Copy etcd systemd config...\033[0m"
    cp systemd/*.service /etc/systemd/system
    systemctl daemon-reload
}

function postinstall(){
    if [ ! -d "/var/lib/etcd" ]; then
        mkdir /var/lib/etcd
        chown -R etcd:etcd /var/lib/etcd
    fi
    systemctl enable etcd
    cp etcdcli.sh /usr/local/bin/etcdcli
    chmod +x /usr/local/bin/etcdcli
}

etcd_tls
download
preinstall
install
postinstall
