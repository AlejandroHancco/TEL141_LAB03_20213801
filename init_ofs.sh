#!/usr/bin/env bash
# ==========================================================
# Script: init_ofs.sh
# Propósito: Inicializar el OpenFlow Switch (OFS) para VLANs
# Uso: sudo ./init_ofs.sh <NombreOvS> <puerto1> [puerto2 ...]
# ==========================================================

set -euo pipefail

echo "=== Inicializando OpenFlow Switch (OFS) ==="

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Debes ejecutar este script como root (sudo)." >&2
  exit 1
fi

if [[ $# -lt 2 ]]; then
  echo "Uso: $0 <NombreOvS> <puerto1> [puerto2 ...]" >&2
  exit 1
fi

NOMBRE_OVS="$1"
shift
PUERTOS=("$@")

# Crear OvS si no existe
if ovs-vsctl br-exists "$NOMBRE_OVS"; then
  echo "[INFO] El bridge $NOMBRE_OVS ya existe."
else
  echo "[INFO] Creando bridge $NOMBRE_OVS..."
  ovs-vsctl add-br "$NOMBRE_OVS"
fi

# Agregar puertos físicos (trunk)
for P in "${PUERTOS[@]}"; do
  if ip link show "$P" >/dev/null 2>&1; then
    ip addr flush dev "$P"
    ovs-vsctl --may-exist add-port "$NOMBRE_OVS" "$P"
    ovs-vsctl set port "$P" trunk=0-4094
    ip link set "$P" up
  fi
done

# Crear gateways por VLAN (para salida a Internet)
for VLAN in 100 200 300; do
  VLAN_IF="vlan${VLAN}"
  ip link add link "$NOMBRE_OVS" name "$VLAN_IF" type vlan id "$VLAN" || true
  ip addr add "192.168.${VLAN}.1/24" dev "$VLAN_IF" || true
  ip link set "$VLAN_IF" up
done

# Reglas NAT para acceso a Internet (suponiendo salida por ens7)
INET_IF="ens7"
iptables -t nat -A POSTROUTING -o "$INET_IF" -j MASQUERADE
echo 1 > /proc/sys/net/ipv4/ip_forward

echo "=== OFS configurado con VLANs y NAT habilitado ==="
ovs-vsctl show
