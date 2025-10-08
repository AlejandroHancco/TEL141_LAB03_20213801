#!/usr/bin/env bash
# ==========================================================
# Script: vm_orchestrator_fase1.sh
# Propósito:
#   - Limpia configuración previa (--clean)
#   - Inicializa Workers
#   - Inicializa OFS
#   - Crea VMs con VLANs
#   - Muestra estado (--status)
# ==========================================================

set -euo pipefail

USER="ubuntu"
PASS="ubuntu123"

# Hosts
WORKER1_HOST="10.0.10.1"
WORKER2_HOST="10.0.10.2"
WORKER3_HOST="10.0.10.3"
OFS_HOST="10.0.10.5"

# Opciones SSH
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

# === Funciones auxiliares ===

execute_remote() {
    local host="$1"
    local cmd="$2"
    sshpass -p "$PASS" ssh "${SSH_OPTS[@]}" "$USER@$host" "bash -c '$cmd'"
}

execute_remote_sudo() {
    local host="$1"
    local cmd="$2"
    sshpass -p "$PASS" ssh "${SSH_OPTS[@]}" "$USER@$host" "echo $PASS | sudo -S bash -c '$cmd'"
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
        execute_remote_sudo "$host" "
            echo 'Bridges existentes:'
            ovs-vsctl list-br || echo '(sin bridges)'
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
        execute_remote_sudo "$host" "
            pkill qemu 2>/dev/null || true
            ovs-vsctl --if-exists del-br br-int 2>/dev/null || true
            ovs-vsctl --if-exists del-br br-data 2>/dev/null || true
            ovs-vsctl --if-exists del-br br-ofs 2>/dev/null || true
            rm -f /tmp/vms/*.pid 2>/dev/null || true
            echo '✔ Limpieza completa en $host'
        "
    done
}

distribute_scripts() {
    echo "=== Distribuyendo scripts a nodos ==="
    NODES=($WORKER1_HOST $WORKER2_HOST $WORKER3_HOST $OFS_HOST)
    SCRIPTS=("init_worker.sh" "vm_create.sh" "init_ofs.sh")

    for node in "${NODES[@]}"; do
        for script in "${SCRIPTS[@]}"; do
            # Solo copiar scripts relevantes a cada nodo
            case "$script" in
                init_ofs.sh)
                    [ "$node" = "$OFS_HOST" ] && {
                        sshpass -p "$PASS" scp "${SSH_OPTS[@]}" "$script" "$USER@$node:/home/$USER/"
                        execute_remote_sudo "$node" "chmod +x /home/$USER/$script"
                    }
                    ;;
                init_worker.sh|vm_create.sh)
                    if [[ "$node" != "$OFS_HOST" ]]; then
                        sshpass -p "$PASS" scp "${SSH_OPTS[@]}" "$script" "$USER@$node:/home/$USER/"
                        execute_remote_sudo "$node" "chmod +x /home/$USER/$script"
                    fi
                    ;;
            esac
        done
    done
}

initialize_workers() {
    echo "==> Inicializando Workers..."
    for host in $WORKER1_HOST $WORKER2_HOST $WORKER3_HOST; do
        echo "=== Inicializando Worker en $host ==="
        execute_remote_sudo "$host" "/home/$USER/init_worker.sh br-int ens4"
        echo "Puertos en br-int:"
        execute_remote_sudo "$host" "ovs-vsctl list-ports br-int"
    done
}

initialize_ofs() {
    echo "==> Inicializando OFS..."
    execute_remote_sudo "$OFS_HOST" "/home/$USER/init_ofs.sh br-ofs ens5 ens6 ens7 ens8"
}

create_vms() {
    echo "==> Creando VMs..."
    for host in $WORKER1_HOST $WORKER2_HOST $WORKER3_HOST; do
        for i in 1 2 3; do
            port=$((5900 + i + (host##*.) * 0)) # Ajusta puerto si lo deseas
            vlan=$((i * 100))
            execute_remote_sudo "$host" "/home/$USER/vm_create.sh vm$i br-int $vlan $port"
        done
    done
}

main() {
    echo "==> Iniciando Fase 1 del Orquestador..."
    clean_configuration
    distribute_scripts
    initialize_workers
    initialize_ofs
    create_vms
    echo "==> Fase 1 del orquestador desplegada correctamente."
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
