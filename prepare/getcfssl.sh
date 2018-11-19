#!/bin/bash

VERSION=R1.2
pkgs=(cfssl cfssljson)

for pkg in ${pkgs[@]}
do
    echo "Download ${pkg}..."
    curl -L https://pkg.cfssl.org/${VERSION}/${pkg}_linux-amd64 -o /usr/local/bin/${pkg}
    chmod +x /usr/local/bin/${pkg}
done