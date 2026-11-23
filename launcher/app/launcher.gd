extends Node

const HostServer = preload("res://server.gd")
const Updater = preload("res://updater.gd")
const GAME := "Stomp and Scurry.exe"
const MANIFEST := "launcher-release.json"
const VERSIONS := "user://versions"
const PLAYER_NAME_FILE := "user://player-name.txt"

var _server: HostServer
var _host_pid := -1
var _marker := ""
var _status: Label
var _address: LineEdit
var _player_name: LineEdit
var _host_button: Button
var _join_button: Button
var _http: HTTPRequest


func _ready() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(36, 26)
	box.size = Vector2(488, 280)
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var title := Label.new()
	title.text = "Stomp & Scurry"
	title.add_theme_font_size_override("font_size", 31)
	box.add_child(title)
	_player_name = LineEdit.new()
	_player_name.placeholder_text = "Player name (optional)"
	_player_name.max_length = 20
	_player_name.custom_minimum_size.y = 36
	if FileAccess.file_exists(PLAYER_NAME_FILE):
		_player_name.text = FileAccess.get_file_as_string(PLAYER_NAME_FILE).strip_edges().left(_player_name.max_length)
	_player_name.text_changed.connect(_save_player_name)
	box.add_child(_player_name)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	_host_button = Button.new()
	_host_button.text = "Host LAN lobby"
	_host_button.custom_minimum_size = Vector2(175, 40)
	_host_button.pressed.connect(_host)
	actions.add_child(_host_button)
	_address = LineEdit.new()
	_address.placeholder_text = "Host IPv4 address"
	_address.max_length = 15
	_address.custom_minimum_size.x = 200
	if FileAccess.file_exists("user://host.txt"):
		_address.text = FileAccess.get_file_as_string("user://host.txt").strip_edges()
	box.add_child(_address)
	_join_button = Button.new()
	_join_button.text = "Join LAN lobby"
	_join_button.custom_minimum_size = Vector2(175, 40)
	_join_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_join_button.pressed.connect(_join)
	_address.text_submitted.connect(func(_value):
		if not _join_button.disabled:
			_join()
	)
	box.add_child(_join_button)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Host from the game's build folder, or enter the host's address to join."
	box.add_child(_status)
	_http = HTTPRequest.new()
	_http.max_redirects = 0
	add_child(_http)
	_resume_update.call_deferred()


func _resume_update() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 4 and args[0] == "--resume-launcher-update":
		await get_tree().process_frame
		if not Updater.acknowledge(args[1], args[3]):
			_finish("Could not acknowledge the launcher update.")
			return
		_address.text = args[2]
		_join(false)
	elif args.size() == 1 and args[0] == "--launcher-update-failed":
		_finish("The previous launcher was restored.")
		if _address.text.is_valid_ip_address():
			_join(false)


func _process(_delta: float) -> void:
	if _server == null:
		return
	if not OS.is_process_running(_host_pid):
		_stop_host()
		_finish("The host game closed.")
		return
	_server.poll()


func _exit_tree() -> void:
	_stop_host()


func _stop_host() -> void:
	if _server != null:
		_server.stop()
		_server = null
	if not _marker.is_empty() and FileAccess.file_exists(_marker):
		DirAccess.remove_absolute(_marker)


func _busy() -> void:
	_host_button.disabled = true
	_join_button.disabled = true


func _finish(message: String) -> void:
	_status.text = message
	_host_button.disabled = false
	_join_button.disabled = false


func _host() -> void:
	_busy()
	_status.text = "Checking the published game…"
	await get_tree().process_frame
	var executable := OS.get_executable_path()
	var directory := executable.get_base_dir()
	var manifest := directory.path_join(MANIFEST)
	if not FileAccess.file_exists(manifest):
		_finish("Open the launcher in the game's build folder to host.")
		return
	var release: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest))
	if not release is Dictionary or not release.get("build") is String or not release.get("file") is String:
		_finish("The game's build description is invalid.")
		return
	var filename: String = release.file
	var build: String = release.build
	if not Updater.valid_hash(build) or filename != filename.get_file() or not filename.ends_with(".exe"):
		_finish("The game's build description is invalid.")
		return
	var game := _cache_path(build)
	if not _matches(game, build):
		var temporary := _prepare_path(game)
		if temporary.is_empty() or DirAccess.copy_absolute(directory.path_join(filename), temporary) != OK or not _install(temporary, game, build):
			_remove(temporary)
			_finish("Couldn't verify or cache the published game. Try again after the build finishes.")
			return
	_marker = ProjectSettings.globalize_path("user://" + Updater.nonce() + ".ready")
	_server = HostServer.new()
	if _server.start(game, build, _marker, executable) != OK:
		_stop_host()
		_finish("Port 8000 is busy or unavailable. Close the standalone download server and try again.")
		return
	_host_pid = _open_game(game, "--launcher-host", _marker)
	if _host_pid <= 0:
		_stop_host()
		_finish("Couldn't open the host game.")
		return
	_status.text = "Hosting. Keep this window open. Share the Wi-Fi or Ethernet IPv4 address shown in the game."


