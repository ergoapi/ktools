#!/bin/bash

CMD="etcdctl --ca-file /etc/etcd/ssl/etcd-root-ca.pem --key-file /etc/etcd/ssl/etcd-key.pem --cert-file /etc/etcd/ssl/etcd.pem"
if [ -z $1 ];then
    ${CMD} cluster-health
else
    ${CMD} ${@}
fi

