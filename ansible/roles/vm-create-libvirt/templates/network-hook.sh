#!/bin/sh

vlan={{ if_list[1].name | regex_replace('(.*)\.(.*)', '\2') }}

if [[ "$1" == "k8s-1" ]] && [[ "$2" == "started" ]]; then
  iface=$(cat - | xmllint --nocdata --xpath "string(/hookData/network/bridge/@name)" -)
  ip link add link ${iface} name ${iface}.${vlan} type vlan id ${vlan}
  ip addr add {{ subnet_ext }}.1/24 dev ${iface}.${vlan}
  ip link set dev ${iface}.${vlan} up
  ip route add {{ subnet_virt }}.0/24 via {{ subnet_ext }}.1 dev ${iface}.${vlan}
fi
