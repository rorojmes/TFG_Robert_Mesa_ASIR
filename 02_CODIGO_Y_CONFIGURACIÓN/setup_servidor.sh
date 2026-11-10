#!/usr/bin/env bash
# ==============================================================================
# SCRIPT REPLICADOR DINÁMICO E INTERACTIVO CON MENÚ DE DESPLIEGUE Y CÓDIGOS QR
# Autor: Robert Mesa
# Repo: Configuración e Infraestructura de Servidor Linux (Blindado)
# ==============================================================================

USUARIO_ACTUAL="$USER"
HOME_ACTUAL="$HOME"

# No ejecutar como root: el script usa sudo internamente
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "❌ No ejecutes este script como root. Lánzalo como usuario normal (usa sudo dentro)."
    exit 1
fi

# Evitar exposición de claves generadas (umask restrictivo)
umask 077

# Detección dinámica de la interfaz de red principal
INTERFAZ_NET=$(ip route show default | awk '/default/ {print $5}' | head -n1)
if [ -z "$INTERFAZ_NET" ]; then
    echo "⚠️  No se pudo detectar la interfaz de red automáticamente."
    read -p "📌 Introduce la interfaz de red principal (ej: ens3, eth0): " INTERFAZ_NET
    [ -z "$INTERFAZ_NET" ] && INTERFAZ_NET="ens3"
fi

clear
echo "======================================================================"
echo "    CONFIGURACIÓN E INSTALACIÓN INTERACTIVA DEL SERVIDOR"
echo "    Usuario detectado:   ${USUARIO_ACTUAL}"
echo "    Directorio Home:     ${HOME_ACTUAL}"
echo "    Interfaz de Red:     ${INTERFAZ_NET}"
echo "======================================================================"
echo ""

# ------------------------------------------------------------------------------
# 0. MENÚ DE SELECCIÓN DE TIPO DE PROYECTO
# ------------------------------------------------------------------------------
echo "SELECCIONA EL TIPO DE DESPLIEGUE QUE DESEAS REALIZAR:"
echo "  1) Desplegar Nuevo Proyecto (Web Única / Single-site)"
echo "  2) Recuperar Proyecto Antiguo (Multi-sitio Dual: Danza + CV ASIR)"
echo ""
read -p "📌 Elige una opción (1 o 2): " TIPO_OPCION

while [[ "$TIPO_OPCION" != "1" && "$TIPO_OPCION" != "2" ]]; do
    read -p "⚠️  Opción no válida. Por favor, introduce 1 o 2: " TIPO_OPCION
done

echo ""
echo "----------------------------------------------------------------------"
# ------------------------------------------------------------------------------
# 1. SOLICITUD Y LIMPIEZA DE DATOS BÁSICOS
# ------------------------------------------------------------------------------
read -p "📌 Introduce tu correo electrónico para Certbot (SSL): " CORREO_INPUT
read -p "📌 Introduce el dominio principal (ej: miweb.com / robertmesa.es): " DOMINIO_INPUT
read -p "📌 Introduce el subdominio principal (ej: www.miweb.com / www.robertmesa.es): " SUBDOMINIO_INPUT

# Sanear entradas eliminando espacios no deseados
CORREO=$(echo "$CORREO_INPUT" | tr -d ' ')
DOMINIO=$(echo "$DOMINIO_INPUT" | tr -d ' ')
SUBDOMINIO=$(echo "$SUBDOMINIO_INPUT" | tr -d ' ')

echo ""
echo "======================================================================"
echo " Datos recolectados. Iniciando instalación y aprovisionamiento..."
echo "======================================================================"
sleep 2

# ------------------------------------------------------------------------------
# 2. INSTALACIÓN DE PAQUETES Y HERRAMIENTAS
# ------------------------------------------------------------------------------
# Backup previo de configuraciones existentes (por si se re-ejecuta sobre un servidor con datos)
if [ -d /etc/ssh ] || [ -d /etc/nginx ]; then
    sudo mkdir -p /root/recovery/pre-setup
    sudo cp -a /etc/ssh /etc/nginx /etc/fail2ban /etc/wireguard /root/recovery/pre-setup/ 2>/dev/null || true
    sudo iptables-save > /root/recovery/pre-setup/iptables.rules 2>/dev/null || true
    echo "  ✅ Backup previo guardado en /root/recovery/pre-setup/"
fi

