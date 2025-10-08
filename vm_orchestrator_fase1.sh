#!/usr/bin/env bash
# vm_orchestrator_fase1.sh
# Orquesta toda la Fase 1:
# - Limpia configuración previa (--clean)
# - Inicializa Workers
# - Inicializa OFS
# - Crea VMs con VLANs
# - Muestra estado (--status)
# - Ayuda (--help)

set -euo pipefail

USER="ubuntu"
PASS="ubuntu123"

# Hosts
WORKER1_HOST="10.0.10.1"
WORKER2_HOST="10.0.10.2"
WORKER3_HOST="10.0.10.3"
OFS_HOST="10.0.10.5"

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

# === Funciones auxiliares ===

execute_remote() {
    local host="$1"
    local cmd="$2"
    sshpass -p "$PASS" ssh "${SSH_OPTS[@]}" "$USER@$host" "bash -c '$cmd'"
}

show_help() {
    echo "Uso: $0 [opción]"
    echo ""
    echo "Opciones:"
    echo "  --clean       Limpia la configuración previa en todos los nodos"
    echo "  --status      Muestra el estado actual de la topología"
    echo "  --help        Muestra esta ayuda"
    echo "  (sin argumentos) Ejecuta toda la Fase 1 completa"
}

show_topology_status() {
    echo "=== Estado actual de la topología ==="
    ALL_HOSTS=($WORKER1_HOST $WORKER2_HOST $WORKER3_HOST $OFS_HOST)

    for host in "${ALL_HOSTS[@]}"; do
        echo "---- $host ----"
        execute_remote "$host" "
            echo 'Bridges existentes:'
            sudo ovs-vsctl list-br || echo '(sin bridges)'
            echo ''
            echo 'VMs activas:'
            pgrep -a qemu || echo '(sin VMs)'
            echo '-------------------------------'
        "
    done
}

clean_configuration() {
    echo "=== Limpiando configuración existente ==="
    ALL_HOSTS=($WORKER1_HOST $WORKER2_HOST $WORKER3_HOST $OFS_HOST)

    for host in "${ALL_HOSTS[@]}"; do
        echo "→ Limpiando configuración en $host..."
        execute_remote "$host" "
            sudo pkill qemu 2>/dev/null || true
            sudo ovs-vsctl del-br br-int 2>/dev/null || true
            sudo ovs-vsctl del-br br-data 2>/dev/null || true
            sudo rm -f /tmp/vms/*.pid 2>/dev/null || true
            echo '✔ Limpieza completa en $host'
        "
    done
}

main() {
    echo "==> Iniciando Fase 1 del Orquestador..."

    # 0) Limpieza previa automática
    clean_configuration

    # 1) Inicializar Workers
    echo "==> Inicializando Workers..."
    sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER1_HOST "sudo ./init_worker.sh br-int ens4"
    sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER2_HOST "sudo ./init_worker.sh br-int ens4"
    sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER3_HOST "sudo ./init_worker.sh br-int ens4"

    # 2) Inicializar OFS
    echo "==> Inicializando OFS..."
    sshpass -p "$PASS" ssh $SSH_OPTS $USER@$OFS_HOST "sudo ./init_ofs.sh br-ofs ens5 ens6 ens7 ens8"

    # 3) Crear VMs
    echo "==> Creando VMs..."
    sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER1_HOST "sudo ./vm_create.sh vm1 br-int 100 5901"
    sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER1_HOST "sudo ./vm_create.sh vm2 br-int 200 5902"
    sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER1_HOST "sudo ./vm_create.sh vm3 br-int 300 5903"

    sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER2_HOST "sudo ./vm_create.sh vm1 br-int 100 5904"
    sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER2_HOST "sudo ./vm_create.sh vm2 br-int 200 5905"
    sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER2_HOST "sudo ./vm_create.sh vm3 br-int 300 5906"

    sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER3_HOST "sudo ./vm_create.sh vm1 br-int 100 5907"
    sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER3_HOST "sudo ./vm_create.sh vm2 br-int 200 5908"
    sshpass -p "$PASS" ssh $SSH_OPTS $USER@$WORKER3_HOST "sudo ./vm_create.sh vm3 br-int 300 5909"

    echo "==>  Fase 1 del orquestador desplegada correctamente."
}

# === Procesamiento de argumentos ===
case ${1:-} in
    --help)
        show_help
        exit 0
        ;;
    --status)
        show_topology_status
        exit 0
        ;;
    --clean)
        clean_configuration
        exit 0
        ;;
    "")
        main
        ;;
    *)
        echo "Opción desconocida: $1"
        show_help
        exit 1
        ;;
esac
