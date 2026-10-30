# Servidor relay (juego en línea)

Los jugadores se conectan por WebSocket a este servidor; el relay arma salas con un
código de 5 letras y reenvía los mensajes. No guarda nada ni conoce las reglas: el
anfitrión de la sala (quien la crea) valida las jugadas.

## Probar en este PC

```
godot --headless --path . -s res://server/relay_server.gd -- --port=8910
```

y en `data/online.json` usar `"server_url": "ws://127.0.0.1:8910"` (o lanzar el juego con
`-- --relay=ws://127.0.0.1:8910`).

## Publicado en Render (gratis)

El relay se despliega desde un repositorio de GitHub que contiene solo esta carpeta
(`git subtree split --prefix server`), con el `Dockerfile` y `render.yaml` de aquí.

- Plan gratuito: se apaga tras 15 minutos sin tráfico y tarda ~1 minuto en despertar.
  El juego lo despierta al abrir "Jugar en línea" y reintenta la conexión mientras tanto.
  Durante una partida los mensajes lo mantienen despierto.
- Para actualizarlo después de cambiar `relay_server.gd`:

```
git subtree split --prefix server -b relay
git push relay relay:main
```
