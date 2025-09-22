#!/bin/bash

# Script: vm_orchestrator_fase1.sh
# Propósito: Orquestador principal que implementa la Fase 1 de la topología
# Este script coordina la inicialización de Workers, OFS y creación de VMs

echo "=========================================="
echo "    VM ORCHESTRATOR - FASE 1"
echo "    TEL141 - Ingeniería de Redes Cloud"
echo "=========================================="

# Configuraciones de la topología - TUS IPs ESPECÍFICAS
HEADNODE_IP="10.0.10.4"    # Server 1 - HeadNode
WORKER1_IP="10.0.10.1"     # Server 2 - Worker1  
WORKER2_IP="10.0.10.2"     # Server 3 - Worker2
WORKER3_IP="10.0.10.3"     # Server 4 - Worker3
OFS_IP="10.0.10.5"         # OFS - OpenFlow Switch

# Configuración de bridges
OVS_WORKER="br-int"
OVS_OFS="br-data"

# Configuración de interfaces (ajustar según topología)
# Estas son las interfaces de Data Network
DATA_INTERFACES=("eth1" "eth2" "eth3" "eth4")

# Configuración de VMs de ejemplo
declare -A VM_CONFIG
VM_CONFIG["vm1"]="worker1 100 5901"  # worker vlan vnc_port
VM_CONFIG["vm2"]="worker2 100 5902"
VM_CONFIG["vm3"]="worker1 200 5903"
VM_CONFIG["vm4"]="worker3 200 5904"

# Función para ejecutar comandos remotos
execute_remote() {
    local host=$1
    local command=$2
    echo "Ejecutando en $host: $command"
    ssh -o StrictHostKeyChecking=no root@$host "$command"
}

# Función para copiar archivos a hosts remotos
copy_to_remote() {
    local host=$1
    local local_file=$2
    local remote_path=$3
    echo "Copiando $local_file a $host:$remote_path"
    scp -o StrictHostKeyChecking=no "$local_file" root@$host:"$remote_path"
}

# Función para verificar conectividad
check_connectivity() {
    local hosts=("$@")
    echo "=== Verificando conectividad ==="
    
    for host in "${hosts[@]}"; do
        if ping -c 1 -W 3 $host >/dev/null 2>&1; then
            echo "✓ $host accesible"
        else
            echo "✗ $host NO accesible"
            return 1
        fi
    done
    return 0
}

# Función para distribuir scripts
distribute_scripts() {
    local hosts=("$@")
    echo "=== Distribuyendo scripts a todos los hosts ==="
    
    for host in "${hosts[@]}"; do
        echo "Distribuyendo scripts a $host..."
        copy_to_remote $host "init_worker.sh" "/tmp/"
        copy_to_remote $host "vm_create.sh" "/tmp/"
        copy_to_remote $host "init_ofs.sh" "/tmp/"
        
        # Hacer scripts ejecutables
        execute_remote $host "chmod +x /tmp/*.sh"
    done
}

# Función para inicializar Workers
initialize_workers() {
    echo "=== Inicializando Workers ==="
    
    # Worker 1
    echo "Inicializando Worker 1..."
    execute_remote $WORKER1_IP "/tmp/init_worker.sh $OVS_WORKER eth1"
    
    # Worker 2
    echo "Inicializando Worker 2..."
    execute_remote $WORKER2_IP "/tmp/init_worker.sh $OVS_WORKER eth1"
    
    # Worker 3
    echo "Inicializando Worker 3..."
    execute_remote $WORKER3_IP "/tmp/init_worker.sh $OVS_WORKER eth1"
}

# Función para inicializar OFS
initialize_ofs() {
    echo "=== Inicializando OpenFlow Switch (OFS) ==="
    execute_remote $OFS_IP "/tmp/init_ofs.sh $OVS_OFS ${DATA_INTERFACES[*]}"
}

# Función para crear VMs
create_virtual_machines() {
    echo "=== Creando Máquinas Virtuales ==="
    
    for vm_name in "${!VM_CONFIG[@]}"; do
        IFS=' ' read -r worker vlan vnc_port <<< "${VM_CONFIG[$vm_name]}"
        
        case $worker in
            "worker1")
                worker_ip=$WORKER1_IP
                ;;
            "worker2")
                worker_ip=$WORKER2_IP
                ;;
            "worker3")
                worker_ip=$WORKER3_IP
                ;;
            *)
                echo "Worker desconocido: $worker"
                continue
                ;;
        esac
        
        echo "Creando VM $vm_name en $worker (IP: $worker_ip) con VLAN $vlan..."
        execute_remote $worker_ip "/tmp/vm_create.sh $vm_name $OVS_WORKER $vlan $vnc_port"
    done
}

