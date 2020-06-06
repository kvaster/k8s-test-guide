#!/bin/sh

kubeadm reset -f

rm -rf /etc/cni/net.d
rm /opt/cni/bin/cilium*

rm /var/log/kubelet/kubelet.log
rc-update del kubelet

crictl rm -af
/etc/init.d/containerd stop
rm /var/log/containerd/containerd.log

/etc/init.d/keepalived stop
rc-update del keepalived