echo "[1/11] Actualizando repositorios y paquetes del sistema..."
sudo apt update && sudo apt upgrade -y

echo "[2/11] Instalando paquetes esenciales, WireGuard, at y generador de QR..."
sudo apt install -y curl wget git unzip software-properties-common python3 python3-pip python3-venv iptables iptables-persistent netfilter-persistent fail2ban ffmpeg qrencode at
sudo systemctl enable --now atd 2>/dev/null || true

echo "[3/11] Configurando Memoria Swap (2GB) y TCP BBR..."
if [ ! -f /swapfile ]; then
    sudo fallocate -l 2G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    # Comprobar idempotencia antes de escribir en fstab
    if ! grep -q "/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    fi
fi

if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p
fi

# Habilitar forwarding IP para VPN
sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sudo sed -i 's/#net.ipv6.conf.all.forwarding=1/net.ipv6.conf.all.forwarding=1/' /etc/sysctl.conf
sudo sysctl -p

echo "[4/11] Aplicando Hardening SSH, Journald y cerrando rpcbind..."
sudo sed -i '/^SystemMaxUse=/d; /^#SystemMaxUse=/d' /etc/systemd/journald.conf
echo "SystemMaxUse=200M" | sudo tee -a /etc/systemd/journald.conf > /dev/null
sudo systemctl restart systemd-journald

# VERIFICACIÓN DINÁMICA DE SEGURIDAD SSH
if [ -f "$HOME/.ssh/authorized_keys" ] && [ -s "$HOME/.ssh/authorized_keys" ]; then
    echo "  ✅ Clave pública SSH detectada. Aplicando bloqueo de contraseñas de forma segura..."
    sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    # PermitRootLogin: cubrir tanto la forma comentada como la activa (without-password/prohibit-password)
    sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sudo sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config

    # Sobreescribir posibles anulaciones en sshd_config.d
    if [ -d /etc/ssh/sshd_config.d ]; then
        printf 'PasswordAuthentication no\nPermitRootLogin no\nX11Forwarding no\n' | sudo tee /etc/ssh/sshd_config.d/99-disable-passwords.conf > /dev/null
    fi

    # Validar configuración antes de reiniciar (evita bloqueo)
    if sudo sshd -t; then
        sudo systemctl restart ssh
    else
        echo "  ❌ sshd -t falló. No se reinicia SSH para no bloquearte. Revisa /etc/ssh/sshd_config."
    fi
else
    echo "  ⚠️ ADVERTENCIA: No se encontró clave SSH en $HOME/.ssh/authorized_keys."
    echo "  ⚠️ Se mantiene el acceso por contraseña para prevenir el bloqueo del servidor."
fi

sudo systemctl stop rpcbind rpcbind.socket || true
sudo systemctl disable rpcbind rpcbind.socket || true

echo "[5/11] Configurando Fail2ban..."
sudo tee /etc/fail2ban/jail.local > /dev/null << 'EOF'
[sshd]
enabled = true
port = 22
maxretry = 3
findtime = 10m
bantime = 48h
# Añadir aquí la IP pública del propietario y la del tailnet si se usa Tailscale
ignoreip = 127.0.0.1/8 ::1 100.64.0.0/10
EOF
sudo systemctl restart fail2ban
sudo systemctl enable fail2ban

echo "[6/11] Instalando Node.js v20 LTS, Nginx, WireGuard y Certbot..."
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt install -y nodejs
fi
sudo apt install -y nginx wireguard certbot python3-certbot-nginx

echo "[7/11] Creando estructura de directorios web y scripts..."
if [ "$TIPO_OPCION" == "1" ]; then
    sudo mkdir -p /var/www/app
else
    sudo mkdir -p /var/www/danza
    sudo mkdir -p /var/www/html
fi

mkdir -p "${HOME_ACTUAL}/scripts"
mkdir -p "${HOME_ACTUAL}/backups"
mkdir -p "${HOME_ACTUAL}/wireguard-clients"

sudo chown -R ${USUARIO_ACTUAL}:www-data /var/www/
sudo chmod -R 775 /var/www/

# ------------------------------------------------------------------------------
# 8. GENERACIÓN AUTOMÁTICA DE CLAVES Y CONFIGURACIÓN DE WIREGUARD
# ------------------------------------------------------------------------------
echo "[8/11] Generando claves automáticas de WireGuard con interfaz '${INTERFAZ_NET}'..."

