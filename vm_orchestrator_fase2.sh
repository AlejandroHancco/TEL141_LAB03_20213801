#!/usr/bin/env bash
# ==========================================================
# Script: vm_orchestrator_fase2.sh
# Propósito:
#   - Inicializar HeadNode
#   - Crear VLANs y namespaces
#   - Configurar OFS y NAT
# ==========================================================

set -euo pipefail

USER="ubuntu"
PASS="contra213"

HEADNODE_HOST="10.0.10.4"
OFS_HOST="10.0.10.5"

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

# === Función para ejecutar comandos remotos ===
execute_remote() {
    local host="$1"
    local cmd="$2"
    sshpass -p "$PASS" ssh "${SSH_OPTS[@]}" "$USER@$host" "bash -c '$cmd'"
}

# === Inicializar HeadNode ===
echo "==> Inicializando HeadNode..."
execute_remote "$HEADNODE_HOST" "sudo ./init_headnode.sh br-int ens4"

# === Crear namespaces (una red por VLAN) ===
echo "==> Creando namespaces y configurando DHCP + Gateway..."

execute_remote "$HEADNODE_HOST" "
sudo ./ns_create.sh vlan100 br-int 100 '192.168.100.10-192.168.100.50' 192.168.100.1
sudo ./ns_create.sh vlan200 br-int 200 '192.168.200.10-192.168.200.50' 192.168.200.1
sudo ./ns_create.sh vlan300 br-int 300 '192.168.300.10-192.168.300.50' 192.168.300.1
"

# === Inicializar OFS central ===
echo "==> Inicializando OpenFlow Switch (OFS)..."
execute_remote "$OFS_HOST" "sudo ./init_ofs.sh br-ofs ens5 ens6 ens7 ens8"

# === Mostrar estado ===
echo "==> Mostrando estado de red (HeadNode y OFS)..."
execute_remote "$HEADNODE_HOST" "sudo ovs-vsctl show"
execute_remote "$OFS_HOST" "sudo ovs-vsctl show"

echo "✅ Fase 2 completada: VLANs y namespaces configurados correctamente."
