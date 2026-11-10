# Fase 7 — Recuperación de acceso, Ubuntu Pro y parcheo seguro

## 1. Contexto y restricción principal

- Servidor: Oracle Cloud, `roro-vpn`, Ubuntu 20.04.6 LTS, kernel `5.15.0-1081-oracle`, uptime 249 días, 952 MB RAM, 45 GB disco.
- Ubuntu 20.04 standard support terminó el 31/05/2025. `pro security-status` reportaba 216 actualizaciones pendientes de `esm-infra` + 19 de `esm-apps`, incluyendo kernel, OpenSSH, OpenSSL, sudo, glibc, systemd, nginx.
- El servidor se gestiona de forma remota; durante este proceso no se utilizó consola serie ni reinicio.
- **Restricción adoptada:** congelar SSH, firewall y reinicio hasta verificar Tailscale como vía de acceso independiente. No se tocó `sshd_config`, ni el puerto 22, ni UFW/iptables.

## 2. Red de seguridad: Tailscale + Tailscale SSH

### Instalación
```bash
curl -fsSL https://tailscale.com/install.sh -o /tmp/tailscale-install.sh
sudo sh /tmp/tailscale-install.sh
sudo systemctl enable --now tailscaled
sudo tailscale up --accept-dns=false
```
- `--accept-dns=false`: Tailscale NO modifica el DNS del servidor.
- IP en el tailnet: `<TAILSCALE_IP>`. MagicDNS: `<TAILSCALE_HOSTNAME>`.

### Activación de Tailscale SSH (puerta independiente de sshd)
```bash
sudo tailscale up --ssh --accept-dns=false
```
- La conexión la atiende `tailscaled`, no `sshd`. Verificado: banner SSH `SSH-2.0-Tailscale` (frente a `OpenSSH_8.2p1 Ubuntu`).
- Probado desde Mac e iPhone (con Wi-Fi apagado, por datos móviles).
- Alias SSH añadido en `~/.ssh/config`: `ssh roro-vpn-ts`.

### Endurecimiento de la cuenta Tailscale
- MFA mediante Apple ID (2FA).
- Device approval activado para dispositivos nuevos.
- Expiración de clave del servidor desactivada (caducaba 05/05/2027).
- ACL recomendada para emergencias: `"action": "accept"` desde `autogroup:member` a `autogroup:self` como `ubuntu`.

## 3. Backups y retención

### Backup completo
```bash
sudo tar czf /tmp/roro-vpn-2026-11-06.tar.gz /var/www /etc/wireguard /etc/nginx /etc/letsencrypt /etc/ssh /etc/iptables /etc/fail2ban ...
```
- 628 MB, SHA256 `0f45c90866787f429950c530ba71e8c6608883924e3fafeae114615857c0b3bb`.
- Contiene claves privadas (TLS y WireGuard). Guardado en Mac con FileVault y permisos 600.

### Copia de recuperación en el servidor
`/root/recovery/2026-11-06/` con copias de `ssh`, `pam.d`, `sudoers`, `nginx`, `fail2ban`, `wireguard`, `iptables`, `ip6tables` y un `README.md` con runbook.

### Clave de emergencia
- Nueva clave Ed25519 (`~/.ssh/roro-vpn-emergency`) añadida a `authorized_keys` y probada.
- Huella: `<HOST_KEY_FINGERPRINT>`.

### Retención de paquetes
```bash
sudo apt-mark hold openssh-server openssh-client openssh-sftp-server \
  linux-oracle linux-image-oracle linux-headers-oracle \
  linux-image-5.15.0-1081-oracle linux-headers-5.15.0-1081-oracle \
  linux-modules-5.15.0-1081-oracle linux-modules-extra-5.15.0-1081-oracle \
  linux-oracle-5.15-headers-5.15.0-1081
```

## 4. Ubuntu Pro y parcheo seguro

