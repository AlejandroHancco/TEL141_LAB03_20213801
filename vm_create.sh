#!/usr/bin/env bash
# ==========================================================
# Script: vm_create.sh
# Propósito: Crear una VM ligera (QEMU + Cirros) y conectarla
#             a un bridge Open vSwitch con una VLAN específica.
# Uso: sudo ./vm_create.sh <NombreVM> <NombreOvS> <VLAN_ID> <PuertoVNC>
# Ejemplo:
#   sudo ./vm_create.sh vm1 br-int 100 5901
# ==========================================================

set -euo pipefail

# === Colores para salida ===
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[36m"
RESET="\e[0m"

# === Función de log ===
log()    { echo -e "${BLUE}[INFO]${RESET} $*"; }
warn()   { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error()  { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

# === Validaciones iniciales ===
if [[ $EUID -ne 0 ]]; then
  error "Debes ejecutar este script como root (usa sudo)."
  exit 1
fi

if [[ $# -ne 4 ]]; then
  error "Uso incorrecto."
  echo -e "Formato: ${YELLOW}$0 <NombreVM> <NombreOvS> <VLAN_ID> <PuertoVNC>${RESET}"
  echo -e "Ejemplo: ${YELLOW}$0 vm1 br-int 100 5901${RESET}"
  exit 1
fi

# === Variables ===
VM_NAME="$1"
OVS_BR="$2"
VLAN_ID="$3"
VNC_PORT="$4"
IMG="cirros-0.5.1-x86_64-disk.img"
TAP_IF="tap-${VM_NAME}"

log "Inicializando creación de VM:"
echo "  VM_NAME : $VM_NAME"
echo "  OVS_BR  : $OVS_BR"
echo "  VLAN_ID : $VLAN_ID"
echo "  VNC_PORT: $VNC_PORT"
echo

# === Comprobaciones de entorno ===
if [[ ! -f "$IMG" ]]; then
  error "No se encuentra la imagen ${IMG} en el directorio actual."
  exit 1
fi

if ! command -v ovs-vsctl >/dev/null 2>&1; then
  error "Open vSwitch no está instalado (falta ovs-vsctl)."
  echo "        Instálalo con: sudo apt update && sudo apt install -y openvswitch-switch"
  exit 1
fi

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  error "QEMU no está instalado (falta qemu-system-x86_64)."
  echo "        Instálalo con: sudo apt install -y qemu-kvm"
  exit 1
fi

# === Validaciones de parámetros ===
if ! ovs-vsctl br-exists "$OVS_BR"; then
  error "No existe el bridge de OvS '$OVS_BR'."
  exit 1
fi

if ! [[ "$VLAN_ID" =~ ^[0-9]+$ ]] || (( VLAN_ID < 1 || VLAN_ID > 4094 )); then
  error "VLAN_ID inválido: $VLAN_ID (debe estar entre 1 y 4094)."
  exit 1
fi

if [[ "$VNC_PORT" -le 5900 ]]; then
  error "El puerto VNC debe ser mayor a 5900 (ejemplo: 5901, 5902...)."
  exit 1
fi

if ip link show "$TAP_IF" >/dev/null 2>&1; then
  error "La interfaz TAP '$TAP_IF' ya existe."
  echo "        Elimínala o usa otro NombreVM. Comandos sugeridos:"
  echo "          sudo ip link set $TAP_IF down"
  echo "          sudo ip link del  $TAP_IF"
  exit 1
fi

# === Generar dirección MAC aleatoria ===
RAND_HEX=$(hexdump -n3 -v -e '/1 "%02x"' /dev/urandom)
MAC_ADDR="52:54:00:${RAND_HEX:0:2}:${RAND_HEX:2:2}:${RAND_HEX:4:2}"

log "MAC generada: ${MAC_ADDR}"

# === Crear interfaz TAP ===
log "Creando interfaz TAP ${TAP_IF} ..."
ip tuntap add mode tap name "$TAP_IF"
ip link set "$TAP_IF" up

# === Conectar TAP al OVS con VLAN ===
log "Conectando ${TAP_IF} a ${OVS_BR} con VLAN ${VLAN_ID} ..."
ovs-vsctl --may-exist add-port "$OVS_BR" "$TAP_IF" tag="$VLAN_ID"

# === Lanzar la VM ===
log "Lanzando VM ${VM_NAME} (VNC :$((VNC_PORT-5900))) ..."
qemu-system-x86_64 \
  -enable-kvm \
  -vnc 0.0.0.0:$((VNC_PORT-5900)) \
  -netdev tap,id="$TAP_IF",ifname="$TAP_IF",script=no,downscript=no \
  -device e1000,netdev="$TAP_IF",mac="$MAC_ADDR" \
  -daemonize \
  -snapshot \
  "$IMG"

log "VM ${VM_NAME} creada exitosamente."
echo -e "${GREEN}VNC disponible en :$((VNC_PORT-5900)) (puerto TCP $VNC_PORT)${RESET}"
echo
echo "Para visualizar:"
echo "  vncviewer localhost:$((VNC_PORT-5900))"
echo "Para listar las VMs en ejecución:"
echo "  ps aux | grep qemu"
