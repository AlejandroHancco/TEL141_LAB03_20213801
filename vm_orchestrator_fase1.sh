#!/usr/bin/env bash
# vm_orchestrator_fase1.sh
# Orquesta toda la Fase 1:
# - Inicializa Workers
# - Inicializa OFS
# - Crea VMs con sus VLANs

set -euo pipefail

USER="ubuntu"
PASS="ubuntu123"

WORKDIR="/home/ubuntu/TEL141_LAB03_20213801"

# Host:IP:Puerto
WORKER1_HOST="10.0.10.1"
WORKER2_HOST="10.0.10.2"
WORKER3_HOST="10.0.10.3"
OFS_HOST="10.0.10.5"

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

# 1) Inicializar Workers
echo "==> Inicializando Workers..."
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER1_HOST "echo $PASS | sudo -S ./init_worker.sh br-int ens4"
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER2_HOST "echo $PASS | sudo -S ./init_worker.sh br-int ens4"
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER3_HOST "echo $PASS | sudo -S ./init_worker.sh br-int ens4"

# 2) Inicializar OFS
echo "==> Inicializando OFS..."
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$OFS_HOST "echo $PASS | sudo -S ./init_ofs.sh br-ofs ens5 ens6 ens7 ens8"

# 3) Crear VMs
echo "==> Creando VMs..."
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER1_HOST "echo $PASS | sudo -S ./vm_create.sh vm1 br-int 100 5901"
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER1_HOST "echo $PASS | sudo -S ./vm_create.sh vm2 br-int 200 5902"
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER1_HOST "echo $PASS | sudo -S ./vm_create.sh vm3 br-int 300 5903"
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER2_HOST "echo $PASS | sudo -S ./vm_create.sh vm1 br-int 100 5904"
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER2_HOST "echo $PASS | sudo -S ./vm_create.sh vm2 br-int 200 5905"
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER2_HOST "echo $PASS | sudo -S ./vm_create.sh vm3 br-int 300 5906"
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER3_HOST "echo $PASS | sudo -S ./vm_create.sh vm1 br-int 100 5907"
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER3_HOST "echo $PASS | sudo -S ./vm_create.sh vm2 br-int 200 5908"
sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER3_HOST "echo $PASS | sudo -S ./vm_create.sh vm3 br-int 300 5909"

echo "==> Fase 1 del orquestador desplegada correctamente."

