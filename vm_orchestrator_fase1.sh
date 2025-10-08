#!/usr/bin/env bash
# ==========================================================
# Script: vm_orchestrator_fase1.sh
# Propósito:
#   - Limpia configuración previa (--clean)
#   - Distribuye scripts a nodos
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

# Scripts locales a distribuir
SCRIPTS_LOCAL=("init_worker.sh" "init_ofs.sh" "vm_create.sh")

# === Funciones auxiliares ===

execute_remote() {
    local host="$1"
    local cmd="$2"
    sshpass -p "$PASS" ssh "${SSH_OPTS[@]}" "$USER@$host" "bash -c '$cmd'"
}

distribute_scripts() {
    echo "=== Distribuyendo scripts a nodos ==="
    declare -A NODE_SCRIPTS=(
        [$WORKER1_HOST]="init_worker.sh vm_create.sh"
        [$WORKER2_HOST]="init_worker.sh vm_create.sh"
        [$WORKER3_HOST]="init_worker.sh vm_create.sh"
        [$OFS_HOST]="init_ofs.sh"
    )

    for host in "${!NODE_SCRIPTS[@]}"; do
        for script in ${NODE_SCRIPTS[$host]}; do
            echo "→ Copiando $script a $host:/home/$USER/"
            sshpass -p "$PASS" scp "${SSH_OPTS[@]}" "$script" "$USER@$host:/home/$USER/"
            echo "→ Ajustando permisos de $script en $host"
            execute_remote "$host" "chmod +x /home/$USER/$script"
        done
    done
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

    # 0.5) Distribuir scripts
    distribute_scripts

    # 1) Inicializar Workers
    echo "==> Inicializando Workers..."
    for host in $WORKER1_HOST $WORKER2_HOST $WORKER3_HOST; do
        execute_remote "$host" "sudo /home/$USER/init_worker.sh br-int ens4"
    done

    # 2) Inicializar OFS
    echo "==> Inicializando OFS..."
    execute_remote "$OFS_HOST" "sudo /home/$USER/init_ofs.sh br-ofs ens5 ens6 ens7 ens8"

    # 3) Crear VMs
    echo "==> Creando VMs..."
    declare -A VM_PORTS=(
        [$WORKER1_HOST]="5901 5902 5903"
        [$WORKER2_HOST]="5904 5905 5906"
        [$WORKER3_HOST]="5907 5908 5909"
    )

    for host in "${!VM_PORTS[@]}"; do
        port_list=(${VM_PORTS[$host]})
        for i in {1..3}; do
            execute_remote "$host" "sudo /home/$USER/vm_create.sh vm$i br-int $((i*100)) ${port_list[i-1]}"
        done
    done

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
