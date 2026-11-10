# Nota: configuración SSH efectiva en el servidor

El archivo `sshd_config` de esta carpeta es la copia de referencia del `/etc/ssh/sshd_config` base.
La configuración efectiva se complementa con `/etc/ssh/sshd_config.d/60-cloudimg-settings.conf`, que contiene los valores realmente aplicados:

- `PasswordAuthentication no`
- `KbdInteractiveAuthentication no`
- `PermitEmptyPasswords no`
- `PermitRootLogin without-password`
- `X11Forwarding yes`
- `ChallengeResponseAuthentication no`
- `UsePAM yes`

Valores destacados:
- No hay `AllowUsers` (pendiente de añadir en la fase de endurecimiento).
- `X11Forwarding yes` (pendiente de desactivar).
- `PermitRootLogin without-password` (pendiente de cambiar a `no`).

La clave pública del servidor (host key Ed25519) es:
`<HOST_KEY_FINGERPRINT>`

Durante la Fase 7 NO se modificó `sshd_config` ni el puerto 22.
La vía de rescate es Tailscale SSH (`ssh roro-vpn-ts`), que no depende de `sshd`.