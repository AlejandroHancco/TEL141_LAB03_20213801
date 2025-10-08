#!/usr/bin/env bash
# ==========================================================
# Script: init_headnode.sh
# Propósito: Inicializar el HeadNode creando el OvS local
# Uso: sudo ./init_headnode.sh <NombreOvS> <interfaz1> [interfaz2 ...]
# Ejemplo: sudo ./init_headnode.sh br-int ens4
# ==========================================================

set -euo pipefail

echo "=== Inicializando HeadNode ==="

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Debes ejecutar este script como root (sudo)." >&2
  exit 1
fi

if [[ $# -lt 2 ]]; then
  echo "Uso: $0 <NombreOvS> <interfaz1> [interfaz2 ...]" >&2
  exit 1
fi

NOMBRE_OVS="$1"
shift
INTERFACES=("$@")

# Comprobar dependencia
if ! command -v ovs-vsctl >/dev/null 2>&1; then
  echo "[ERROR] Open vSwitch no está instalado." >&2
  exit 1
fi

# Crear OvS si no existe
if ovs-vsctl br-exists "$NOMBRE_OVS"; then
  echo "[INFO] El bridge $NOMBRE_OVS ya existe."
else
  echo "[INFO] Creando bridge $NOMBRE_OVS..."
  ovs-vsctl add-br "$NOMBRE_OVS"
  echo "[OK] Bridge $NOMBRE_OVS creado."
fi

# Agregar interfaces
for IFACE in "${INTERFACES[@]}"; do
  echo "-> Procesando $IFACE"
  if ! ip link show "$IFACE" >/dev/null 2>&1; then
    echo "[WARN] Interfaz $IFACE no existe. Omitiendo..."
    continue
  fi

  ip addr flush dev "$IFACE"
  ovs-vsctl --may-exist add-port "$NOMBRE_OVS" "$IFACE"
  ovs-vsctl set port "$IFACE" trunk=0-4094
  ip link set dev "$IFACE" up
done

ip link set dev "$NOMBRE_OVS" up
ovs-vsctl set bridge "$NOMBRE_OVS" fail-mode=standalone
ovs-vsctl set bridge "$NOMBRE_OVS" stp_enable=true

echo "=== HeadNode inicializado correctamente ==="
ovs-vsctl list-ports "$NOMBRE_OVS"
