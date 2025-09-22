#!/bin/bash

# Script: init_worker.sh
# Propósito: Inicializar Workers creando OvS local y conectando interfaces
# Parámetros: nombreOvS InterfacesAConectar

# Verificar parámetros
if [ $# -lt 2 ]; then
    echo "Uso: $0 <nombreOvS> <interfaz1> [interfaz2] [interfaz3] ..."
    echo "Ejemplo: $0 br-int eth1 eth2"
    exit 1
fi

NOMBRE_OVS=$1
shift
INTERFACES=("$@")

echo "=== Inicializando Worker ==="
echo "OvS: $NOMBRE_OVS"
echo "Interfaces: ${INTERFACES[*]}"

# Función para verificar si OvS existe
ovs_exists() {
    ovs-vsctl br-exists $1 2>/dev/null
}

# Crear OvS local si no existe
if ovs_exists $NOMBRE_OVS; then
    echo "El bridge $NOMBRE_OVS ya existe"
else
    echo "Creando bridge $NOMBRE_OVS..."
    sudo ovs-vsctl add-br $NOMBRE_OVS
    if [ $? -eq 0 ]; then
        echo "Bridge $NOMBRE_OVS creado exitosamente"
    else
        echo "Error al crear el bridge $NOMBRE_OVS"
        exit 1
    fi
fi

# Conectar interfaces al OvS
for interface in "${INTERFACES[@]}"; do
    echo "Verificando interfaz $interface..."
    
    # Verificar si la interfaz existe
    if ! ip link show $interface >/dev/null 2>&1; then
        echo "Advertencia: La interfaz $interface no existe"
        continue
    fi
    
    # Verificar si la interfaz ya está conectada al bridge
    if sudo ovs-vsctl port-to-br $interface 2>/dev/null | grep -q $NOMBRE_OVS; then
        echo "La interfaz $interface ya está conectada al bridge $NOMBRE_OVS"
    else
        echo "Conectando interfaz $interface al bridge $NOMBRE_OVS..."
        
        # Limpiar configuración IP de la interfaz antes de agregarla
        sudo ip addr flush dev $interface
        
        # Agregar interfaz al bridge
        sudo ovs-vsctl add-port $NOMBRE_OVS $interface
        if [ $? -eq 0 ]; then
            echo "Interfaz $interface agregada exitosamente al bridge $NOMBRE_OVS"
            
            # Configurar como trunk port por defecto
            sudo ovs-vsctl set port $interface trunk=0-4094
        else
            echo "Error al agregar la interfaz $interface al bridge $NOMBRE_OVS"
        fi
    fi
done

# Levantar el bridge
sudo ip link set $NOMBRE_OVS up

echo "=== Worker inicializado correctamente ==="
echo "Puertos del bridge $NOMBRE_OVS:"
sudo ovs-vsctl list-ports $NOMBRE_OVS
