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

print("=" * 65)
print("  TELEGRAM MEDIA HUB v3.0 - SERVIDOR LOCAL & ACCESO CELULAR")
print("  Creador: @lukgtz (Luciano Gutierrez)")
print("=" * 65)

print("\n[1/3] Limpiando túneles anteriores...")
subprocess.run(["taskkill", "/F", "/IM", "cloudflared.exe"], capture_output=True, text=True)
if os.path.exists(TUNNEL_LOG):
    try:
        os.remove(TUNNEL_LOG)
    except Exception:
        pass

# Verificar si el backend ya está corriendo en el puerto 8000
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
backend_running = False
try:
    s.connect(("127.0.0.1", 8000))
    backend_running = True
    s.close()
except Exception:
    backend_running = False

api_proc = None
if not backend_running:
    print("[2/3] Iniciando Servidor FastAPI Turbo...")
    api_proc = subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"],
        cwd=BACKEND_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    time.sleep(2)
else:
    print("[2/3] Servidor FastAPI Turbo ya está activo en el puerto 8000.")

print("[3/3] Conectando con Cloudflare Tunnel para tu celular...")
tunnel_proc = subprocess.Popen(
    [CLOUDFLARED_EXE, "tunnel", "--no-autoupdate", "--logfile", TUNNEL_LOG, "--url", "http://127.0.0.1:8000"],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL
)

tunnel_url = None
start_time = time.time()

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

print("\n" + "=" * 65)
if tunnel_url:
    print("  ¡TODO LISTO Y FUNCIONANDO EN TU CELULAR Y COMPUTADORA!")
    print(f"\n  👉 TU ENLACE PARA EL CELULAR:\n     {tunnel_url}\n")
    print(f"  👉 ENLACE EN TU COMPUTADORA:\n     http://localhost:8000\n")
    print("=" * 65)
    print("\n  [Abriendo el enlace en tu navegador automáticamente...]")
    webbrowser.open(tunnel_url)
else:
    print("  Servidor iniciado localmente:")
    print("  👉 http://localhost:8000")
    print("=" * 65)
    webbrowser.open("http://localhost:8000")

print("\n⚠️ NO CIERRES ESTA VENTANA mientras estés usando el bot.")
print("Para apagar el bot cuando termines, simplemente cierra esta ventana.\n")

try:
    while True:
        time.sleep(1)
        if tunnel_proc.poll() is not None:
            break
except KeyboardInterrupt:
    pass
finally:
    print("\nApagando túnel...")
    tunnel_proc.terminate()
    if api_proc:
        api_proc.terminate()
