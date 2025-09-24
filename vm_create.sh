#!/bin/bash

# Script: vm_create.sh
# Propósito: Crear una VM y conectarla al OvS con VLAN específica
# Parámetros: NombreVM NombreOvS VLAN_ID PuertoVNC [ImagenSO]

if [ $# -lt 4 ]; then
    echo "Uso: $0 <NombreVM> <NombreOvS> <VLAN_ID> <PuertoVNC> [ImagenSO]"
    echo "Ejemplo con disco vacío + ISO: $0 vm1 br-int 100 5901"
    echo "Ejemplo con imagen SO:        $0 vm1 br-int 100 5901 /tmp/cirros.img"
    exit 1
fi

NOMBRE_VM=$1
NOMBRE_OVS=$2
VLAN_ID=$3
PUERTO_VNC=$4
IMAGEN_SO=$5

# Configuración por defecto
RAM_MB=1024
DISCO_SIZE="10G"
VM_DIR="/tmp/vms"
ISO_PATH="/tmp/ubuntu-server.iso"  # Se usará solo si no hay IMAGEN_SO

echo "=== Creando VM: $NOMBRE_VM ==="
echo "OvS: $NOMBRE_OVS"
echo "VLAN ID: $VLAN_ID"
echo "Puerto VNC: $PUERTO_VNC"
[ -n "$IMAGEN_SO" ] && echo "Imagen SO: $IMAGEN_SO"

# Crear directorio para VMs si no existe
sudo mkdir -p $VM_DIR
cd $VM_DIR

# Verificar que el bridge OvS existe
if ! sudo ovs-vsctl br-exists $NOMBRE_OVS; then
    echo "Error: El bridge $NOMBRE_OVS no existe"
    exit 1
fi

# Ruta del disco
DISCO_PATH="$VM_DIR/${NOMBRE_VM}.qcow2"

# Si no se pasa imagen de SO → crear disco vacío
if [ -z "$IMAGEN_SO" ]; then
    if [ ! -f $DISCO_PATH ]; then
        echo "Creando disco virtual para $NOMBRE_VM..."
        sudo qemu-img create -f qcow2 $DISCO_PATH $DISCO_SIZE
    fi
else
    DISCO_PATH=$IMAGEN_SO
fi

# Crear interfaz TAP para la VM
TAP_INTERFACE="tap-$NOMBRE_VM"
echo "Creando interfaz TAP: $TAP_INTERFACE"
sudo ip tuntap del dev $TAP_INTERFACE mode tap 2>/dev/null
sudo ip tuntap add dev $TAP_INTERFACE mode tap
sudo ip link set $TAP_INTERFACE up

# Conectar TAP al OvS y asignar VLAN
echo "Conectando $TAP_INTERFACE al bridge $NOMBRE_OVS con VLAN $VLAN_ID"
sudo ovs-vsctl add-port $NOMBRE_OVS $TAP_INTERFACE
sudo ovs-vsctl set port $TAP_INTERFACE tag=$VLAN_ID

# Script de inicio
STARTUP_SCRIPT="$VM_DIR/start_${NOMBRE_VM}.sh"
cat > $STARTUP_SCRIPT << EOF
#!/bin/bash
if pgrep -f "qemu.*${NOMBRE_VM}" > /dev/null; then
    echo "La VM $NOMBRE_VM ya está ejecutándose"
    exit 1
fi

sudo qemu-system-x86_64 \\
    -enable-kvm \\
    -name $NOMBRE_VM \\
    -m $RAM_MB \\
    -hda $DISCO_PATH \\
    -netdev tap,id=net0,ifname=$TAP_INTERFACE,script=no,downscript=no \\
    -device virtio-net-pci,netdev=net0,mac=52:54:00:\$(printf '%02x:%02x:%02x' \$((RANDOM%256)) \$((RANDOM%256)) \$((RANDOM%256))) \\
    -vnc :$(($PUERTO_VNC - 5900)) \\
    -daemonize \\
    -pidfile $VM_DIR/${NOMBRE_VM}.pid \\
EOF

# Si no hay imagen, añadir arranque desde ISO
if [ -z "$IMAGEN_SO" ] && [ -f $ISO_PATH ]; then
    echo "    -cdrom $ISO_PATH \\" >> $STARTUP_SCRIPT
    echo "    -boot d \\" >> $STARTUP_SCRIPT
fi

chmod +x $STARTUP_SCRIPT

# Iniciar la VM
echo "Iniciando VM $NOMBRE_VM..."
bash $STARTUP_SCRIPT

# Info final
echo "=== Configuración de la VM ==="
echo "Nombre: $NOMBRE_VM"
echo "Interfaz TAP: $TAP_INTERFACE"
echo "VLAN ID: $VLAN_ID"
echo "Puerto VNC: $PUERTO_VNC"
echo "Disco/Imagen: $DISCO_PATH"
echo "Script de inicio: $STARTUP_SCRIPT"