# Bucle de validación para garantizar la captura de la IP pública
SERVER_IP=""
INTENTOS=0
while [ -z "$SERVER_IP" ] && [ $INTENTOS -lt 5 ]; do
    SERVER_IP=$(curl -s https://ifconfig.me || curl -s https://api.ipify.org)
    INTENTOS=$((INTENTOS+1))
    [ -z "$SERVER_IP" ] && sleep 2
done

if [ -z "$SERVER_IP" ]; then
    echo "⚠️  No se pudo determinar la IP pública automáticamente."
    read -p "📌 Por favor, ingresa manualmente la IP pública del servidor: " SERVER_IP
fi

SERVER_PRIV_KEY=$(wg genkey)
SERVER_PUB_KEY=$(echo "$SERVER_PRIV_KEY" | wg pubkey)

crear_cliente() {
    local NOMBRE=$1
    local IP_V4=$2
    local IP_V6=$3

    local CLIENT_PRIV=$(wg genkey)
    local CLIENT_PUB=$(echo "$CLIENT_PRIV" | wg pubkey)
    local CLIENT_PSK=$(wg genpsk)

    sudo tee -a /etc/wireguard/wg0.conf > /dev/null << EOF

### Client ${NOMBRE}
[Peer]
PublicKey = ${CLIENT_PUB}
PresharedKey = ${CLIENT_PSK}
AllowedIPs = ${IP_V4}/32,${IP_V6}/128
EOF

    cat << EOF > "${HOME_ACTUAL}/wireguard-clients/${NOMBRE}.conf"
[Interface]
PrivateKey = ${CLIENT_PRIV}
Address = ${IP_V4}/24,${IP_V6}/64
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = ${SERVER_PUB_KEY}
PresharedKey = ${CLIENT_PSK}
Endpoint = ${SERVER_IP}:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
}

sudo tee /etc/wireguard/wg0.conf > /dev/null << EOF
[Interface]
Address = 10.66.66.1/24,fd42:42:42::1/64
ListenPort = 51820
PrivateKey = ${SERVER_PRIV_KEY}
PostUp = iptables -I INPUT -p udp --dport 51820 -j ACCEPT
PostUp = iptables -I FORWARD -i ${INTERFAZ_NET} -o wg0 -j ACCEPT
PostUp = iptables -I FORWARD -i wg0 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o ${INTERFAZ_NET} -j MASQUERADE
PostUp = ip6tables -I FORWARD -i wg0 -j ACCEPT
PostUp = ip6tables -t nat -A POSTROUTING -o ${INTERFAZ_NET} -j MASQUERADE
PostDown = iptables -D INPUT -p udp --dport 51820 -j ACCEPT
PostDown = iptables -D FORWARD -i ${INTERFAZ_NET} -o wg0 -j ACCEPT
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o ${INTERFAZ_NET} -j MASQUERADE
PostDown = ip6tables -D FORWARD -i wg0 -j ACCEPT
PostDown = ip6tables -t nat -D POSTROUTING -o ${INTERFAZ_NET} -j MASQUERADE
EOF

crear_cliente "macbook" "10.66.66.2" "fd42:42:42::2"
crear_cliente "ipad" "10.66.66.3" "fd42:42:42::3"
crear_cliente "iphone" "10.66.66.4" "fd42:42:42::4"
crear_cliente "Mingos_phone" "10.66.66.5" "fd42:42:42::5"
crear_cliente "Mingos_Mac" "10.66.66.6" "fd42:42:42::6"

sudo chmod 600 /etc/wireguard/wg0.conf
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
if sudo wg show >/dev/null 2>&1; then
    echo "  ✅ WireGuard activo."
else
    echo "  ⚠️ WireGuard no levantó. Revisa 'systemctl status wg-quick@wg0'."
fi

chmod 700 "${HOME_ACTUAL}/wireguard-clients"
chmod 600 "${HOME_ACTUAL}/wireguard-clients/"*.conf

# ------------------------------------------------------------------------------
# 9. SCRIPT DE DESPLIEGUE CI/CD (deploy_server.py)
# ------------------------------------------------------------------------------
echo "[9/11] Creando script de despliegue automatizado (deploy_server.py)..."

NPM_PATH=$(which npm || echo "/usr/bin/npm")

if [ "$TIPO_OPCION" == "1" ]; then
    tee "${HOME_ACTUAL}/scripts/deploy_server.py" > /dev/null << EOF
#!/usr/bin/env python3
import os
import shutil
import zipfile
import subprocess
import glob

PROYECTO_DIR = "${HOME_ACTUAL}" 
EXTRACTION_DIR = os.path.join(PROYECTO_DIR, "temp_despliegue")
TARGET_DIR = "/var/www/app"
NPM_BIN = "${NPM_PATH}"

def procesar_despliegue():
    archivos_zip = glob.glob(os.path.join(PROYECTO_DIR, "*.zip"))

    if not archivos_zip:
        print(f"❌ Error: No se encontró ningún archivo ZIP en {PROYECTO_DIR}")
        return

    zip_path = archivos_zip[0]
    zip_name = os.path.basename(zip_path)
    print(f"📦 ¡Archivo detectado!: {zip_name}. Iniciando despliegue en {TARGET_DIR}...")

    deploy_ok = False
    try:
        if os.path.exists(EXTRACTION_DIR):
            shutil.rmtree(EXTRACTION_DIR)
        os.makedirs(EXTRACTION_DIR)

        print("-> Descomprimiendo archivo...")
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            # Validación anti zip-slip: ninguna ruta puede salir del directorio de extracción
            for _m in zip_ref.namelist():
                _dest = os.path.join(EXTRACTION_DIR, _m)
                if not os.path.abspath(_dest).startswith(os.path.abspath(EXTRACTION_DIR) + os.sep):
                    print("❌ ZIP inseguro: contiene rutas fuera del directorio de extracción.")
                    return
            zip_ref.extractall(EXTRACTION_DIR)

        macosx_folder = os.path.join(EXTRACTION_DIR, "__MACOSX")
        if os.path.exists(macosx_folder):
            shutil.rmtree(macosx_folder)

        print("-> Instalando dependencias y ejecutando build...")
        result = subprocess.run(
            [NPM_BIN, "install"],
            cwd=EXTRACTION_DIR,
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            result = subprocess.run(
                [NPM_BIN, "run", "build"],
                cwd=EXTRACTION_DIR,
                capture_output=True,
                text=True
            )

        if result.returncode != 0:
            print(f"❌ Error durante la compilación (npm): \n{result.stderr}")
            return
        print("✓ Compilación completada con éxito.")

        dist_dir = os.path.join(EXTRACTION_DIR, "dist")
        if not os.path.exists(dist_dir):
            print("❌ Error crítico: No se encontró la carpeta 'dist' generada.")
            return

        print(f"-> Copiando archivos a {TARGET_DIR}...")
        if not os.path.exists(TARGET_DIR):
            os.makedirs(TARGET_DIR)

        for item in os.listdir(dist_dir):
            s = os.path.join(dist_dir, item)
            d = os.path.join(TARGET_DIR, item)
            if os.path.isdir(s):
                if os.path.exists(d):
                    shutil.rmtree(d)
                shutil.copytree(s, d)
            else:
                shutil.copy2(s, d)

        print(f"✓ Sitio web actualizado en {TARGET_DIR}.")
        deploy_ok = True

    except Exception as e:
        print(f"❌ Ocurrió un fallo en el proceso: {e}")
        deploy_ok = False

    finally:
        print("-> Limpiando residuos...")
        if deploy_ok and os.path.exists(zip_path):
            os.remove(zip_path)
        elif os.path.exists(zip_path):
            print(f"⚠️ Se conserva el ZIP por fallo en el despliegue.")
        if os.path.exists(EXTRACTION_DIR):
            shutil.rmtree(EXTRACTION_DIR)
        if deploy_ok:
            print("🎉 ¡Proceso completado!")

if __name__ == "__main__":
    procesar_despliegue()
EOF

else
    tee "${HOME_ACTUAL}/scripts/deploy_server.py" > /dev/null << EOF
#!/usr/bin/env python3
import os
import shutil
import zipfile
import subprocess
import glob

PROYECTO_DIR = "${HOME_ACTUAL}" 
EXTRACTION_DIR = os.path.join(PROYECTO_DIR, "temp_robert_mesa")

REMOTE_DIR_DANZA = "/var/www/danza"
REMOTE_DIR_ASIR = "/var/www/html"
NPM_BIN = "${NPM_PATH}"

def procesar_despliegue():
    archivos_zip = glob.glob(os.path.join(PROYECTO_DIR, "*artista*.zip")) + glob.glob(os.path.join(PROYECTO_DIR, "*robert*.zip"))
    archivos_zip = list(set(archivos_zip))

    # Respaldo flexible si no coincide el nombre estándar
    if not archivos_zip:
        archivos_zip = glob.glob(os.path.join(PROYECTO_DIR, "*.zip"))

    if not archivos_zip:
        print(f"❌ Error: No se encontró ningún archivo ZIP coincidente en {PROYECTO_DIR}")
        return

    zip_path = archivos_zip[0]
    zip_name = os.path.basename(zip_path).lower()
    print(f"📦 ¡Archivo detectado en {PROYECTO_DIR}!: {zip_name}. Iniciando despliegue...")

    if "cv" in zip_name:
        target_dir = REMOTE_DIR_ASIR
        tipo_proyecto = "ASIRWEB (CV)"
    else:
        target_dir = REMOTE_DIR_DANZA
        tipo_proyecto = "ARTISTA (Danza)"

    print(f"🎯 Tipo de proyecto detectado: {tipo_proyecto} -> Destino: {target_dir}")

    deploy_ok = False
    deploy_ok = False
    try:
        if os.path.exists(EXTRACTION_DIR):
            shutil.rmtree(EXTRACTION_DIR)
        os.makedirs(EXTRACTION_DIR)

        print("-> Descomprimiendo archivo...")
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            # Validación anti zip-slip: ninguna ruta puede salir del directorio de extracción
            for _m in zip_ref.namelist():
                _dest = os.path.join(EXTRACTION_DIR, _m)
                if not os.path.abspath(_dest).startswith(os.path.abspath(EXTRACTION_DIR) + os.sep):
                    print("❌ ZIP inseguro: contiene rutas fuera del directorio de extracción.")
                    return
            zip_ref.extractall(EXTRACTION_DIR)

        macosx_folder = os.path.join(EXTRACTION_DIR, "__MACOSX")
        if os.path.exists(macosx_folder):
            shutil.rmtree(macosx_folder)

        print("-> Instalando dependencias y ejecutando build con ruta absoluta de npm...")
        result = subprocess.run(
            [NPM_BIN, "install"],
            cwd=EXTRACTION_DIR,
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            result = subprocess.run(
                [NPM_BIN, "run", "build"],
                cwd=EXTRACTION_DIR,
                capture_output=True,
                text=True
            )

        if result.returncode != 0:
            print(f"❌ Error durante la compilación (npm): \n{result.stderr}")
            return
        print("✓ Compilación completada con éxito (Carpeta 'dist' generada).")

        dist_dir = os.path.join(EXTRACTION_DIR, "dist")
        if not os.path.exists(dist_dir):
            print("❌ Error crítico: No se encontró la carpeta 'dist' generada tras el build.")
            return

        print(f"-> Copiando archivos compilados a {target_dir}...")
        if not os.path.exists(target_dir):
            os.makedirs(target_dir)

        for item in os.listdir(dist_dir):
            s = os.path.join(dist_dir, item)
            d = os.path.join(target_dir, item)
            if os.path.isdir(s):
                if os.path.exists(d):
                    shutil.rmtree(d)
                shutil.copytree(s, d)
            else:
                shutil.copy2(s, d)

        print(f"✓ Archivos de {tipo_proyecto} actualizados en {target_dir}.")
        deploy_ok = True

    except Exception as e:
        print(f"❌ Ocurrió un fallo en el proceso: {e}")
        deploy_ok = False

    finally:
        print("-> Iniciando limpieza de residuos...")
        if deploy_ok and os.path.exists(zip_path):
            os.remove(zip_path)
            print(f"✓ Archivo origen {zip_name} eliminado de la home.")
        elif os.path.exists(zip_path):
            print(f"⚠️ Se conserva {zip_name} por fallo en el despliegue.")
        if os.path.exists(EXTRACTION_DIR):
            shutil.rmtree(EXTRACTION_DIR)
            print("✓ Carpeta temporal de descompresión eliminada.")
        
        if deploy_ok:
            print("🎉 ¡Todo el proceso se completó y el servidor quedó limpio!")

if __name__ == "__main__":
    procesar_despliegue()
EOF
fi

chmod +x "${HOME_ACTUAL}/scripts/deploy_server.py"

# ------------------------------------------------------------------------------
# 10. CONFIGURACIÓN DE NGINX Y CERTBOT
# ------------------------------------------------------------------------------
echo "[10/11] Configurando Server Blocks de Nginx..."

if [ "$TIPO_OPCION" == "1" ]; then
    sudo tee /etc/nginx/sites-available/default > /dev/null << EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name ${DOMINIO} ${SUBDOMINIO} _;
    root /var/www/app;
    index index.html;

    gzip on;
    gzip_vary on;
    gzip_min_length 10240;
    gzip_proxied any;
    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/xml application/javascript image/svg+xml;
    gzip_disable "MSIE [1-6]\.";

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)\$ {
        expires 1y;
        add_header Cache-Control "public, no-transform";
    }
}
EOF
    sudo rm -f /etc/nginx/sites-enabled/danza 2>/dev/null || true
    sudo ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/

else
    sudo tee /etc/nginx/sites-available/default > /dev/null << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;
    root /var/www/html;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF

    sudo tee /etc/nginx/sites-available/danza > /dev/null << EOF
server {
    server_name ${DOMINIO} ${SUBDOMINIO};

    root /var/www/danza;
    index index.html;

    gzip on;
    gzip_vary on;
    gzip_min_length 10240;
    gzip_proxied any;
    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/xml application/javascript image/svg+xml;
    gzip_disable "MSIE [1-6]\.";

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)\$ {
        expires 1y;
        add_header Cache-Control "public, no-transform";
        include /etc/nginx/snippets/security-headers.conf;
    }

    include /etc/nginx/snippets/security-headers.conf;
    server_tokens off;
}
EOF
    sudo ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/danza /etc/nginx/sites-enabled/
