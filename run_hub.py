import os
import sys
import subprocess
import time
import re
import socket
import webbrowser

ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
BACKEND_DIR = os.path.join(ROOT_DIR, "backend")
CLOUDFLARED_EXE = os.path.join(ROOT_DIR, "cloudflared.exe")
TUNNEL_LOG = os.path.join(ROOT_DIR, "tunnel.log")

print("=" * 70)
print("  TELEGRAM MEDIA HUB v3.0 - ACCESO CELULAR Y WEB")
print("  Creador: @lukgtz (Luciano Gutierrez)")
print("=" * 70)

# Limpiar procesos viejos
subprocess.run(["taskkill", "/F", "/IM", "cloudflared.exe"], capture_output=True)
subprocess.run(["taskkill", "/F", "/IM", "uvicorn.exe"], capture_output=True)
time.sleep(1)

if os.path.exists(TUNNEL_LOG):
    try:
        os.remove(TUNNEL_LOG)
    except Exception:
        pass

# Iniciar Backend
print("\n[1/2] Iniciando Servidor Backend Turbo...")
api_proc = subprocess.Popen(
    [sys.executable, "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"],
    cwd=BACKEND_DIR,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL
)
time.sleep(2)

# Iniciar Cloudflare
print("[2/2] Conectando Tunel Seguro HTTPS con Cloudflare...")
tunnel_proc = subprocess.Popen(
    [CLOUDFLARED_EXE, "tunnel", "--no-autoupdate", "--logfile", TUNNEL_LOG, "--url", "http://127.0.0.1:8000"],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL
)

tunnel_url = None
start_time = time.time()
print("\nObteniendo enlace para tu celular...")

while time.time() - start_time < 30:
    if os.path.exists(TUNNEL_LOG):
        try:
            with open(TUNNEL_LOG, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
                matches = re.findall(r"https://[a-zA-Z0-9-]+\.trycloudflare\.com", content)
                if matches:
                    tunnel_url = matches[-1]
                    break
        except Exception:
            pass
    time.sleep(1)

os.system("cls" if os.name == "nt" else "clear")
print("=" * 70)
print("  TELEGRAM MEDIA HUB v3.0 - ¡CONECTADO CON EXITO!")
print("  Creador: @lukgtz (Luciano Gutierrez)")
print("=" * 70)
print()
if tunnel_url:
    print("  👉 TU ENLACE PARA EL CELULAR:")
    print()
    print(f"     {tunnel_url}")
    print()
    print("  👉 ENLACE EN TU COMPUTADORA:")
    print("     http://localhost:8000")
    print()
    print("=" * 70)
    print("\n  [Abriendo el enlace en tu navegador automaticamente...]")
    webbrowser.open(tunnel_url)
else:
    print("  👉 ENLACE EN TU COMPUTADORA:")
    print("     http://localhost:8000")
    print("=" * 70)
    webbrowser.open("http://localhost:8000")

print("\n  * NO CIERRES ESTA VENTANA mientras estes usando el bot en tu celular.")
print("  Presiona ENTER o cierra esta ventana cuando quieras apagar todo.\n")

try:
    input("  >> ")
except Exception:
    pass

print("\nApagando servidores...")
tunnel_proc.terminate()
api_proc.terminate()
subprocess.run(["taskkill", "/F", "/IM", "cloudflared.exe"], capture_output=True)
subprocess.run(["taskkill", "/F", "/IM", "uvicorn.exe"], capture_output=True)
print("Listo.")
time.sleep(1)
