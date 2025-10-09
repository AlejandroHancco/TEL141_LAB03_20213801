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

# --- Crear namespace si no existe ---
if ip netns list | grep -qw "$NS_NAME"; then
    echo "[INFO] Namespace $NS_NAME ya existe, se reutiliza."
else
    ip netns add "$NS_NAME"
    echo "[INFO] Namespace $NS_NAME creado."
fi

# --- Crear veth si no existen ---
if ! ip link show "$VETH_NS" >/dev/null 2>&1; then
    ip link add "$VETH_NS" type veth peer name "$VETH_OVS"
    echo "[INFO] Interfaces $VETH_NS/$VETH_OVS creadas."
else
    echo "[INFO] Las interfaces $VETH_NS/$VETH_OVS ya existen, se reutilizan."
fi

# --- Mover extremo NS al namespace ---
ip link set "$VETH_NS" netns "$NS_NAME" 2>/dev/null || true

# --- Configurar interfaces ---
ip -n "$NS_NAME" addr flush dev "$VETH_NS"
ip -n "$NS_NAME" addr add "${GATEWAY}/24" dev "$VETH_NS"
ip -n "$NS_NAME" link set "$VETH_NS" up
ip -n "$NS_NAME" link set lo up

# --- Conectar al OvS con VLAN ---
ovs-vsctl --may-exist add-port "$OVS_BR" "$VETH_OVS" tag="$VLAN_ID"
ip link set "$VETH_OVS" up

# --- Manejar dnsmasq ---
TMP_DIR="/tmp/ns_${NS_NAME}"
mkdir -p "$TMP_DIR"
DNSMASQ_PID_FILE="$TMP_DIR/dnsmasq.pid"

# Si hay un dnsmasq corriendo, matarlo
if [[ -f "$DNSMASQ_PID_FILE" ]] && kill -0 $(cat "$DNSMASQ_PID_FILE") 2>/dev/null; then
    echo "[INFO] Matando dnsmasq anterior ($(cat $DNSMASQ_PID_FILE))..."
    kill -9 $(cat "$DNSMASQ_PID_FILE") || true
fi

# Configurar archivo dnsmasq
cat > "$TMP_DIR/dnsmasq.conf" <<EOF
interface=$VETH_NS
dhcp-range=$DHCP_RANGE,12h
dhcp-option=3,$GATEWAY
bind-interfaces
EOF

# Lanzar dnsmasq en el namespace
ip netns exec "$NS_NAME" dnsmasq --conf-file="$TMP_DIR/dnsmasq.conf" --pid-file="$DNSMASQ_PID_FILE"

echo "[OK] dnsmasq iniciado en $NS_NAME"
echo "=== Namespace $NS_NAME creado con VLAN $VLAN_ID ==="
ip netns list

