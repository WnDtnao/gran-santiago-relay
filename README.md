# Servidor relay (juego en línea)

Los jugadores se conectan por WebSocket a este servidor; el relay arma salas con un
código de 5 letras y reenvía los mensajes. No guarda nada ni conoce las reglas: el
anfitrión de la sala (quien la crea) valida las jugadas.

## Probar en este PC

```
godot --headless --path . -s res://server/relay_server.gd -- --port=8910
```

`data/online.json` apunta por defecto a `ws://127.0.0.1:8910`.

## Publicarlo en Internet

Cualquier hosting que ejecute un contenedor Docker con WebSockets sirve (Render,
Fly.io, Railway, un VPS...). El servidor toma el puerto de la variable `PORT`.

1. Crear el servicio desde esta carpeta (`server/`) usando el `Dockerfile`.
2. El hosting entrega una dirección HTTPS, por ejemplo `https://gran-santiago-relay.onrender.com`.
3. En `data/online.json` poner `"server_url": "wss://gran-santiago-relay.onrender.com"`
   (`wss://` porque el hosting usa TLS; así también funciona desde la versión Web).

Para probar otro servidor sin tocar el archivo: `godot --path . -- --relay=wss://...`.
