import os
import shutil
import zipfile
import subprocess
import time
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
import paramiko

# --- CONFIGURACIÓN BASE DE RUTAS (MAC) ---
BASE_DIR = "/Users/roro/vs-code"

# Nombres de archivos válidos
ZIP_ARTISTA = "robert-mesa-|-artista.zip"
ZIP_CV = "robert-mesa-cv.zip"

# --- CONFIGURACIÓN SFTP GENERAL ---
SFTP_HOST = "<SERVER_IP>"
SFTP_PORT = 22
SFTP_USER = "ubuntu"
SSH_KEY_PATH = "/Users/roro/Downloads/ssh-key-2026-02-23.key"

# Destinos en el servidor según el proyecto
REMOTE_DIR_DANZA = "/var/www/danza"
REMOTE_DIR_ASIR = "/var/www/html"


def traer_terminal_al_frente():
    """Trae al frente iTerm si está abierto (o lo abre), evitando usar la Terminal nativa de macOS"""
    script = """
    if application "iTerm" is running then
        tell application "iTerm"
            activate
        end tell
    else
        tell application "iTerm"
            activate
        end tell
    end if
    """
    subprocess.run(["osascript", "-e", script])


def procesar_archivo(zip_name):
    zip_path = os.path.join(BASE_DIR, zip_name)
    if not os.path.exists(zip_path):
        return

    # Configuración dinámica de variables según el archivo detectado
    if zip_name == ZIP_ARTISTA:
        tipo_proyecto = "ARTISTA"
        extraction_dir = os.path.join(BASE_DIR, "robert-mesa-|-artista")
        server_dir = os.path.join(BASE_DIR, "robert-mesa-|-artista para servidor")
        remote_dir_target = REMOTE_DIR_DANZA
    elif zip_name == ZIP_CV:
        tipo_proyecto = "ASIRWEB (CV)"
        extraction_dir = os.path.join(BASE_DIR, "robert-mesa-cv-temp")
        server_dir = os.path.join(BASE_DIR, "ASIRWEB")
        remote_dir_target = REMOTE_DIR_ASIR
    else:
        return

    print(f"\n📦 ¡Archivo detectado! Iniciando proceso para: {tipo_proyecto}...")
    traer_terminal_al_frente()
    
    try:
        # 1. Asegurar y extraer el ZIP directamente dentro de la carpeta temporal correspondiente
        print(f"-> Preparando directorio temporal y descomprimiendo {zip_name}...")
        if os.path.exists(extraction_dir):
            shutil.rmtree(extraction_dir)
        os.makedirs(extraction_dir)
        
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            zip_ref.extractall(extraction_dir)
        
        # Corrección por si el zip venía con una carpeta interna redundante de macOS (__MACOSX)
        macosx_folder = os.path.join(extraction_dir, "__MACOSX")
        if os.path.exists(macosx_folder):
            shutil.rmtree(macosx_folder)
            
        # 2. Mover archivos al directorio de producción del servidor local
        print(f"-> Moviendo archivos de {extraction_dir} a {server_dir}...")
        if not os.path.exists(server_dir):
            os.makedirs(server_dir)
            
        for item in os.listdir(extraction_dir):
            s = os.path.join(extraction_dir, item)
            d = os.path.join(server_dir, item)
            if os.path.isdir(s):
                if os.path.exists(d):
                    shutil.rmtree(d)
                shutil.copytree(s, d)
            else:
                shutil.copy2(s, d)

        # 3. Limpieza local inmediata de residuos temporales
        print("-> Limpiando archivos temporales...")
        if os.path.exists(zip_path):
            os.remove(zip_path)
        if os.path.exists(extraction_dir):
            shutil.rmtree(extraction_dir)

        # 4. Ejecutar npm run build en la carpeta del servidor local del Mac
        print(f"-> Ejecutando 'npm run build' en {server_dir}...")
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
        print("✓ Build completado con éxito locales.")

        # 5. Localizar la carpeta 'dist' generada en tu Mac
        dist_dir = os.path.join(server_dir, "dist")
        if not os.path.exists(dist_dir):
            print("❌ No se encontró la carpeta 'dist' tras el build.")
            return

        # 6. Subir la carpeta 'dist' por SFTP al destino remoto correspondiente
        print(f"-> Conectando al servidor SFTP para desplegar en {remote_dir_target}...")
        subir_sftp(dist_dir, remote_dir_target)
        print(f"🎉 ¡Todo el proceso de {tipo_proyecto} se completó con éxito!")

    except Exception as e:
        print(f"❌ Ocurrió un error durante la ejecución: {e}")


def subir_sftp(local_folder, remote_dir_target):
    try:
        key = paramiko.RSAKey.from_private_key_file(SSH_KEY_PATH)
    except Exception:
        key = paramiko.Ed25519Key.from_private_key_file(SSH_KEY_PATH)

    transport = paramiko.Transport((SFTP_HOST, SFTP_PORT))
    transport.connect(username=SFTP_USER, pkey=key)
    sftp = paramiko.SFTPClient.from_transport(transport)

    print("-> Subiendo archivos al servidor SFTP...")
    
    for root, dirs, files in os.walk(local_folder):
        for file in files:
            local_path = os.path.join(root, file)
            relative_path = os.path.relpath(local_path, local_folder)
            remote_path = os.path.join(remote_dir_target, relative_path).replace("\\", "/")
            
            # Crear directorios remotos recursivos si no existen
            remote_dir_path = os.path.dirname(remote_path)
            crear_directorio_remoto_recursivo(sftp, remote_dir_path)
            
            print(f"Subiendo: {relative_path} -> {remote_path}")
            sftp.put(local_path, remote_path)

    sftp.close()
    transport.close()


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


# --- WATCHER ADAPTADO PARA MÚLTIPLES ARCHIVOS ---
class ZipHandler(FileSystemEventHandler):
    def __init__(self):
        super().__init__()
        self.procesando = False

    def evaluar_evento(self, filepath):
        filename = os.path.basename(filepath)
        
        # Filtro inteligente: solo reacciona si coincide exactamente con uno de los dos proyectos
        if filename in [ZIP_ARTISTA, ZIP_CV]:
            if self.procesando:
                return
            self.procesando = True
            
            zip_full_path = os.path.join(BASE_DIR, filename)
            if os.path.exists(zip_full_path):
                print(f"\n📦 ¡Se detectó una nueva descarga de: {filename}!")
                time.sleep(2)  # Pausa de seguridad para asegurar escritura física completa del ZIP
                
                procesar_archivo(filename)
                
                print("\n👀 Volviendo al estado de espera... Listo para el próximo archivo.")
            
            time.sleep(2)
            self.procesando = False

    def on_created(self, event):
        if not event.is_directory:
            self.evaluar_evento(event.src_path)

    def on_moved(self, event):
        if not event.is_directory:
            self.evaluar_evento(event.dest_path)

    def on_modified(self, event):
        if not event.is_directory:
            self.evaluar_evento(event.src_path)


if __name__ == "__main__":
    print(f"👀 Vigilando la carpeta: {BASE_DIR}")
    print(f"   -> Esperando a: '{ZIP_ARTISTA}' o '{ZIP_CV}'...")
    event_handler = ZipHandler()
    observer = Observer()
    observer.schedule(event_handler, path=BASE_DIR, recursive=False)
    observer.start()

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n🛑 Deteniendo el watcher...")
        observer.stop()
    observer.join()