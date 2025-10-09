#!/usr/bin/env bash
# ==========================================================
# Script: init_ofs.sh
# Propósito: Inicializar OpenFlow Switch (OFS)
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

# --- Crear OvS si no existe ---
if ovs-vsctl br-exists "$NOMBRE_OVS"; then
    echo "[INFO] El bridge $NOMBRE_OVS ya existe."
else
    ovs-vsctl add-br "$NOMBRE_OVS"
    echo "[INFO] Bridge $NOMBRE_OVS creado."
fi

# --- Subir bridge ---
ip link set "$NOMBRE_OVS" up

# --- Agregar puertos físicos ---
for P in "${PUERTOS[@]}"; do
    if ip link show "$P" >/dev/null 2>&1; then
        ip addr flush dev "$P"
        ovs-vsctl --may-exist add-port "$NOMBRE_OVS" "$P"
        ip link set "$P" up
        echo "[INFO] Puerto $P agregado y levantado."
    else
        echo "[WARN] El puerto $P no existe, se omite."
    fi
done

# --- Crear interfaces de gateway para VLANs ---
for VLAN in 100 200 300; do
    VLAN_IF="vlan${VLAN}"
    if ! ip link show "$VLAN_IF" >/dev/null 2>&1; then
        ip link add link "$NOMBRE_OVS" name "$VLAN_IF" type vlan id "$VLAN"
    fi
    ip addr add "192.168.${VLAN}.1/24" dev "$VLAN_IF" 2>/dev/null || true
    ip link set "$VLAN_IF" up
done

# --- NAT hacia Internet (ens8) ---
INET_IF="ens8"
if ip link show "$INET_IF" >/dev/null 2>&1; then
    iptables -t nat -C POSTROUTING -o "$INET_IF" -j MASQUERADE 2>/dev/null || \
        iptables -t nat -A POSTROUTING -o "$INET_IF" -j MASQUERADE
    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo "[INFO] NAT configurado sobre $INET_IF."
else
    echo "[WARN] Interfaz $INET_IF no encontrada, NAT no configurado."
fi

echo "=== OpenFlow Switch ($NOMBRE_OVS) configurado correctamente ==="
ovs-vsctl show
