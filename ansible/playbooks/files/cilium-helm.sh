#!/bin/sh

API_SERVER_IP=10.118.12.100
API_SERVER_PORT=6443
CILIUM_VERSION=1.9.5
CILIUM_IF=wan0.4000
TMP=cilium

CILIUM_COMPAT_VERSION=1.8

# no kube-proxy
NO_KUBE_PROXY="
--set nodePort.enabled=true
--set k8sServiceHost=$API_SERVER_IP
--set k8sServicePort=$API_SERVER_PORT
--set kubeProxyReplacement=strict
--set nativeRoutingCIDR=10.244.0.0/16
--set masquerade=true
--set ipam.mode=kubernetes
--set bpf.masquerade=true
"
#--set loadBalancer.acceleration=native
#--set devices=${CILIUM_IF}

# host reachable services
HOST_REACHABLE="
--set hostServices.enabled=true
--set externalIPs.enabled=true
"

# direct routing
DIRECT_ROUTING="
--set tunnel=disabled
--set autoDirectNodeRoutes=true
--set nodePort.directRoutingDevice=${CILIUM_IF}
--set endpointRoutes.enabled=false
"

# dsr or not dsr
DSR="
--set loadBalancer.mode=dsr
"

LOCAL="
--set image.repository=registry.kvaster.com/cilium/cilium
--set image.tag=latest
--set image.pullPolicy=Always
--set operator.image.repository=registry.kvaster.com/cilium/operator
--set operator.image.tag=latest
--set operator.image.pullPolicy=Always
"

OPTS="--namespace kube-system --set global.tag=v${CILIUM_VERSION}"
OPTS="${OPTS} ${NO_KUBE_PROXY}"
OPTS="${OPTS} ${HOST_REACHABLE}"
OPTS="${OPTS} ${DIRECT_ROUTING}"
OPTS="${OPTS} ${DSR}"
OPTS="${OPTS} ${LOCAL}"

FILE=cilium.yml

if [ "$1" == "preflight" ]; then
  OPTS="${OPTS} --set preflight.enabled=true --set agent=false --set operator.enabled=false"
  FILE=cilium-preflight.yml
fi

if [ "$1" == "compat" ]; then
  OPTS="${OPTS} --set upgradeCompatibility=${CILIUM_COMPAT_VERSION}"
fi

echo helm template cilium cilium/cilium --version ${CILIUM_VERSION} ${OPTS}
helm template cilium cilium/cilium --version ${CILIUM_VERSION} ${OPTS} > $FILE
