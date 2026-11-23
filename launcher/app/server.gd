extends RefCounted

const Updater = preload("res://updater.gd")
const PORT := 8000
const TRANSFER_CHUNK := 65536
const CONNECTION_LIMIT := 12

class Client:
	var socket: StreamPeerTCP
	var request := PackedByteArray()
	var pending := PackedByteArray()
	var file: FileAccess
	var touched := 0
	var responding := false

var listener := TCPServer.new()
var clients: Array[Client] = []
var game_path := ""
var build_id := ""
var status_file := ""
var launcher_path := ""
var launcher_hash := ""
var pack_manifest := ""


func start(game: String, build: String, marker: String, launcher: String) -> Error:
	game_path = game
	build_id = build
	status_file = marker
	launcher_path = launcher
	launcher_hash = FileAccess.get_sha256(launcher)
	return listener.listen(PORT, "0.0.0.0")


func start_pack(path: String, digest: String, marker: String, manifest: String) -> Error:
	game_path = path
	build_id = digest
	status_file = marker
	pack_manifest = manifest
	return listener.listen(PORT, "0.0.0.0")


func stop() -> void:
	listener.stop()
	for client in clients:
		client.socket.disconnect_from_host()
	clients.clear()


func poll() -> void:
	while listener.is_connection_available():
		var socket := listener.take_connection()
		if clients.size() >= CONNECTION_LIMIT:
			socket.disconnect_from_host()
		else:
			var client := Client.new()
			client.socket = socket
			client.touched = Time.get_ticks_msec()
			clients.append(client)
	for index in range(clients.size() - 1, -1, -1):
		var client := clients[index]
		client.socket.poll()
		if client.socket.get_status() != StreamPeerTCP.STATUS_CONNECTED or Time.get_ticks_msec() - client.touched > 20000 or not _advance(client):
			client.socket.disconnect_from_host()
			clients.remove_at(index)


func _advance(client: Client) -> bool:
	if not client.responding:
		var available := client.socket.get_available_bytes()
		if available == 0:
			return true
		var result := client.socket.get_partial_data(mini(available, 8192))
		if result[0] != OK:
			return false
		client.request.append_array(result[1])
		client.touched = Time.get_ticks_msec()
		var header := client.request.get_string_from_utf8()
		if header.contains("\r\n\r\n"):
			var line := header.get_slice("\r\n", 0).split(" ")
			_respond(client, line)
		elif client.request.size() > 8192:
			return false
		else:
			return true
	for chunk in 4:
		if client.pending.is_empty():
			if client.file == null or client.file.get_position() >= client.file.get_length():
				return false
			client.pending = client.file.get_buffer(TRANSFER_CHUNK)
		var sent := client.socket.put_partial_data(client.pending)
		if sent[0] != OK:
			return false
		if sent[1] == 0:
			break
		client.touched = Time.get_ticks_msec()
		client.pending = client.pending.slice(sent[1])
	return true


func _respond(client: Client, request: PackedStringArray) -> void:
	client.responding = true
	if request.size() < 3 or (request[0] != "GET" and request[0] != "HEAD"):
		client.pending = _header("400 Bad Request", "text/plain", 0)
		return
	var route := request[1]
	var download := "/game/" + build_id + (".exe" if pack_manifest.is_empty() else ".pck")
	if route == "/session.json":
		var marker := FileAccess.get_file_as_string(status_file) if FileAccess.file_exists(status_file) else ""
		var session := {"build": build_id, "download": download, "ready": marker == "ready"}
		if not pack_manifest.is_empty():
			session["manifest"] = pack_manifest
		elif Updater.valid_hash(launcher_hash):
			session["launcher_version"] = Updater.VERSION
			session["launcher_hash"] = launcher_hash
			session["launcher_download"] = Updater.download_path(launcher_hash)
		var body := JSON.stringify(session).to_utf8_buffer()
		client.pending = _header("200 OK", "application/json", body.size())
		if request[0] == "GET":
			client.pending.append_array(body)
	elif route == download or (not launcher_path.is_empty() and (route == "/launcher.exe" or (not launcher_hash.is_empty() and route == Updater.download_path(launcher_hash)))):
		var file := FileAccess.open(game_path if route == download else launcher_path, FileAccess.READ)
		if file == null:
			client.pending = _header("404 Not Found", "text/plain", 0)
			return
		client.pending = _header("200 OK", "application/octet-stream", file.get_length())
		if request[0] == "GET":
			client.file = file
	else:
		client.pending = _header("404 Not Found", "text/plain", 0)


func _header(status: String, content_type: String, length: int) -> PackedByteArray:
	return ("HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" %
		[status, content_type, length]).to_utf8_buffer()