fi

# Hardening global de nginx
sudo sed -i 's/^# *server_tokens off;/server_tokens off;/' /etc/nginx/nginx.conf
sudo sed -i 's/ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;/ssl_protocols TLSv1.2 TLSv1.3;/' /etc/nginx/nginx.conf

# Cabeceras de seguridad reutilizables
sudo mkdir -p /etc/nginx/snippets
sudo tee /etc/nginx/snippets/security-headers.conf > /dev/null << 'EOF'
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
EOF

if sudo nginx -t; then
    sudo systemctl restart nginx
    sudo systemctl enable nginx
fi

echo "[11/11] Aplicando reglas de cortafuegos local y emitiendo certificado SSL..."
sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables -I INPUT -p udp --dport 51820 -j ACCEPT
sudo netfilter-persistent save

SSL_SUCCESS=0
sudo certbot --nginx --non-interactive --agree-tos --email "$CORREO" -d "$DOMINIO" -d "$SUBDOMINIO" --redirect && SSL_SUCCESS=1

if [ $SSL_SUCCESS -eq 0 ]; then
    echo ""
    echo "⚠️  ATENCIÓN: Certbot no pudo emitir el certificado SSL."
    echo "⚠️  Causa probable: Las entradas DNS A de ${DOMINIO} / ${SUBDOMINIO} aún no apuntan a la IP (${SERVER_IP})."
    echo ""
    read -p "❓ ¿Deseas programar un intento automático de emisión de SSL dentro de 24 horas mediante 'crontab'? (s/n): " PROGRAMAR_SSL
    if [[ "$PROGRAMAR_SSL" =~ ^[Ss]$ ]]; then
        COMANDO_SSL="certbot --nginx --non-interactive --agree-tos --email ${CORREO} -d ${DOMINIO} -d ${SUBDOMINIO} --redirect"
        (sudo crontab -l 2>/dev/null; echo "0 $(date +%H) * * * $COMANDO_SSL") | sudo crontab -
        echo "✅ Tarea de Crontab de root configurada para reintentar SSL automáticamente en 24 horas."
    else
        echo "ℹ️  Has omitido la programación. Cuando la DNS propague, ejecuta manualmente:"
        echo "   sudo certbot --nginx -d ${DOMINIO} -d ${SUBDOMINIO}"
    fi
    sleep 3
