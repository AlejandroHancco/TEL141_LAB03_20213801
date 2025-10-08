#!/usr/bin/env bash
# Script: init_worker.sh
# Propósito: Inicializar Workers creando un bridge Open vSwitch (OvS) y conectando interfaces.
# Uso: sudo ./init_worker.sh <nombreOvS> <iface1> [iface2 iface3 ...]

set -euo pipefail

# === Comprobaciones iniciales ===
if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Debes ejecutar este script como root (usa sudo)." >&2
  exit 1
fi

if ! command -v ovs-vsctl >/dev/null 2>&1; then
  echo "[ERROR] El paquete 'openvswitch-switch' no está instalado." >&2
  echo "        Instálalo con: sudo apt update && sudo apt install -y openvswitch-switch"
  exit 1
fi

if [[ $# -lt 2 ]]; then
  echo "Uso: $0 <nombreOvS> <iface1> [iface2 iface3 ...]" >&2
  echo "Ejemplo: $0 br-int eth1 eth2"
  exit 1
fi

# === Variables ===
OVS_BR="$1"
shift
IFACES=("$@")

echo "=== Inicializando Worker ==="
echo "Bridge OVS  : $OVS_BR"
echo "Interfaces   : ${IFACES[*]}"
echo

# === Crear bridge si no existe ===
if ovs-vsctl br-exists "$OVS_BR" 2>/dev/null; then
  echo "[INFO] El bridge $OVS_BR ya existe."
else
  echo "[INFO] Creando bridge $OVS_BR..."
  ovs-vsctl add-br "$OVS_BR"
  echo "[OK] Bridge $OVS_BR creado exitosamente."
fi

# Levantar el bridge
ip link set dev "$OVS_BR" up || true
echo "[OK] Bridge $OVS_BR levantado."

# === Conectar interfaces ===
for IFACE in "${IFACES[@]}"; do
  echo
  echo ">> Procesando interfaz: $IFACE"

  if ! ip link show "$IFACE" >/dev/null 2>&1; then
    echo "  [WARN] La interfaz $IFACE no existe. Omitiendo..."
    continue
  fi

  # Verificar si la interfaz ya pertenece al bridge
  CURRENT_BR=$(ovs-vsctl port-to-br "$IFACE" 2>/dev/null || true)
  if [[ "$CURRENT_BR" == "$OVS_BR" ]]; then
    echo "  [INFO] La interfaz $IFACE ya está conectada a $OVS_BR."
    continue
  elif [[ -n "$CURRENT_BR" ]]; then
    echo "  [WARN] La interfaz $IFACE pertenece actualmente a $CURRENT_BR. Omitiendo..."
    continue
  fi

  # Limpiar IPs de la interfaz
  echo "  [INFO] Limpiando configuración IP de $IFACE..."
  ip addr flush dev "$IFACE" || true

  # Agregar interfaz al bridge
  echo "  [INFO] Agregando $IFACE al bridge $OVS_BR..."
  ovs-vsctl add-port "$OVS_BR" "$IFACE"
  echo "  [OK] Interfaz $IFACE agregada."

  # Configurar como trunk
  echo "  [INFO] Configurando $IFACE como trunk (0–4094)..."
  ovs-vsctl set port "$IFACE" trunk=0-4094 || true

  # Levantar la interfaz
  ip link set dev "$IFACE" up || true
  echo "  [OK] Interfaz $IFACE levantada."
done

# === Mostrar resumen ===
echo
echo "=== Worker inicializado correctamente ==="
echo "Puertos en $OVS_BR:"
ovs-vsctl list-ports "$OVS_BR"