# Función para mostrar estado de la topología
show_topology_status() {
    echo "=========================================="
    echo "    ESTADO DE LA TOPOLOGÍA"
    echo "=========================================="
    
    echo "=== Workers ==="
    for worker_ip in $WORKER1_IP $WORKER2_IP $WORKER3_IP; do
        echo "Worker: $worker_ip"
        execute_remote $worker_ip "ovs-vsctl show" | head -10
        echo ""
    done
    
    echo "=== OpenFlow Switch ==="
    execute_remote $OFS_IP "ovs-vsctl show"
    
    echo "=== VMs Creadas ==="
    for vm_name in "${!VM_CONFIG[@]}"; do
        IFS=' ' read -r worker vlan vnc_port <<< "${VM_CONFIG[$vm_name]}"
        echo "VM: $vm_name | Worker: $worker | VLAN: $vlan | VNC: $vnc_port"
    done
}

# Script principal
main() {
    echo "Iniciando orquestación de la topología Fase 1..."
    
    # Lista de todos los hosts
    ALL_HOSTS=($HEADNODE_IP $WORKER1_IP $WORKER2_IP $WORKER3_IP $OFS_IP)
    
    # Paso 1: Verificar conectividad
    if ! check_connectivity "${ALL_HOSTS[@]}"; then
        echo "Error: No todos los hosts están accesibles"
        exit 1
    fi
    
    # Paso 2: Distribuir scripts
    distribute_scripts "${ALL_HOSTS[@]}"
    
    # Paso 3: Inicializar OFS (debe ir primero)
    initialize_ofs
    
    # Paso 4: Inicializar Workers
    initialize_workers
    
    # Dar tiempo para que se establezcan las conexiones
    echo "Esperando 10 segundos para establecer conectividad..."
    sleep 10
    
    # Paso 5: Crear VMs
    create_virtual_machines
    
    # Paso 6: Mostrar estado final
    show_topology_status
    
    echo "=========================================="
    echo "   ORQUESTACIÓN FASE 1 COMPLETADA"
    echo "=========================================="
    
    echo ""
    echo "Para conectarse a las VMs usando VNC:"
    for vm_name in "${!VM_CONFIG[@]}"; do
        IFS=' ' read -r worker vlan vnc_port <<< "${VM_CONFIG[$vm_name]}"
        case $worker in
            "worker1") worker_ip=$WORKER1_IP ;;
            "worker2") worker_ip=$WORKER2_IP ;;
            "worker3") worker_ip=$WORKER3_IP ;;
        esac
        echo "  VM $vm_name: vncviewer $worker_ip:$vnc_port"
    done
    
    echo ""
    echo "Para verificar el estado de los bridges:"
    echo "  ovs-vsctl show"
    echo "  ovs-vsctl list-ports <bridge_name>"
}

# Función de ayuda
show_help() {
    echo "VM Orchestrator Fase 1 - TEL141"
    echo ""
    echo "Este script configura automáticamente:"
    echo "  - Workers con Open vSwitch local"
    echo "  - OpenFlow Switch central"
    echo "  - VMs con configuración VLAN"
    echo ""
    echo "Uso: $0 [opción]"
    echo "Opciones:"
    echo "  --help    Mostrar esta ayuda"
    echo "  --status  Mostrar solo el estado actual"
    echo "  --clean   Limpiar configuración existente"
}

# Función para limpiar configuración
clean_configuration() {
    echo "=== Limpiando configuración existente ==="
    
    ALL_HOSTS=($HEADNODE_IP $WORKER1_IP $WORKER2_IP $WORKER3_IP $OFS_IP)
    
    for host in "${ALL_HOSTS[@]}"; do
        echo "Limpiando configuración en $host..."
        execute_remote $host "pkill qemu 2>/dev/null || true"
        execute_remote $host "ovs-vsctl del-br br-int 2>/dev/null || true"
        execute_remote $host "ovs-vsctl del-br br-data 2>/dev/null || true"
        execute_remote $host "rm -f /tmp/vms/*.pid"
    done
}

# Procesar argumentos
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
