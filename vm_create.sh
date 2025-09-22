#!/bin/bash

# Script: vm_create.sh
# Propósito: Crear una VM y conectarla al OvS con VLAN específica
# Parámetros: NombreVM NombreOvS VLAN_ID PuertoVNC

# Verificar parámetros
if [ $# -ne 4 ]; then
    echo "Uso: $0 <NombreVM> <NombreOvS> <VLAN_ID> <PuertoVNC>"
    echo "Ejemplo: $0 vm1 br-int 100 5901"
    exit 1
fi

NOMBRE_VM=$1
NOMBRE_OVS=$2
VLAN_ID=$3
PUERTO_VNC=$4

# Configuraciones por defecto
RAM_MB=1024
DISCO_SIZE="10G"
VM_DIR="/tmp/vms"
ISO_PATH="/tmp/ubuntu-server.iso"  # Ajustar según disponibilidad

echo "=== Creando VM: $NOMBRE_VM ==="
echo "OvS: $NOMBRE_OVS"
echo "VLAN ID: $VLAN_ID"
echo "Puerto VNC: $PUERTO_VNC"

# Crear directorio para VMs si no existe
sudo mkdir -p $VM_DIR
cd $VM_DIR

# Verificar que el bridge OvS existe
if ! sudo ovs-vsctl br-exists $NOMBRE_OVS; then
    echo "Error: El bridge $NOMBRE_OVS no existe"
    exit 1
fi

# Crear disco de la VM
DISCO_PATH="$VM_DIR/${NOMBRE_VM}.qcow2"
if [ ! -f $DISCO_PATH ]; then
    echo "Creando disco virtual para $NOMBRE_VM..."
    sudo qemu-img create -f qcow2 $DISCO_PATH $DISCO_SIZE
fi

# Crear interfaz TAP para la VM
TAP_INTERFACE="tap-$NOMBRE_VM"
echo "Creando interfaz TAP: $TAP_INTERFACE"

# Eliminar TAP si ya existe
sudo ip tuntap del dev $TAP_INTERFACE mode tap 2>/dev/null

# Crear nueva interfaz TAP
sudo ip tuntap add dev $TAP_INTERFACE mode tap
sudo ip link set $TAP_INTERFACE up

# Conectar TAP al OvS y asignar VLAN
echo "Conectando $TAP_INTERFACE al bridge $NOMBRE_OVS con VLAN $VLAN_ID"
sudo ovs-vsctl add-port $NOMBRE_OVS $TAP_INTERFACE

# Configurar VLAN en el puerto (access port)
sudo ovs-vsctl set port $TAP_INTERFACE tag=$VLAN_ID

# Función para verificar si el puerto VNC está disponible
check_vnc_port() {
    netstat -ln | grep ":$1 " >/dev/null 2>&1
}

if check_vnc_port $PUERTO_VNC; then
    echo "Advertencia: El puerto VNC $PUERTO_VNC ya está en uso"
fi

# Crear script de inicio de VM
STARTUP_SCRIPT="$VM_DIR/start_${NOMBRE_VM}.sh"
cat > $STARTUP_SCRIPT << EOF
#!/bin/bash
# Script de inicio para $NOMBRE_VM

# Verificar si la VM ya está corriendo
if pgrep -f "qemu.*${NOMBRE_VM}" > /dev/null; then
    echo "La VM $NOMBRE_VM ya está ejecutándose"
    exit 1
fi

# Iniciar VM con QEMU
sudo qemu-system-x86_64 \\
    -name $NOMBRE_VM \\
    -m $RAM_MB \\
    -hda $DISCO_PATH \\
    -netdev tap,id=net0,ifname=$TAP_INTERFACE,script=no,downscript=no \\
    -device virtio-net-pci,netdev=net0,mac=52:54:00:\$(printf '%02x:%02x:%02x' \$((RANDOM%256)) \$((RANDOM%256)) \$((RANDOM%256))) \\
    -vnc :$(($PUERTO_VNC - 5900)) \\
    -daemonize \\
    -pidfile $VM_DIR/${NOMBRE_VM}.pid

echo "VM $NOMBRE_VM iniciada en puerto VNC $PUERTO_VNC"
echo "Conectar con: vncviewer localhost:$PUERTO_VNC"
EOF

chmod +x $STARTUP_SCRIPT

# Iniciar la VM
echo "Iniciando VM $NOMBRE_VM..."
bash $STARTUP_SCRIPT

# Verificar configuración
echo "=== Configuración de la VM ==="
echo "Nombre: $NOMBRE_VM"
echo "Interfaz TAP: $TAP_INTERFACE"
echo "VLAN ID: $VLAN_ID"
echo "Puerto VNC: $PUERTO_VNC"
echo "Script de inicio: $STARTUP_SCRIPT"

# Mostrar configuración del puerto en OvS
echo "=== Configuración del puerto en OvS ==="
sudo ovs-vsctl show | grep -A 5 -B 5 $TAP_INTERFACE

echo "=== VM $NOMBRE_VM creada exitosamente ==="
