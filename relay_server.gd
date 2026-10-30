extends SceneTree
## Servidor relay del juego en línea. No conoce las reglas: agrupa a los jugadores
## en salas con un código y reenvía los mensajes entre ellos. El anfitrión de cada
## sala (quien la creó, id 1) es el que valida y aplica las jugadas (OnlineSession).
##
## Local:   godot --headless --path . -s res://server/relay_server.gd -- --port=8910
## Hosting: ver server/README.md (toma el puerto de la variable de entorno PORT).
##
## Mensajes (texto JSON) del cliente al relay:
##   {"t":"create","v":1}                -> {"t":"created","room":"ABCDE","id":1}
##   {"t":"join","room":"ABCDE","v":1}   -> {"t":"joined","room":"ABCDE","id":N} o {"t":"error","reason":...}
##   {"t":"msg","to":N,"data":{...}}     -> el destinatario recibe {"t":"msg","from":id,"data":{...}} (to 0 = todos los demás)
##   {"t":"lock"} / {"t":"kick","id":N}  (solo el anfitrión: cerrar la sala a nuevos / expulsar)
## Avisos del relay: {"t":"peer_joined","id":N} y {"t":"peer_left","id":N} al anfitrión; {"t":"host_left"} a todos.

const RELAY_VERSION := 1
const DEFAULT_PORT := 8910
const MAX_MEMBERS := 6
const MAX_ROOMS := 2000
const MAX_MESSAGE := 512 * 1024
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 5
## Mensajes por segundo permitidos por conexión.
const MAX_RATE := 120.0

var _tcp := TCPServer.new()
## id de conexión -> {ws, room, id, budget}
var _conns: Dictionary = {}
## código -> {members: {id: id de conexión}, next_id, locked}
var _rooms: Dictionary = {}
var _next_conn := 1
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	Engine.max_fps = 60
	_rng.randomize()
	var port := DEFAULT_PORT
	if OS.get_environment("PORT") != "":
		port = int(OS.get_environment("PORT"))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
	var error := _tcp.listen(port)
	if error != OK:
		printerr("No se pudo abrir el puerto %d: %s" % [port, error_string(error)])
		quit(1)
		return
	print("Relay de Gran Santiago escuchando en el puerto %d" % port)


func _process(delta: float) -> bool:
	while _tcp.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = MAX_MESSAGE
		ws.outbound_buffer_size = MAX_MESSAGE * 4
		ws.accept_stream(_tcp.take_connection())
		_conns[_next_conn] = {"ws": ws, "room": "", "id": 0, "budget": MAX_RATE}
		_next_conn += 1
	for cid in _conns.keys():
		if not _conns.has(cid):
			continue
		var c: Dictionary = _conns[cid]
		var ws: WebSocketPeer = c.ws
		ws.poll()
		c.budget = minf(MAX_RATE, float(c.budget) + MAX_RATE * delta)
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				while ws.get_available_packet_count() > 0:
					c.budget -= 1.0
					if c.budget < 0.0:
						ws.close(1008, "rate")
						break
					var msg: Variant = JSON.parse_string(ws.get_packet().get_string_from_utf8())
					if msg is Dictionary:
						_handle(cid, msg)
			WebSocketPeer.STATE_CLOSED:
				_drop(cid)
	return false


func _handle(cid: int, m: Dictionary) -> void:
	var c: Dictionary = _conns[cid]
	var room: Dictionary = _rooms.get(c.room, {})
	match String(m.get("t", "")):
		"create":
			if c.room != "":
				return
			if int(m.get("v", 0)) != RELAY_VERSION:
				_reply(cid, {"t": "error", "reason": "NET_VERSION_MISMATCH"})
			elif _rooms.size() >= MAX_ROOMS:
				_reply(cid, {"t": "error", "reason": "NET_SERVER_FULL"})
			else:
				var code := _new_code()
				_rooms[code] = {"members": {1: cid}, "next_id": 2, "locked": false}
				c.room = code
				c.id = 1
				_reply(cid, {"t": "created", "room": code, "id": 1})
		"join":
			if c.room != "":
				return
			var code := String(m.get("room", "")).strip_edges().to_upper()
			if int(m.get("v", 0)) != RELAY_VERSION:
				_reply(cid, {"t": "error", "reason": "NET_VERSION_MISMATCH"})
			elif not _rooms.has(code):
				_reply(cid, {"t": "error", "reason": "NET_ROOM_NOT_FOUND"})
			elif _rooms[code].locked:
				_reply(cid, {"t": "error", "reason": "NET_GAME_STARTED"})
			elif _rooms[code].members.size() >= MAX_MEMBERS:
				_reply(cid, {"t": "error", "reason": "NET_ROOM_FULL"})
			else:
				var target: Dictionary = _rooms[code]
				var id := int(target.next_id)
				target.next_id = id + 1
				target.members[id] = cid
				c.room = code
				c.id = id
				_reply(cid, {"t": "joined", "room": code, "id": id})
				_send_to(code, 1, {"t": "peer_joined", "id": id})
		"msg":
			if room.is_empty():
				return
			var out := {"t": "msg", "from": c.id, "data": m.get("data", {})}
			var to := int(m.get("to", 0))
			if to == 0:
				for id in room.members:
					if id != c.id:
						_send_to(c.room, id, out)
			else:
				_send_to(c.room, to, out)
		"lock":
			if not room.is_empty() and c.id == 1:
				room.locked = true
		"kick":
			if not room.is_empty() and c.id == 1:
				var target_cid: Variant = room.members.get(int(m.get("id", 0)))
				if target_cid != null and _conns.has(target_cid):
					_conns[target_cid].ws.close(4000, "kicked")


func _drop(cid: int) -> void:
	var c: Dictionary = _conns[cid]
	_conns.erase(cid)
	if not _rooms.has(c.room):
		return
	var room: Dictionary = _rooms[c.room]
	room.members.erase(c.id)
	if c.id == 1:
		for id in room.members:
			_send_to(c.room, id, {"t": "host_left"})
			_conns[room.members[id]].ws.close(1000, "host_left")
		_rooms.erase(c.room)
	elif room.members.is_empty():
		_rooms.erase(c.room)
	else:
		_send_to(c.room, 1, {"t": "peer_left", "id": c.id})


func _send_to(code: String, id: int, obj: Dictionary) -> void:
	var cid: Variant = _rooms[code].members.get(id)
	if cid != null:
		_reply(cid, obj)


func _reply(cid: int, obj: Dictionary) -> void:
	if _conns.has(cid):
		_conns[cid].ws.send_text(JSON.stringify(obj))


func _new_code() -> String:
	while true:
		var code := ""
		for _i in CODE_LENGTH:
			code += CODE_CHARS[_rng.randi_range(0, CODE_CHARS.length() - 1)]
		if not _rooms.has(code):
			return code
	return ""
