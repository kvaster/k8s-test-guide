#!/bin/sh

mkdir -p ~/.kube
cp /etc/kubernetes/admin.conf ~/.kube/config

kubectl taint nodes $(hostname) node-role.kubernetes.io/control-plane:NoSchedule-

/etc/init.d/keepalived start
rc-update add keepalived
rc-update add kubelet

