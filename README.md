# OCI Cloud Infrastructure & CI/CD Automated Pipeline

Repositorio final de trabajo: infraestructura, hardening y automatización de un servidor Linux en Oracle Cloud Infrastructure (OCI).

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](#licencia)

---

## Resumen del proyecto

Documenta la arquitectura, fortificación y automatización de un servidor Linux alojado en OCI (Instancia VM.Standard.E2.1.Micro, 1 GB RAM), con arquitectura multi-sitio web, VPN privada (WireGuard) y pipeline CI/CD híbrido desde iPadOS/macOS.

**Stack:** OCI · Ubuntu 20.04.6 LTS · Nginx · Fail2Ban · WireGuard · Let's Encrypt · Python 3 · Node.js v20 · React/Vite/Tailwind · Tailscale

---

## Estructura del repositorio

```
OCI-Infrastructure-Portfolio_TFG/
├── README.md
├── .gitignore
├── 01_MEMORIA/
│   ├── Memoria_Técnica_TFG.pdf          # Memoria técnica del TFG
│   └── Fase_7_Hardening_y_Recuperacion.md  # Hardening, Ubuntu Pro, Tailscale
├── 02_CODIGO_Y_CONFIGURACIÓN/
│   ├── nginx/
│   │   ├── danza.conf                   # Vhost de robertmesa.es (con cabeceras de seguridad)
│   │   └── security-headers.conf        # HSTS, X-Content-Type-Options, etc.
│   ├── python/
│   │   ├── setup_servidor.sh            # Replicador interactivo de la instancia
│   │   ├── deploy_server.py             # Despliegue automático en servidor (desde ZIP)
│   │   ├── auto_deploy.py               # Watcher en Mac (watchdog + SFTP + AppleScript)
│   │   ├── despliegue.py                # Despliegue incremental (solo archivos nuevos/modificados)
│   │   ├── explicando_auto_deploy.py.txt
│   │   └── explicando_autodeploy_on_ios.txt
│   ├── ssh/
│   │   ├── sshd_config                 # Config base de SSH (referencia)
│   │   └── NOTA_CONFIG_EFECTIVA.md      # Config efectiva (cloudimg-settings)
│   └── wireguard/
│       └── wg0.conf                     # Config de WireGuard (claves redactadas)
├── 03_EVIDENCIAS_Y_CAPTURAS/            # Capturas de pantalla del proceso
└── docs/
    ├── architecture_diagram.drawio.png
    ├── logs_fail2ban.png
    ├── scipt_python_console.png
    ├── runbook.md                       # Runbook de instalación (Fases 1-4)
    └── TFG_README.md                    # README original del TFG (Fases 1-6)
```

---

## Fases documentadas

| Fase | Descripción | Documento |
|---|---|---|
| 1 | Aprovisionamiento y optimización del SO (swap 2 GB, BBR, journald 200 MB) | [TFG_README.md](docs/TFG_README.md) |
| 2 | Hardening y seguridad perimetral (SSH por clave, Fail2Ban, firewall) | [TFG_README.md](docs/TFG_README.md) |
| 3 | Networking y WireGuard VPN (5 peers) | [TFG_README.md](docs/TFG_README.md) |
| 4 | Arquitectura multi-sitio y rendimiento web (Nginx, Let's Encrypt, gzip) | [TFG_README.md](docs/TFG_README.md) |
| 5 | Pipeline CI/CD híbrido (iPadOS/macOS → SFTP → build → deploy) | [TFG_README.md](docs/TFG_README.md) |
| 6 | Resolución de incidentes (troubleshooting) | [TFG_README.md](docs/TFG_README.md) |
| 7 | Recuperación de acceso, Ubuntu Pro y parcheo seguro (nov 2026) | [Fase_7_Hardening_y_Recuperacion.md](01_MEMORIA/Fase_7_Hardening_y_Recuperacion.md) |

---

## Scripts y archivos de configuración

### Aprovisionamiento
- [`setup_servidor.sh`](02_CODIGO_Y_CONFIGURACIÓN/setup_servidor.sh) — Replicador interactivo de la instancia. Menú single/multi-sitio, WireGuard (5 peers con QR), Nginx, Certbot, Tailscale y Ubuntu Pro opcionales. Incluye hardening SSH, journald, fail2ban, swap, BBR.

### Despliegue CI/CD
- [`deploy_server.py`](02_CODIGO_Y_CONFIGURACIÓN/python/deploy_server.py) — Despliegue automático en servidor desde ZIP. Detecta CV vs Danza por nombre, validación anti zip-slip, `shell=False`.
- [`auto_deploy.py`](02_CODIGO_Y_CONFIGURACIÓN/python/auto_deploy.py) — Watcher en Mac (watchdog + SFTP + AppleScript). Monitoriza descargas de ZIP y despliega automáticamente.
- [`despliegue.py`](02_CODIGO_Y_CONFIGURACIÓN/python/despliegue.py) — Despliegue incremental (solo sube archivos nuevos/modificados por tamaño/fecha).
- [`explicando_auto_deploy.py.txt`](02_CODIGO_Y_CONFIGURACIÓN/python/explicando_auto_deploy.py.txt) — Documentación del flujo de auto_deploy.py.
- [`explicando_autodeploy_on_ios.txt`](02_CODIGO_Y_CONFIGURACIÓN/python/explicando_autodeploy_on_ios.txt) — Documentación del flujo desde iPad (Termius + SFTP).

### Configuración del servidor
- [`nginx/danza.conf`](02_CODIGO_Y_CONFIGURACIÓN/nginx/danza.conf) — Vhost de robertmesa.es con cabeceras de seguridad (HSTS, X-Content-Type-Options, X-Frame-Options, Referrer-Policy) y `server_tokens off`.
- [`nginx/security-headers.conf`](02_CODIGO_Y_CONFIGURACIÓN/nginx/security-headers.conf) — Cabeceras de seguridad reutilizables (include en nginx).
- [`ssh/sshd_config`](02_CODIGO_Y_CONFIGURACIÓN/ssh/sshd_config) — Config base de SSH (referencia, no modificada en Fase 7).
- [`ssh/NOTA_CONFIG_EFECTIVA.md`](02_CODIGO_Y_CONFIGURACIÓN/ssh/NOTA_CONFIG_EFECTIVA.md) — Config efectiva (cloudimg-settings) y valores pendientes de endurecer.
- [`wireguard/wg0.conf`](02_CODIGO_Y_CONFIGURACIÓN/wireguard/wg0.conf) — Config de WireGuard (claves redactadas para publicación).

### Documentación
- [`01_MEMORIA/Memoria_Técnica_TFG.pdf`](01_MEMORIA/Memoria_Técnica_TFG.pdf) — Memoria técnica del TFG.
- [`01_MEMORIA/Fase_7_Hardening_y_Recuperacion.md`](01_MEMORIA/Fase_7_Hardening_y_Recuperacion.md) — Hardening, Ubuntu Pro, Tailscale, parcheo seguro.
- [`docs/runbook.md`](docs/runbook.md) — Runbook de instalación paso a paso (Fases 1-4).
- [`docs/TFG_README.md`](docs/TFG_README.md) — README original del TFG (Fases 1-6).
- [`docs/architecture_diagram.drawio.png`](docs/architecture_diagram.drawio.png) — Diagrama de arquitectura.

### Evidencias
- [`03_EVIDENCIAS_Y_CAPTURAS/`](03_EVIDENCIAS_Y_CAPTURAS/) — 10 capturas de pantalla del proceso (SSH, WireGuard, Fail2Ban, Nginx, monitorización).

---

## Notas de seguridad

- El servidor real está en `<SERVER_IP>` (Oracle Cloud, Frankfurt). Tailscale IP: `<TAILSCALE_IP>`.
- OpenSSH y kernel se retuvieron (`apt-mark hold`) para mantener la estabilidad durante el parcheo; se actualizarán en una ventana de mantenimiento posterior.
- `ufw` está inactivo en el servidor real; el filtrado lo hace `iptables-persistent` + `fail2ban` + `PostUp` de WireGuard.
- Las claves privadas, IPs reales, hostnames de Tailscale y huellas SSH se han redactado en este repositorio público. Los valores reales están en el servidor y en el backup privado.
- `deploy_server.py` usa `shell=False` y validación anti zip-slip. `auto_deploy.py` usa `shell=True` con `npm run build` (revisar si se usa en producción).

---

## Prerrequisitos para replicar

- Instancia Ubuntu 20.04 LTS en Oracle Cloud (o cualquier proveedor).
- Acceso SSH con clave pública.
- Dominio apuntando a la IP del servidor (para Certbot).
- Node.js v20, Python 3, Nginx, WireGuard, Fail2Ban, Certbot.

Ejecutar [`setup_servidor.sh`](02_CODIGO_Y_CONFIGURACIÓN/setup_servidor.sh) como usuario normal (usa `sudo` internamente). El script es interactivo: pregunta tipo de despliegue, dominio, email, etc.

---

## Licencia

MIT License — ver [LICENSE](LICENSE) (pendiente de añadir).

---

> **Nota:** Este repositorio es el resultado de un Trabajo Fin de Grado (TFG) de ASIR. La infraestructura real está en producción y los valores sensibles han sido redactados.