func _join(allow_launcher_update := true) -> void:
	var address := _address.text.strip_edges()
	if not address.is_valid_ip_address() or address.contains(":"):
		_finish("Enter the host's IPv4 address, for example 192.168.1.10.")
		return
	_busy()
	_status.text = "Finding the host game…"
	var base := "http://%s:%d" % [address, HostServer.PORT]
	var session := await _get_session(base)
	if session.is_empty():
		_finish("Couldn't reach the host launcher at %s:8000." % address)
		return
	if allow_launcher_update and Updater.advertised_version(session) > Updater.VERSION:
		if await _update_launcher(base, address, session):
			return
		_status.text = "Launcher update unavailable. Joining with this version…"
	var build: String = session.build
	var game := _cache_path(build)
	if not _matches(game, build):
		var temporary := _prepare_path(game)
		if temporary.is_empty():
			_finish("Couldn't create the game download folder.")
			return
		_status.text = "Downloading the matching game build…"
		var result := await _http_get(base + session.download, temporary)
		if result.is_empty() or not _install(temporary, game, build):
			_remove(temporary)
			_finish("The game download failed or didn't match the host build. Try joining again.")
			return
	_status.text = "Waiting for the host game…"
	for attempt in 40:
		session = await _get_session(base)
		if session.is_empty():
			break
		if session.build != build:
			_finish("The host changed builds. Choose Join again.")
			return
		if session.ready:
			if _open_game(game, "--launcher-join", address) <= 0:
				_finish("Couldn't open the downloaded game.")
				return
			_save_host(address)
			_finish("Lobby opened. Pick Ant or Shoe, then Ready.")
			return
		await get_tree().create_timer(0.5).timeout
	_finish("The host game isn't ready. Check the host's game window and try again.")


func _open_game(game: String, mode: String, value: String) -> int:
	var args := PackedStringArray(["--", mode, value])
	var player_name := _player_name.text.strip_edges()
	if not player_name.is_empty():
		# Encode the name so spaces and quotes survive Windows command line parsing.
		args.append(Marshalls.utf8_to_base64(player_name))
	return OS.create_process(game, args)


func _save_player_name(value: String) -> void:
	var saved := FileAccess.open(PLAYER_NAME_FILE, FileAccess.WRITE)
	if saved != null:
		saved.store_string(value.strip_edges())


func _save_host(address: String) -> void:
	var saved := FileAccess.open("user://host.txt", FileAccess.WRITE)
	if saved != null:
		saved.store_string(address)


func _update_launcher(base: String, address: String, session: Dictionary) -> bool:
	if not Updater.valid_offer(session):
		return false
	var target := OS.get_executable_path()
	var pending := target + "." + Updater.nonce() + ".update"
	_status.text = "Downloading the new launcher…"
	var response := await _http_get(base + session.launcher_download, pending)
	if response.is_empty() or not _matches(pending, session.launcher_hash):
		_remove(pending)
		return false
	_save_host(address)
	_status.text = "Restarting the launcher…"
	if not Updater.restart(target, pending, address, Updater.advertised_version(session)):
		_remove(pending)
		return false
	get_tree().quit()
	return true


func _get_session(base: String) -> Dictionary:
	var body := await _http_get(base + "/session.json")
	if body.is_empty():
		return {}
	var session: Variant = JSON.parse_string((body[3] as PackedByteArray).get_string_from_utf8())
	if not session is Dictionary or not session.get("build") is String or not session.get("ready") is bool:
		return {}
	if not Updater.valid_hash(session.build) or session.get("download") != "/game/" + session.build + ".exe":
		return {}
	return session


func _http_get(url: String, output := "") -> Array:
	_http.download_file = output
	_http.timeout = 6.0 if output.is_empty() else 180.0
	_http.body_size_limit = 4096 if output.is_empty() else 268435456
	if _http.request(url) != OK:
		return []
	var response: Array = await _http.request_completed
	return response if response[0] == HTTPRequest.RESULT_SUCCESS and response[1] == 200 else []


func _cache_path(build: String) -> String:
	return ProjectSettings.globalize_path(VERSIONS.path_join(build).path_join(GAME))


func _prepare_path(game: String) -> String:
	var error := DirAccess.make_dir_recursive_absolute(game.get_base_dir())
	return game + "." + Updater.nonce() + ".partial" if error == OK else ""


func _matches(path: String, build: String) -> bool:
	return FileAccess.file_exists(path) and FileAccess.get_sha256(path) == build


func _remove(path: String) -> void:
	if not path.is_empty() and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _install(temporary: String, game: String, build: String) -> bool:
	if not _matches(temporary, build):
		return false
	if _matches(game, build):
		_remove(temporary)
		return true
	if DirAccess.rename_absolute(temporary, game) == OK:
		return true
	if _matches(game, build):
		_remove(temporary)
		return true
	return false
