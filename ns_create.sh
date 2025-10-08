#!/usr/bin/env bash
# ==========================================================
# Script: ns_create.sh
# Propósito: Crear un Network Namespace con DHCP y Gateway
# Uso: sudo ./ns_create.sh <NombreNS> <NombreOvS> <VLAN_ID> <RangoDHCP> <Gateway>
# Ejemplo: sudo ./ns_create.sh vlan100 br-int 100 "192.168.100.10-192.168.100.50" 192.168.100.1
# ==========================================================

set -euo pipefail

echo "=== Creando Network Namespace ==="

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Debes ejecutar este script como root (sudo)." >&2
  exit 1
fi

if [[ $# -ne 5 ]]; then
  echo "Uso: $0 <NombreNS> <NombreOvS> <VLAN_ID> <RangoDHCP> <Gateway>" >&2
  exit 1
fi

NS_NAME="$1"
OVS_BR="$2"
VLAN_ID="$3"
DHCP_RANGE="$4"
GATEWAY="$5"

VETH_NS="v${VLAN_ID}-ns"
VETH_OVS="v${VLAN_ID}-ovs"

# Crear par veth
ip link add "$VETH_NS" type veth peer name "$VETH_OVS"

# Crear namespace
ip netns add "$NS_NAME"
ip link set "$VETH_NS" netns "$NS_NAME"

# Configurar interfaz en namespace
ip -n "$NS_NAME" addr add "${GATEWAY}/24" dev "$VETH_NS"
ip -n "$NS_NAME" link set "$VETH_NS" up
ip -n "$NS_NAME" link set lo up

# Conectar al OvS con VLAN tag
ovs-vsctl --may-exist add-port "$OVS_BR" "$VETH_OVS" tag="$VLAN_ID"
ip link set "$VETH_OVS" up

# Configurar DHCP con dnsmasq
mkdir -p /tmp/ns_${NS_NAME}
cat > /tmp/ns_${NS_NAME}/dnsmasq.conf <<EOF
interface=$VETH_NS
dhcp-range=$DHCP_RANGE,12h
dhcp-option=3,$GATEWAY
bind-interfaces
EOF

ip netns exec "$NS_NAME" dnsmasq --conf-file=/tmp/ns_${NS_NAME}/dnsmasq.conf --pid-file=/tmp/ns_${NS_NAME}/dnsmasq.pid

echo "=== Namespace $NS_NAME creado con VLAN $VLAN_ID ==="
ip netns list
