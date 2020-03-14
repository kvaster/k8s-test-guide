#!/bin/sh

API_SERVER_IP=10.118.12.100
API_SERVER_PORT=6443
CILIUM_VERSION=1.7.1
CILIUM_IF=wan1
TMP=cilium

OPTS="--namespace kube-system"

# managed etcd
MANAGED_ETC="
--set global.etcd.enabled=true
--set global.etcd.managed=true
"

# ipvlan
IPVLAN="
--set global.datapathMode=ipvlan
--set global.ipvlan.masterDevice=${CILIUM_IF}
--set global.tunnel=disabled
"

# ipvlan L3 bpf mode
IPVLAN_L3_BPF="
--set global.datapathMode=ipvlan
--set global.ipvlan.masterDevice=${CILIUM_IF}
--set global.tunnel=disabled
--set global.masquerade=true
--set global.installIptablesRules=false
--set global.autoDirectNodeRoutes=true
--set global.l7Proxy.enabled=false
--set global.nodePort.enabled=true
"

# ipvlan l3s mode
IPVLAN_L3S="
--set global.datapathMode=ipvlan
--set global.ipvlan.masterDevice=${CILIUM_IF}
--set global.tunnel=disabled
--set global.masquerade=true
--set global.autoDirectNodeRoutes=true
--set global.nodePort.enabled=true
"

# host reachable services
HOST_REACHABLE="
--set global.hostServices.enabled=true
"

# node port
NODE_PORT="
--set global.nodePort.enabled=true
--set global.nodePort.device=${CILIUM_IF}
"

# kube-proxy replacement
NO_KUBEPROXY="
--set global.nodePort.enabled=true
--set global.k8sServiceHost=$API_SERVER_IP
--set global.k8sServicePort=$API_SERVER_PORT
"

OPTS="--namespace kube-system --set global.tag=v${CILIUM_VERSION}"
#OPTS="${OPTS} ${MANAGED_ETC}"
#OPTS="${OPTS} ${IPVLAN}"
#OPTS="${OPTS} ${IPVLAN_L3_BPF}"
#OPTS="${OPTS} ${IPVLAN_L3S}"
OPTS="${OPTS} ${HOST_REACHABLE}"
OPTS="${OPTS} ${NODE_PORT}"
OPTS="${OPTS} ${NO_KUBEPROXY}"

mkdir -p "${TMP}"
if [ ! -d "${TMP}"/cilium-${CILIUM_VERSION} ]; then
  wget --show-progress https://github.com/cilium/cilium/archive/v${CILIUM_VERSION}.tar.gz -O "${TMP}"/cilium-${CILIUM_VERSION}.tar.gz
  tar -C "${TMP}" -xzf "${TMP}"/cilium-${CILIUM_VERSION}.tar.gz
  rm "${TMP}"/cilium-${CILIUM_VERSION}.tar.gz
fi

helm template "${TMP}"/cilium-${CILIUM_VERSION}/install/kubernetes/cilium ${OPTS} > cilium.yaml