fi

# ------------------------------------------------------------------------------
# 12. (OPCIONAL) RED DE SEGURIDAD: TAILSCALE + UBUNTU PRO
# ------------------------------------------------------------------------------
echo ""
read -p "¿Deseas instalar Tailscale como puerta de rescate independiente de SSH? (s/n): " INSTALAR_TS
if [[ "$INSTALAR_TS" =~ ^[Ss]$ ]]; then
    curl -fsSL https://tailscale.com/install.sh -o /tmp/tailscale-install.sh
    sudo sh /tmp/tailscale-install.sh
    sudo systemctl enable --now tailscaled
    sudo tailscale up --accept-dns=false
    echo "  Abre la URL que aparece arriba en tu navegador y autentica el servidor."
    read -p "  Pulsa ENTER cuando el servidor aparezca en tu tailnet..."
    sudo tailscale up --ssh --accept-dns=false
    echo "  ✅ Tailscale SSH activado. Prueba: ssh ${USUARIO_ACTUAL}@<ip-tailscale>"
fi

read -p "¿Deseas adherir el servidor a Ubuntu Pro? (requiere token) (s/n): " INSTALAR_PRO
if [[ "$INSTALAR_PRO" =~ ^[Ss]$ ]]; then
    read -p "  Pega tu token de Ubuntu Pro: " PRO_TOKEN
    echo "$PRO_TOKEN" | sudo pro attach --no-auto-enable
    sudo pro enable esm-infra esm-apps
    echo "  ✅ Ubuntu Pro adherido (esm-infra + esm-apps)."
