import json
import asyncio
from typing import Dict, List, Any
from fastapi import WebSocket

class ConnectionManager:
    """Administra conexiones activas de WebSockets por usuario para enviar progreso en vivo."""
    def __init__(self):
        self.active_connections: Dict[int, List[WebSocket]] = {}

    async def connect(self, user_id: int, websocket: WebSocket):
        await websocket.accept()
        if user_id not in self.active_connections:
            self.active_connections[user_id] = []
        self.active_connections[user_id].append(websocket)

    def disconnect(self, user_id: int, websocket: WebSocket):
        if user_id in self.active_connections:
            if websocket in self.active_connections[user_id]:
                self.active_connections[user_id].remove(websocket)
            if not self.active_connections[user_id]:
                del self.active_connections[user_id]

    async def broadcast_user_job_progress(self, user_id: int, job_data: Dict[str, Any]):
        """Envía el estado de la tarea en tiempo real a todos los navegadores abiertos del usuario."""
        if user_id in self.active_connections:
            message = json.dumps(job_data)
            disconnected = []
            for connection in self.active_connections[user_id]:
                try:
                    await connection.send_text(message)
                except Exception:
                    disconnected.append(connection)
            for conn in disconnected:
                self.disconnect(user_id, conn)

manager = ConnectionManager()
