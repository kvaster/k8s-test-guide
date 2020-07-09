#!/bin/sh

API_SERVER_IP=10.118.12.100
API_SERVER_PORT=6443
CILIUM_VERSION=1.8.1
CILIUM_IF=wan1
TMP=cilium

CILIUM_COMPAT_VERSION=1.7

# no kube-proxy
NO_KUBE_PROXY="
--set global.nodePort.enabled=true
--set global.k8sServiceHost=$API_SERVER_IP
--set global.k8sServicePort=$API_SERVER_PORT
--set global.kubeProxyReplacement=strict
--set global.nativeRoutingCIDR=10.244.0.0/16
--set global.masquerade=true
"

NO_BPF_MASQ="
--set config.bpfMasquerade=false
"

# host reachable services
HOST_REACHABLE="
--set global.hostServices.enabled=true
--set global.externalIPs.enabled=true
"

# direct routing
DIRECT_ROUTING="
--set global.tunnel=disabled
--set global.autoDirectNodeRoutes=true
--set global.nodePort.directRoutingDevice=${CILIUM_IF}
"

# dsr or not dsr
DSR="
--set global.nodePort.mode=dsr
"

OPTS="--namespace kube-system --set global.tag=v${CILIUM_VERSION}"
OPTS="${OPTS} ${NO_KUBE_PROXY}"
OPTS="${OPTS} ${NO_BPF_MASQ}"
OPTS="${OPTS} ${HOST_REACHABLE}"
OPTS="${OPTS} ${DIRECT_ROUTING}"
OPTS="${OPTS} ${DSR}"

if [ "$1" == "preflight" ]; then
  OPTS="${OPTS} --set preflight.enabled=true --set agent.enabled=false --set config.enabled=false --set operator.enabled=false"
fi

if [ "$1" == "compat" ]; then
  OPTS="${OPTS} --set config.upgradeCompatibility=${CILIUM_COMPAT_VERSION} --set agent.keepDeprecatedProbes=true"
fi

echo helm template cilium cilium/cilium --version ${CILIUM_VERSION} ${OPTS}
helm template cilium cilium/cilium --version ${CILIUM_VERSION} ${OPTS} > cilium.yml
