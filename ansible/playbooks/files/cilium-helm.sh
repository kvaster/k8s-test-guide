#!/bin/sh

API_SERVER_IP=10.118.12.100
API_SERVER_PORT=6443
CILIUM_VERSION=1.8.0
CILIUM_IF=wan1
TMP=cilium

CILIUM_COMPAT_VERSION=1.7

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
--set global.nodePort.mode=dsr
"

# ipvlan l3s mode
IPVLAN_L3S="
--set global.datapathMode=ipvlan
--set global.ipvlan.masterDevice=${CILIUM_IF}
--set global.tunnel=disabled
--set global.masquerade=true
--set global.autoDirectNodeRoutes=true
--set global.nodePort.enabled=true
--set global.nodePort.mode=dsr
"

# host reachable services
HOST_REACHABLE="
--set global.hostServices.enabled=true
--set global.externalIPs.enabled=true
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
--set global.kubeProxyReplacement=strict
--set config.masquerade=true
--set global.nativeRoutingCIDR=10.244.0.0/16
"

DSR="
--set global.tunnel=disabled
--set global.autoDirectNodeRoutes=true
--set global.nodePort.mode=dsr
"

# global.bpf.mapDynamicSizeRatio
ACCEL="
--set global.nodePort.acceleration=native
"

OPTS="--namespace kube-system --set global.tag=v${CILIUM_VERSION}"
#OPTS="${OPTS} ${MANAGED_ETC}"
#OPTS="${OPTS} ${IPVLAN}"
#OPTS="${OPTS} ${IPVLAN_L3_BPF}"
#OPTS="${OPTS} ${IPVLAN_L3S}"
OPTS="${OPTS} ${DSR}"
OPTS="${OPTS} ${HOST_REACHABLE}"
OPTS="${OPTS} ${NODE_PORT}"
OPTS="${OPTS} ${NO_KUBEPROXY}"

if [ "$1" == "preflight" ]; then
  OPTS="${OPTS} --set preflight.enabled=true --set agent.enabled=false --set config.enabled=false --set operator.enabled=false"
fi

if [ "$1" == "compat" ]; then
  OPTS="${OPTS} --set config.upgradeCompatibility=${CILIUM_COMPAT_VERSION} --set agent.keepDeprecatedProbes=true"
fi

echo helm template cilium cilium/cilium --version ${CILIUM_VERSION} ${OPTS}
helm template cilium cilium/cilium --version ${CILIUM_VERSION} ${OPTS} > cilium.yml
