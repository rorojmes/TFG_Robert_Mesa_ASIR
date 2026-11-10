OCI Cloud Infrastructure & CI/CD Automated Pipeline

Resumen del Proyecto

Este repositorio documenta la arquitectura, fortificación y automatización de un servidor Linux alojado en Oracle Cloud Infrastructure (OCI) (Instancia VM.Standard.E2.1.Micro).

El objetivo principal de este proyecto es demostrar la capacidad para diseñar y administrar un entorno con recursos ultra-optimizados (1GB RAM) y seguridad perimetral, albergando una arquitectura multi-sitio web y una VPN privada, gestionado íntegramente mediante un pipeline híbrido de CI/CD desde dispositivos móviles (iPadOS) y portátiles (macOS).

Stack Tecnológico

Cloud Provider: Oracle Cloud Infrastructure (OCI)

Sistema Operativo: Ubuntu 20.04.6 LTS Linux (kernel 5.15.0-1081-oracle)

Servidor Web & Proxy: Nginx

Seguridad: UFW, Fail2Ban, Criptografía Asimétrica (Ed25519/RSA), SSL/TLS (Let's Encrypt)

Redes: WireGuard VPN, TCP BBR, DNS Management

CI/CD & Scripting: Python 3, Bash, AppleScript, SFTP

Frontend: React, Vite, Tailwind CSS 4

Fase 1: Aprovisionamiento y Optimización del SO

Dadas las restricciones de hardware (1GB RAM), se implementaron ajustes a nivel de kernel para garantizar la estabilidad:

Memoria de Intercambio (SWAP): Creación de un swapfile de 2GB para mitigar la intervención del proceso OOM Killer.

Control de Congestión TCP BBR: Activación del algoritmo de Google en el kernel para maximizar el rendimiento del ancho de banda.

Control de Logs (Journald): Límite de retención de registros a 200MB para evitar la degradación del almacenamiento local (/etc/systemd/journald.conf).

Fase 2: Hardening y Seguridad Perimetral

Implementación de una estrategia de Defensa en Profundidad (Defense in Depth):

Desactivación de Autenticación por Contraseña: Acceso SSH restringido de forma exclusiva al intercambio de llaves criptográficas (KEX).

Mitigación de Fuerza Bruta: Despliegue de Fail2Ban para la monitorización heurística de logs y baneos automáticos en el firewall.

Firewall Híbrido: Listas de Seguridad y NSGs en la consola de Oracle (Capa Cloud) en conjunción con `iptables-persistent` + reglas de `fail2ban` + `PostUp` de WireGuard (Capa Sistema Operativo). Nota: UFW está inactivo (`ENABLED=no`); el filtrado real lo hace iptables. IPv6 con política por defecto ACCEPT (pendiente de endurecer).

Fase 3: Networking y WireGuard VPN

Despliegue de un túnel cifrado privado operando en la capa de kernel:

Configuración de interfaz virtual wg0 escuchando en el puerto 51820 UDP.

Entorno Multi-Peer: Enrutamiento por claves públicas (Cryptokey Routing) para permitir el acceso simultáneo de múltiples clientes (Mac y dispositivos móviles) aislando sus IPs internas (ej. 10.66.66.2 y 10.66.66.3).

Fase 4: Arquitectura Multi-Sitio y Rendimiento Web (Nginx)

Implementación de Server Blocks basados en nombres de host para servir diferentes proyectos desde la misma máquina:

Despliegue del dominio principal (robertmesa.es) y subdominios (www) con enrutamiento de peticiones de Single Page Applications (SPA).

Securización automática del tráfico HTTP hacia HTTPS mediante certificados SSL/TLS de Let's Encrypt (Certbot).

WPO (Web Performance Optimization): Activación de compresión gzip dinámica en Nginx para aligerar la carga de la red.

SEO Avanzado: Inyección de esquemas de datos estructurados (JSON-LD), robots.txt estricto y sitemaps autogenerados para optimización de rastreo de Googlebot.

Fase 5: Pipeline CI/CD Híbrido (iPadOS / macOS)

Desarrollo de un sistema autónomo de integración continua capaz de actualizar la plataforma de producción sin depender de un equipo de escritorio local.

El pipeline se basa en un script de Python 3 alojado en el servidor (deploy_server.py) que automatiza el siguiente flujo al recibir una carga binaria por SFTP:

Detección Dinámica: Monitorización heurística en la capa de usuario de la llegada de paquetes .zip.

Sandbox: Descompresión en un directorio temporal aislado y limpieza de metadatos residuales del SO origen.

Compilación Nativa: Ejecución síncrona de dependencias (Node.js v20) y empaquetado de assets estáticos (npm run build).

Despliegue Atómico: Sustitución en caliente del directorio /var/www/danza mitigando el downtime.

Garbage Collection: Purga automatizada de artefactos temporales tras operaciones exitosas o fallidas (manejo de excepciones try/finally).

Fase 6: Resolución de Incidentes (Troubleshooting)

Bloqueo Perimetral (NXDOMAIN & Connection Timeout): Diagnóstico de filtrado de paquetes a nivel 3/4 utilizando tcpdump para aislar bloqueos residuales en los Network Security Groups (NSG) de OCI.

Desincronización Criptográfica (WireGuard): Resolución de handshakes fallidos detectados en logs del sistema causados por rotación de IPs públicas efímeras.
Fase 7: Recuperación de acceso, Ubuntu Pro y parcheo seguro (noviembre 2026)

Contexto: tras 249 días de uptime, se detecta que Ubuntu 20.04 standard support terminó el 31/05/2025 y el servidor no está adherido a Ubuntu Pro. 216 actualizaciones de seguridad pendientes (esm-infra + esm-apps), incluyendo kernel, OpenSSH, OpenSSL, sudo, glibc y systemd. 
Restricción de seguridad adoptada: congelar SSH, firewall y reinicio hasta verificar Tailscale como vía de acceso independiente. No se tocó `sshd_config`, ni el puerto 22, ni UFW/iptables.

7.1 Red de seguridad: Tailscale + Tailscale SSH
- Instalado Tailscale (v1.104.5) con `--accept-dns=false` (no toca el DNS del servidor).
- IP en el tailnet: <TAILSCALE_IP>. MagicDNS: <TAILSCALE_HOSTNAME>.
- Activado Tailscale SSH (`tailscale up --ssh`): la conexión la atiende `tailscaled`, no `sshd`. Verificado desde Mac e iPhone (con Wi-Fi apagado, por datos móviles). Alias SSH: `ssh roro-vpn-ts`.
- La puerta pública (`ssh roro-vpn`) sigue funcionando igual; ambas conviven.
- Endurecimiento de la cuenta: MFA (Apple ID 2FA), device approval, expiración de clave del servidor desactivada (caducaba 05/05/2027).

7.2 Backups y retención
- Backup completo (628 MB) en `~/Backups/roro-vpn/` y copia en `/root/recovery/2026-11-06/` (ssh, pam.d, sudoers, nginx, fail2ban, wireguard, iptables, ip6tables).
- Segunda clave SSH de emergencia generada y probada.
- `apt-mark hold` sobre openssh-server/client/sftp-server y el stack del kernel (5.15.0-1081-oracle) para evitar actualizaciones/reinicios sorpresa.

7.3 Ubuntu Pro y parcheo seguro
- Adherido a Ubuntu Pro (suscripción personal gratuita, hasta 5 máquinas).
- `esm-infra` y `esm-apps` habilitados hasta 2030.
- `apt upgrade` aplicado: ~200 paquetes (nginx, fail2ban, OpenSSL, systemd, sudo, glibc, libpam, curl, git, etc.).
- Resultado: `sshd` con el mismo PID, puerto 22 activo, `sshd -t` OK, nginx/fail2ban/tailscaled activos, sistema en estado `running`.

7.4 Hardening de bajo riesgo (sin tocar SSH ni firewall)
- WireGuard: `/etc/wireguard/wg0.conf` y `params` → modo 600 (contenían la clave privada del servidor). Los 5 `.conf` de clientes movidos de `/home/ubuntu` (world-readable, 644 en dir 755) a `/root/wireguard-clients/` con modo 600.
- nginx: `server_tokens off` (global + vhost), cabeceras HSTS, X-Content-Type-Options, X-Frame-Options, Referrer-Policy en robertmesa.es. TLS limitado a 1.2/1.3. Verificado con `curl -I`.
- fail2ban: `bantime` de 744 h a 48 h; `ignoreip` con loopback, tailnet (100.64.0.0/10) y la IP pública del propietario.
- Journal: 840 MB → 192 MB (`journalctl --vacuum-size=200M` + reinicio de journald).
- apt cache limpiado. Disco: 7.8 G usados de 45 G.
- `motd-news` reparado (permiso de ejecución) y systemd sin unidades fallidas.

7.5 Pendiente (ventana de mantenimiento controlada)
- Actualizar OpenSSH y recargar (no reiniciar) con prueba de conexión nueva.
- Instalar kernel nuevo y reiniciar en ventana controlada.
- Endurecer `sshd_config` (PermitRootLogin no, X11Forwarding no, AllowUsers, etc.) y firewall (UFW/iptables, ip6tables default DROP).
- Cerrar el puerto 22 público cuando Tailscale sea la única vía de administración.

7.6 Notas de seguridad adicionales
- `deploy_server.py` ejecuta `npm install && npm run build` con `shell=True` como `ubuntu`, que tiene `NOPASSWD:ALL`. Riesgo de inyección si se despliega un ZIP malicioso. Revisar antes de usar en producción.
- No hay backups automáticos (sin restic/borg/duplicity); solo el backup manual en `~/Backups/roro-vpn/`.
- `/root/.ssh/authorized_keys` y `/home/opc/.ssh/authorized_keys` usan claves con `command="echo ..."` (sin shell). Correcto.
