OCI Linux Server Setup & Hardening RunbookEste repositorio contiene la guía de despliegue paso a paso para configurar, fortificar y optimizar una instancia de Oracle Cloud Infrastructure (OCI) (VM.Standard.E2.1.Micro - 1GB RAM). El objetivo es establecer una base sólida y segura para alojar servicios web ligeros (Nginx) y una red privada virtual (WireGuard) superando las limitaciones de hardware de la capa gratuita (Free Tier).🛠️ 

Fase 1: Preparación y Optimización del Sistema. La instancia inicial cuenta con pocos recursos (1GB RAM). Se procederá a optimizar la memoria y la gestión de red antes de instalar cualquier servicio.

1.1 Actualización Base del SistemaAsegurar que los repositorios y el software están al día.
 
sudo apt update && sudo apt upgrade -y

1.2 Configuración de Memoria SWAP (2GB)Objetivo: Evitar que el sistema mate procesos por falta de memoria RAM (OOM Killer) creando un archivo de paginación en disco.Ejecución:# 

# 1. Crear un archivo de 2GB
sudo fallocate -l 2G /swapfile

# 2. Asignar permisos estrictos (solo root puede leer/escribir)
sudo chmod 600 /swapfile

# 3. Formatear el archivo como partición swap
sudo mkswap /swapfile

# 4. Activar la swap en el sistema
sudo swapon /swapfile

# 5. Hacer el cambio persistente añadiéndolo al fstab
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# 6. Comprobar que está activa
sudo free -h

1.3 Aceleración de Red (TCP BBR) Objetivo: Activar el algoritmo BBR de Google en el kernel de Linux para maximizar el ancho de banda y reducir la latencia de la VPN y el servidor web. Ejecución:

# 1. Añadir los parámetros al archivo sysctl
echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf

# 2. Aplicar los cambios sin reiniciar
sudo sysctl -p

# 3. Verificar que BBR está activo
sysctl net.ipv4.tcp_congestion_control

1.4 Límite de Tamaño de Logs (Journald) Objetivo: Prevenir el colapso del disco duro (Block Volume) limitando el historial de logs del sistema a 200MB.Ejecución:

# 1. Editar el archivo de configuración
sudo sed -i 's/#SystemMaxUse=/SystemMaxUse=200M/g' /etc/systemd/journald.conf

# 2. Reiniciar el demonio de logs para aplicar el límite

sudo systemctl restart systemd-journald

Fase 2: Hardening y Seguridad Perimetral2.1 Deshabilitar Autenticación por Contraseña (SSH)Objetivo: Forzar el acceso remoto exclusivamente mediante llaves criptográficas para mitigar ataques de fuerza bruta.Ejecución:# 1. Editar la configuración del servicio SSH
sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#PasswordAuthentication no/PasswordAuthentication no/' /etc/ssh/sshd_config

# 2. Reiniciar el servicio SSH
sudo systemctl restart sshd

2.2 Instalación de Prevención de Intrusiones (Fail2Ban)Objetivo: Analizar los logs en tiempo real y banear temporalmente en el firewall las IPs que realicen intentos fallidos de conexión.Ejecución:# 1. Instalar el paquete
sudo apt install fail2ban -y

# 2. Iniciar y habilitar el servicio para que arranque con el sistema
sudo systemctl enable --now fail2ban

2.3 Configuración del Firewall (UFW)Objetivo: Bloquear todo el tráfico entrante por defecto y abrir solo los puertos necesarios para este proyecto.Atención: La configuración del cortafuegos de Oracle (Security Lists y NSG) debe sincronizarse manualmente desde el panel web de OCI para coincidir con estas reglas.Ejecución:# 1. Permitir puertos necesarios
sudo ufw allow 22/tcp     # SSH
sudo ufw allow 80/tcp     # HTTP Web
sudo ufw allow 443/tcp    # HTTPS Web
sudo ufw allow 51820/udp  # WireGuard VPN

# 2. Habilitar el cortafuegos (Confirmar con 'y' si advierte sobre conexiones SSH)
sudo ufw enable

# 3. Comprobar el estado
sudo ufw status verbose

Fase 3: Despliegue de Servicios3.1 Servidor Web (Nginx) y Configuración de PermisosObjetivo: Instalar el servidor web y preparar el directorio raíz para permitir subidas de archivos mediante SFTP (Cyberduck/FileZilla) usando el usuario estándar ubuntu sin necesidad de ser root.Ejecución:# 1. Instalar Nginx
sudo apt install nginx -y

# 2. Cambiar el propietario de la carpeta web. 
# Usuario: ubuntu | Grupo: www-data (Nginx)
sudo chown -R ubuntu:www-data /var/www/html

# 3. Ajustar permisos para que el grupo (Nginx) pueda leer, y el usuario (ubuntu) pueda leer/escribir.
sudo chmod -R 775 /var/www/html
A partir de este punto, se pueden subir los archivos estáticos (index.html, css, js) directamente a /var/www/html mediante un cliente SFTP.3.2 Despliegue de VPN (WireGuard)Objetivo: Establecer un túnel seguro de alto rendimiento operando en el puerto 51820 UDP.Ejecución:# 1. Instalar dependencias
sudo apt install wireguard -y

(Nota: La configuración específica de las claves y clientes de WireGuard varía por despliegue. Generar claves con wg genkey y configurar /etc/wireguard/wg0.conf).3.3 Filtrado DNS Privado (AdGuard Home)Objetivo: Resolver peticiones DNS de los clientes de la VPN, bloqueando rastreadores y anuncios a nivel de red.Ejecución:# 1. Descargar y ejecutar el script oficial de instalación silenciosa
curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v

(Nota: Tras la instalación, completar el asistente de configuración accediendo a http://[IP_SERVIDOR]:3000 y asegurar que la interfaz de escucha DNS apunte a la IP de la interfaz wg0 de WireGuard para evitar conflictos con systemd-resolved).🚨 Fase 4: Troubleshooting (Problemas Conocidos)4.1 Error: Nginx no responde al exterior (Connection Timeout)Si Nginx funciona localmente (curl localhost) y UFW muestra el puerto 80 abierto, pero no hay acceso desde internet:Causa: Bloqueo en la infraestructura física de Oracle Cloud.Diagnóstico: Los logs de /var/log/nginx/access.log no muestran peticiones entrantes.Solución:Acceder al panel de Oracle Cloud.Navegar a Compute > Instances > [Tu Instancia].Bajar hasta Attached VNICs y hacer clic en la VNIC principal.Revisar los Network Security Groups (NSG) aplicados. Un NSG obsoleto o restrictivo puede estar ignorando las Security Lists de la VCN.Modificar el NSG o añadir las reglas Ingress para los puertos TCP 80/443.