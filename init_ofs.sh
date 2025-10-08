#!/usr/bin/env bash
# ============================================================
# Script: init_ofs.sh
# Propósito: Inicializar el OpenFlow Switch (OFS)
# Uso: sudo ./init_ofs.sh <NombreOvS> <puerto1> [puerto2 puerto3 ...]
# Ejemplo: sudo ./init_ofs.sh br-data eth1 eth2 eth3
# ============================================================

set -euo pipefail

echo "=== Inicializando OpenFlow Switch (OFS) ==="

# --- Verificar que se ejecute como root ---
if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Debes ejecutar este script como root (sudo)." >&2
  exit 1
fi

# --- Verificar parámetros ---
if [[ $# -lt 2 ]]; then
  echo "Uso: $0 <NombreOvS> <puerto1> [puerto2 ...]" >&2
  echo "Ejemplo: $0 br-data eth1 eth2 eth3" >&2
  exit 1
fi

NOMBRE_OVS="$1"
shift
PUERTOS=("$@")

echo "Bridge (OvS): $NOMBRE_OVS"
echo "Puertos Data Network: ${PUERTOS[*]}"
echo ""

# --- Verificar existencia del bridge ---
echo "=== Verificando existencia del bridge ==="
if ! ovs-vsctl br-exists "$NOMBRE_OVS"; then
  echo "[ERROR] No existe el OvS '$NOMBRE_OVS'. Créalo antes con:"
  echo "        sudo ovs-vsctl add-br $NOMBRE_OVS"
  exit 1
else
  echo "El bridge $NOMBRE_OVS existe. Continuando..."
fi
echo ""

# --- Procesar interfaces ---
for PUERTO in "${PUERTOS[@]}"; do
  echo "=== Procesando puerto: $PUERTO ==="
  
  # Verificar si la interfaz existe
  if ! ip link show "$PUERTO" >/dev/null 2>&1; then
    echo "[ADVERTENCIA] La interfaz '$PUERTO' no existe en este host. Omitiendo..."
    echo ""
    continue
  fi

  # Limpiar IPs previas
  echo "Limpiando configuraciones IP de $PUERTO..."
  ip addr flush dev "$PUERTO"

  # Agregar puerto al OvS (sin error si ya existe)
  echo "Agregando $PUERTO al bridge $NOMBRE_OVS..."
  ovs-vsctl --may-exist add-port "$NOMBRE_OVS" "$PUERTO"

  echo "Puerto $PUERTO agregado exitosamente."
  echo ""
done

echo "=== OFS inicializado correctamente ==="
echo "Bridge configurado: $NOMBRE_OVS"
echo "Puertos añadidos:"
ovs-vsctl list-ports "$NOMBRE_OVS"

echo ""
echo "=== Detalles de configuración OvS ==="
ovs-vsctl show

echo ""
echo "=== Estado del bridge ==="
ovs-appctl fdb/show "$NOMBRE_OVS" || echo "(No hay tabla MAC disponible todavía)"

echo ""
echo "=== Proceso completado ==="