```bash
sudo pro attach --no-auto-enable   # ejecutado por el usuario
sudo pro enable esm-infra esm-apps
sudo apt-get update
sudo apt-get upgrade -y --with-new-pkgs \
  -o Dpkg::Options::=--force-confdef \
  -o Dpkg::Options::=--force-confold
```
- `esm-infra` y `esm-apps` habilitados hasta 2030.
- ~200 paquetes actualizados (nginx, fail2ban, OpenSSL, systemd, sudo, glibc, libpam, curl, git, etc.).
- OpenSSH y kernel **no** se tocaron (holds).
- `sshd` con el mismo PID, puerto 22 activo, `sshd -t` OK, nginx/fail2ban/tailscaled activos.

## 5. Hardening de bajo riesgo

### WireGuard (permisos de claves)
```bash
sudo chmod 600 /etc/wireguard/wg0.conf /etc/wireguard/params
sudo mv /home/ubuntu/wg0-client-*.conf /root/wireguard-clients/
sudo chmod 700 /root/wireguard-clients
sudo chmod 600 /root/wireguard-clients/*
```
- `params` contenía `SERVER_PRIV_KEY` en claro con modo 644.
- Los 5 `.conf` de clientes eran world-readable (644 en directorio 755).
- WireGuard sigue activo.

### nginx (cabeceras y versionado)
- `server_tokens off;` (global + vhost).
- Cabeceras: HSTS (`max-age=31536000; includeSubDomains`), `X-Content-Type-Options: nosniff`, `X-Frame-Options: SAMEORIGIN`, `Referrer-Policy: strict-origin-when-cross-origin`.
- TLS limitado a 1.2/1.3.
- Verificado con `curl -I https://robertmesa.es`.

### fail2ban
```ini
[sshd]
enabled = true
port = 22
maxretry = 3
findtime = 10m
bantime = 48h
ignoreip = 127.0.0.1/8 ::1 100.64.0.0/10 <OWNER_PUBLIC_IP>
```
- `bantime` bajado de 744 h (31 días) a 48 h.
- `ignoreip` incluye tailnet para no banear conexiones Tailscale.

### Journal
```bash
sudo journalctl --vacuum-size=200M
sudo systemctl restart systemd-journald
```
- 840 MB → 192 MB.

### Otros
- `motd-news` reparado (permiso de ejecución).
- apt cache limpiado (`apt-get clean`).
- Disco: 7.8 G usados de 45 G.

## 6. Pendiente (bloqueado)

| Tarea | Bloqueo |
|---|---|
| Actualizar OpenSSH + reload | Ventana de mantenimiento controlada |
| Instalar kernel nuevo + reiniciar | Ventana de mantenimiento controlada |
| Endurecer `sshd_config` (root login, X11, AllowUsers) | Sin red de seguridad estable |
| Firewall (UFW/iptables, ip6tables default DROP) | Ventana de mantenimiento controlada |
| Cerrar puerto 22 público | Último paso |

## 7. Notas de seguridad adicionales

- `deploy_server.py` ejecuta `npm install && npm run build` con `shell=True` como `ubuntu`, que tiene `NOPASSWD:ALL`. Riesgo de inyección si se despliega un ZIP malicioso.
- No hay backups automáticos (sin restic/borg/duplicity).
- `/root/.ssh/authorized_keys` y `/home/opc/.ssh/authorized_keys` usan claves con `command="echo ..."` (sin shell). Correcto.

## 8. Comandos de verificación final

```bash
ps -o pid,lstart,cmd -p $(pgrep -o sshd)   # PID 1132307 (sin cambios)
ss -ltn | grep ':22 '                       # escuchando IPv4 + IPv6
systemctl is-active ssh nginx fail2ban tailscaled systemd-journald
sudo sshd -t                                # OK
apt-mark showhold | wc -l                   # 11
pro status | grep -E 'esm-infra|esm-apps'   # enabled hasta 2030
sudo wg show | head -3                      # activo
journalctl --disk-usage                      # ~192 MB
tailscale ip -4                             # <TAILSCALE_IP>
ssh -v roro-vpn-ts true 2>&1 | grep "remote software version"  # Tailscale
```