fi

# Retener OpenSSH y kernel para no perder acceso por una actualización sorpresa
sudo apt-mark hold openssh-server openssh-client openssh-sftp-server \
  linux-oracle linux-image-oracle linux-headers-oracle 2>/dev/null || true
echo "  ✅ OpenSSH y kernel retenidos (hold)."

# ------------------------------------------------------------------------------
# MUESTRA DE CÓDIGOS QR EN PANTALLA Y NOTIFICACIONES FINALES
# ------------------------------------------------------------------------------
clear
echo "======================================================================"
echo "          ¡INSTALACIÓN COMPLETADA EXITOSAMENTE!"
echo "======================================================================"
echo " A continuación se muestran los códigos QR para conectar tus dispositivos."
echo " Abre la app de WireGuard en el dispositivo y elige 'Añadir desde QR'."
echo "======================================================================"
echo ""

for CLIENT_CONF in "${HOME_ACTUAL}"/wireguard-clients/*.conf; do
    if [ -f "$CLIENT_CONF" ]; then
        CLIENT_NAME=$(basename "$CLIENT_CONF" .conf)
        echo "----------------------------------------------------------------------"
        echo " 📱 CÓDIGO QR PARA DISPOSITIVO: ${CLIENT_NAME^^}"
        echo "----------------------------------------------------------------------"
        qrencode -t ansiutf8 < "$CLIENT_CONF"
        echo ""
        read -p "Presiona ENTER para ver el código QR del siguiente dispositivo..."
        clear
    fi
done

echo "======================================================================"
echo " 🌐 CONFIGURACIÓN DE RED Y DOMINIOS DE TU SERVIDOR 🌐"
echo "======================================================================"
echo " 📌 LA DIRECCIÓN IP PÚBLICA DE ESTE SERVIDOR ES: ${SERVER_IP}"
echo ""
echo " ⚠️  IMPORTANTE - ASOCIACIÓN DNS:"
echo "   Asegúrate de ir a tu proveedor de dominio (Hostinger / Cloudflare / DNS)"
echo "   y actualizar los registros de tipo A para que apunten a esta nueva IP:"
echo "     • Registro A (${DOMINIO})     --> ${SERVER_IP}"
echo "     • Registro A (${SUBDOMINIO}) --> ${SERVER_IP}"
echo ""
echo " 🚨 CORTAFUEGOS EXTERNO / GRUPO DE SEGURIDAD (EN TU PROVEEDOR DE NUBE):"
echo "   Asegúrate de abrir los siguientes puertos de entrada en el panel web"
echo "   de tu proveedor (Oracle Cloud, AWS, Hetzner, DigitalOcean, etc.):"
echo "     - TCP 22    (SSH)"
echo "     - TCP 80    (HTTP)"
echo "     - TCP 443   (HTTPS)"
echo "     - UDP 51820 (WireGuard VPN)"
echo ""
echo " Perfiles guardados con permisos protegidos (600) en: ${HOME_ACTUAL}/wireguard-clients/"
echo " Para ver un QR individual en el futuro, ejecuta:"
echo "   qrencode -t ansiutf8 < ${HOME_ACTUAL}/wireguard-clients/iphone.conf"
echo "======================================================================"