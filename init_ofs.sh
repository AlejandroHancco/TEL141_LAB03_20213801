#!/bin/bash

# Script: init_ofs.sh
# Propósito: Inicializar el OpenFlow Switch (OFS)
# Parámetros: NombreOvS Puerto1 Puerto2 ... PuertoN

# Verificar parámetros
if [ $# -lt 2 ]; then
    echo "Uso: $0 <NombreOvS> <puerto1> [puerto2] [puerto3] ..."
    echo "Ejemplo: $0 br-data eth1 eth2 eth3 eth4"
    exit 1
fi

NOMBRE_OVS=$1
shift
PUERTOS=("$@")

echo "=== Inicializando OpenFlow Switch (OFS) ==="
echo "OvS: $NOMBRE_OVS"
echo "Puertos Data Network: ${PUERTOS[*]}"

# Función para verificar si OvS existe
ovs_exists() {
    ovs-vsctl br-exists $1 2>/dev/null
}

# Crear OvS si no existe
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

# Procesar cada puerto de la Data Network
for puerto in "${PUERTOS[@]}"; do
    echo "=== Procesando puerto: $puerto ==="
    
    # Verificar si la interfaz existe
    if ! ip link show $puerto >/dev/null 2>&1; then
        echo "Advertencia: La interfaz $puerto no existe, omitiendo..."
        continue
    fi
    
    # Limpiar configuraciones IP en las interfaces de Data Network
    echo "Limpiando configuraciones IP de $puerto..."
    sudo ip addr flush dev $puerto
    
    # Verificar si el puerto ya está en el bridge
    current_bridge=$(sudo ovs-vsctl port-to-br $puerto 2>/dev/null)
    if [ $? -eq 0 ]; then
        if [ "$current_bridge" = "$NOMBRE_OVS" ]; then
            echo "El puerto $puerto ya está en el bridge $NOMBRE_OVS"
        else
            echo "El puerto $puerto está en otro bridge ($current_bridge), removiendo..."
            sudo ovs-vsctl del-port $current_bridge $puerto
        fi
    fi
    
    # Agregar puerto al OvS si no está ya agregado
    if ! sudo ovs-vsctl list-ports $NOMBRE_OVS | grep -q "^$puerto$"; then
        echo "Agregando puerto $puerto al bridge $NOMBRE_OVS..."
        sudo ovs-vsctl add-port $NOMBRE_OVS $puerto
        
        if [ $? -eq 0 ]; then
            echo "Puerto $puerto agregado exitosamente"
            
            # Configurar como trunk port para permitir todas las VLANs
            echo "Configurando $puerto como trunk port..."
            sudo ovs-vsctl set port $puerto trunk=0-4094
            
            # Asegurar que el puerto esté UP
            sudo ip link set $puerto up
            
        else
            echo "Error al agregar puerto $puerto al bridge"
        fi
    fi
done

# Configurar el bridge como trunk switch
echo "=== Configurando bridge como switch central ==="

# Levantar el bridge
sudo ip link set $NOMBRE_OVS up

# Configurar el bridge en modo normal (no OpenFlow si no es necesario)
sudo ovs-vsctl set bridge $NOMBRE_OVS fail-mode=standalone

# Habilitar STP (Spanning Tree Protocol) para evitar loops
sudo ovs-vsctl set bridge $NOMBRE_OVS stp_enable=true

# Mostrar configuración final
echo "=== Configuración del OFS completada ==="
echo "Bridge: $NOMBRE_OVS"
echo "Puertos configurados:"
sudo ovs-vsctl list-ports $NOMBRE_OVS

echo ""
echo "=== Detalles de configuración OvS ==="
sudo ovs-vsctl show

# Mostrar tabla de MACs (si hay tráfico)
echo ""
echo "=== Estado del bridge ==="
sudo ovs-appctl fdb/show $NOMBRE_OVS

echo "=== OFS inicializado correctamente ==="
