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
    echo "[INFO] Agregando puerto $P al bridge $NOMBRE_OVS..."
    ip addr flush dev "$P"
    ovs-vsctl --may-exist add-port "$NOMBRE_OVS" "$P"
    ovs-vsctl set port "$P" trunk=0-4094
    ip link set "$P" up
  else
    echo "[WARN] El puerto $P no existe, se omite."
  fi
done

# Crear gateways por VLAN (para salida de cada VLAN)
for VLAN in 100 200 300; do
  VLAN_IF="vlan${VLAN}"
  if ! ip link show "$VLAN_IF" >/dev/null 2>&1; then
    ip link add link "$NOMBRE_OVS" name "$VLAN_IF" type vlan id "$VLAN"
  fi
  ip addr add "192.168.${VLAN}.1/24" dev "$VLAN_IF" 2>/dev/null || true
  ip link set "$VLAN_IF" up
done

# Configurar NAT usando ens8 (interfaz de salida a Internet)
INET_IF="ens8"
if ip link show "$INET_IF" >/dev/null 2>&1; then
  echo "[INFO] Habilitando NAT sobre $INET_IF..."
  iptables -t nat -A POSTROUTING -o "$INET_IF" -j MASQUERADE
  echo 1 > /proc/sys/net/ipv4/ip_forward
else
  echo "[WARN] No se encontró la interfaz $INET_IF. NAT no configurado."
fi

echo "=== OpenFlow Switch ($NOMBRE_OVS) configurado correctamente ==="
ovs-vsctl show

