#!/usr/bin/env bash
# vm_orchestrator_fase1.sh
# Fase 1 del orquestador:
# - Limpia configuración previa en cada nodo
# - Inicializa Workers
# - Inicializa OFS
# - Crea VMs con sus VLANs

set -euo pipefail

USER="ubuntu"
PASS="ubuntu123"
WORKDIR="/home/ubuntu/TEL141_LAB03_20213801"

# Host:IP
WORKER1_HOST="10.0.10.1"
WORKER2_HOST="10.0.10.2"
WORKER3_HOST="10.0.10.3"
OFS_HOST="10.0.10.5"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# ==========================
# 0) LIMPIEZA PREVIA
# ==========================
echo "==> Limpiando configuración previa en todos los nodos..."

for HOST in $WORKER1_HOST $WORKER2_HOST $WORKER3_HOST $OFS_HOST; do
  echo ">> Limpiando en $HOST..."
  sshpass -p "$PASS" ssh $SSH_OPTS $USER@$HOST "echo $PASS | sudo -S bash -c '
    echo \"[INFO] Eliminando bridges antiguos...\";
    sudo ovs-vsctl --if-exists del-br br-int;
    sudo ovs-vsctl --if-exists del-br br-ofs;

    echo \"[INFO] Eliminando interfaces TAP...\";
    for tap in \$(ip link show | grep -oE \"tap-[^:]+\" || true); do
      sudo ip link set \$tap down;
      sudo ip link del \$tap;
    done

    echo \"[OK] Nodo limpio.\";
  '"
done

echo "==> Limpieza completada correctamente."

# ==========================
# 1) Inicializar Workers
# ==========================
echo "==> Inicializando Workers..."
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER1_HOST "echo $PASS | sudo -S ./init_worker.sh br-int ens4"
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER2_HOST "echo $PASS | sudo -S ./init_worker.sh br-int ens4"
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER3_HOST "echo $PASS | sudo -S ./init_worker.sh br-int ens4"

# ==========================
# 2) Inicializar OFS
# ==========================
echo "==> Inicializando OFS..."
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$OFS_HOST "echo $PASS | sudo -S ./init_ofs.sh br-ofs ens5 ens6 ens7 ens8"

# ==========================
# 3) Crear VMs
# ==========================
echo "==> Creando VMs..."

# Worker 1
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER1_HOST "echo $PASS | sudo -S ./vm_create.sh vm1 br-int 100 5901"
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER1_HOST "echo $PASS | sudo -S ./vm_create.sh vm2 br-int 200 5902"
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER1_HOST "echo $PASS | sudo -S ./vm_create.sh vm3 br-int 300 5903"

# Worker 2
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER2_HOST "echo $PASS | sudo -S ./vm_create.sh vm1 br-int 100 5904"
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER2_HOST "echo $PASS | sudo -S ./vm_create.sh vm2 br-int 200 5905"
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER2_HOST "echo $PASS | sudo -S ./vm_create.sh vm3 br-int 300 5906"

# Worker 3
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER3_HOST "echo $PASS | sudo -S ./vm_create.sh vm1 br-int 100 5907"
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER3_HOST "echo $PASS | sudo -S ./vm_create.sh vm2 br-int 200 5908"
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER3_HOST "echo $PASS | sudo -S ./vm_create.sh vm3 br-int 300 5909"

# ==========================
# 4) Verificación final
# ==========================
echo "==> Verificando bridges activos en cada worker..."
for HOST in $WORKER1_HOST $WORKER2_HOST $WORKER3_HOST; do
  echo "--- Puertos en $HOST ---"
  sshpass -p "$PASS" ssh $SSH_OPTS $USER@$HOST "sudo ovs-vsctl list-ports br-int || echo 'br-int no existe'"
done

echo "✅ ==> Fase 1 del orquestador completada exitosamente."


