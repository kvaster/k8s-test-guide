#!/bin/sh

/etc/init.d/keepalived start
rc-update add keepalived

rc-update add kubelet

kubeadm init --config kubeadm.yml --skip-phases=addon/kube-proxy --upload-certs
mkdir -p ~/.kube
cp /etc/kubernetes/admin.conf ~/.kube/config

kubectl taint nodes $(hostname) node-role.kubernetes.io/master:NoSchedule-

