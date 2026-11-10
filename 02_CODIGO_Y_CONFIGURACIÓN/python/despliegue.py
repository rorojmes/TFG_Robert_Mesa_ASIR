import os
import subprocess
import paramiko

# --- CONFIGURACIÓN BASE DE RUTAS (MAC) ---
BASE_DIR = "/Users/roro/vs-code"

# Carpetas locales de desarrollo
DIR_ARTISTA = os.path.join(BASE_DIR, "robert-mesa-|-artista para servidor")
DIR_CV = os.path.join(BASE_DIR, "ASIRWEB")

# --- CONFIGURACIÓN SFTP / SERVIDOR REMOTO ---
SFTP_HOST = "<SERVER_IP>"
SFTP_PORT = 22
SFTP_USER = "ubuntu"
SSH_KEY_PATH = "/Users/roro/Downloads/ssh-key-2026-02-23.key"

# Destinos en el servidor según el proyecto
REMOTE_DIR_DANZA = "/var/www/danza"
REMOTE_DIR_ASIR = "/var/www/html"


def procesar_proyecto(server_dir, tipo_proyecto, remote_dir_target):
    """Ejecuta el build local y sube únicamente los archivos nuevos o modificados."""
    if not os.path.exists(server_dir):
        print(f"⚠️ Omite {tipo_proyecto}: No se encontró la carpeta en {server_dir}")
        return

    print(f"\n🚀 Procesando proyecto: {tipo_proyecto}...")
    print(f"-> Ejecutando 'npm run build' en {server_dir}...")

    # 1. Ejecutar npm run build en la carpeta del proyecto
    result = subprocess.run(
        "npm run build",
        shell=True,
        cwd=server_dir,
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        print(f"❌ Error en npm run build para {tipo_proyecto}:\n{result.stderr}")
        return
    print("✓ Build completado con éxito.")

    # 2. Localizar la carpeta 'dist' generada
    dist_dir = os.path.join(server_dir, "dist")
    if not os.path.exists(dist_dir):
        print("❌ No se encontró la carpeta 'dist' tras el build.")
        return

    # 3. Sincronizar diferencialmente los archivos hacia el servidor
    print(f"-> Verificando y subiendo archivos a {remote_dir_target}...")
    subir_sftp_inteligente(dist_dir, remote_dir_target)


def subir_sftp_inteligente(local_folder, remote_dir_target):
    """
    Compara la carpeta 'dist' local con el servidor y sube
    ÚNICAMENTE los archivos que sean nuevos o tengan un tamaño/fecha diferente.
    """
    try:
        key = paramiko.RSAKey.from_private_key_file(SSH_KEY_PATH)
    except Exception:
        key = paramiko.Ed25519Key.from_private_key_file(SSH_KEY_PATH)

    transport = paramiko.Transport((SFTP_HOST, SFTP_PORT))
    transport.connect(username=SFTP_USER, pkey=key)
    sftp = paramiko.SFTPClient.from_transport(transport)

    archivos_subidos = 0

    for root, dirs, files in os.walk(local_folder):
        for file in files:
            local_path = os.path.join(root, file)
            relative_path = os.path.relpath(local_path, local_folder)
            remote_path = os.path.join(remote_dir_target, relative_path).replace("\\", "/")

            remote_dir_path = os.path.dirname(remote_path)
            crear_directorio_remoto_recursivo(sftp, remote_dir_path)

            # Comprobar estado del archivo local vs remoto
            local_stat = os.stat(local_path)
            necesita_subida = True

            try:
                remote_stat = sftp.stat(remote_path)
                # Si coincide el tamaño y la marca de tiempo remota es igual o más reciente, se omite
                if remote_stat.st_size == local_stat.st_size and remote_stat.st_mtime >= local_stat.st_mtime:
                    necesita_subida = False
            except IOError:
                # El archivo no existe en el servidor -> requiere subida
                necesita_subida = True

            if necesita_subida:
                print(f"  ⬆️ Subiendo cambios: {relative_path}")
                sftp.put(local_path, remote_path)
                archivos_subidos += 1

    sftp.close()
    transport.close()

    if archivos_subidos == 0:
        print("  ✓ Sin cambios pendientes. El servidor ya está actualizado al 100%.")
    else:
        print(f"  ✓ {archivos_subidos} archivo(s) desplegado(s) con éxito.")


def crear_directorio_remoto_recursivo(sftp, remote_dir):
    dirs = []
    while remote_dir and remote_dir != "/":
        dirs.append(remote_dir)
        remote_dir = os.path.dirname(remote_dir)

    while dirs:
        d = dirs.pop()
        try:
            sftp.stat(d)
        except IOError:
            sftp.mkdir(d)


if __name__ == "__main__":
    print("=== INICIANDO DESPLIEGUE MANUAL BAJO DEMANDA ===")

    # 1. Procesar proyecto ARTISTA
    procesar_proyecto(
        server_dir=DIR_ARTISTA,
        tipo_proyecto="ARTISTA",
        remote_dir_target=REMOTE_DIR_DANZA
    )

    # 2. Procesar proyecto ASIRWEB (CV)
    procesar_proyecto(
        server_dir=DIR_CV,
        tipo_proyecto="ASIRWEB (CV)",
        remote_dir_target=REMOTE_DIR_ASIR
    )

    print("\n🎉 ¡Proceso finalizado con éxito! Saliendo del programa.")