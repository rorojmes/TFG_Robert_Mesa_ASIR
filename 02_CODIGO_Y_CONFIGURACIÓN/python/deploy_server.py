#!/usr/bin/env python3
import os
import shutil
import zipfile
import subprocess
import glob

# --- CONFIGURACIÓN DE RUTAS EN EL SERVIDOR ---
PROYECTO_DIR = "/home/ubuntu" 
EXTRACTION_DIR = os.path.join(PROYECTO_DIR, "temp_robert_mesa")

# Rutas de producción en el servidor web
REMOTE_DIR_DANZA = "/var/www/danza"
REMOTE_DIR_ASIR = "/var/www/html"

def procesar_despliegue():
    # Busca cualquier ZIP coincidente en /home/ubuntu
    archivos_zip = glob.glob(os.path.join(PROYECTO_DIR, "*artista*.zip")) + glob.glob(os.path.join(PROYECTO_DIR, "*robert*.zip"))
    archivos_zip = list(set(archivos_zip)) # Elimina duplicados

    if not archivos_zip:
        print(f"❌ Error: No se encontró ningún archivo ZIP coincidente en {PROYECTO_DIR}")
        return

    # Tomamos el primer match
    zip_path = archivos_zip[0]
    zip_name = os.path.basename(zip_path).lower()
    print(f"📦 ¡Archivo detectado en {PROYECTO_DIR}!: {zip_name}. Iniciando despliegue...")

    # Identificar destino dinámicamente según el nombre del archivo
    if "cv" in zip_name:
        target_dir = REMOTE_DIR_ASIR
        tipo_proyecto = "ASIRWEB (CV)"
    else:
        target_dir = REMOTE_DIR_DANZA
        tipo_proyecto = "ARTISTA (Danza)"

    print(f"🎯 Tipo de proyecto detectado: {tipo_proyecto} -> Destino: {target_dir}")

    deploy_ok = False
    try:
        # Limpieza de intentos previos
        if os.path.exists(EXTRACTION_DIR):
            shutil.rmtree(EXTRACTION_DIR)
        os.makedirs(EXTRACTION_DIR)

        print("-> Descomprimiendo archivo...")
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            for _m in zip_ref.namelist():
                _dest = os.path.join(EXTRACTION_DIR, _m)
                if not os.path.abspath(_dest).startswith(os.path.abspath(EXTRACTION_DIR) + os.sep):
                    print("❌ ZIP inseguro: contiene rutas fuera del directorio de extracción.")
                    return
            zip_ref.extractall(EXTRACTION_DIR)

        # Limpiar basura de metadatos de macOS si existiera
        macosx_folder = os.path.join(EXTRACTION_DIR, "__MACOSX")
        if os.path.exists(macosx_folder):
            shutil.rmtree(macosx_folder)

        print("-> Instalando dependencias y ejecutando 'npm run build'...")
        result = subprocess.run(
            ["npm", "install"],
            cwd=EXTRACTION_DIR,
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            result = subprocess.run(
                ["npm", "run", "build"],
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

        # Mover los archivos resultantes al directorio web final
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