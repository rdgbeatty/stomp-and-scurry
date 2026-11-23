extends "res://launcher.gd"

const PackRelease = preload("res://pack_release.gd")
const FrontMenu = preload("res://front_menu.gd")
const MAIN_MENU_HINT := "Play solo, host a LAN lobby, or enter a host's address to join."
const PACK_FAILED := "The game pack did not start."
const RESUME_DIR := "user://pack-resume"

var _releases := PackRelease.new()
var _front: FrontMenu
var _solo: Button
var _menu: Button
var _game: Node2D
var _mounted_digest := ""
var _failed_packs: Dictionary = {}
var _skip_runtime_update := false
var _muted := false


func _ready() -> void:
	# A failed external pack can leave Godot in the embedded main scene.
	if OS.get_cmdline_user_args().has("--game-pack"):
		get_tree().quit(1)
		return
	get_window().title = "Stomp & Scurry"
	_front = FrontMenu.new()
	add_child(_front)
	_solo = _front.solo
	_host_button = _front.host
	_join_button = _front.join
	_player_name = _front.player_name
	_address = _front.address
	_status = _front.status
	_host_button.pressed.connect(_host)
	_join_button.pressed.connect(_join)
	_address.text_submitted.connect(func(_value):
		if not _join_button.disabled:
			_join()
	)
	if FileAccess.file_exists(PLAYER_NAME_FILE):
		_player_name.text = FileAccess.get_file_as_string(PLAYER_NAME_FILE).strip_edges().left(_player_name.max_length)
	_player_name.text_changed.connect(_save_player_name)
	if FileAccess.file_exists("user://host.txt"):
		_address.text = FileAccess.get_file_as_string("user://host.txt").strip_edges()
	_solo.pressed.connect(_play_or_host.bind("solo"))
	_menu = FrontMenu.make_button(Rect2(856, 31, 78, 39), "Menu")
	_menu.hide()
	_menu.pressed.connect(_return_to_menu)
	add_child(_menu)
	_http = HTTPRequest.new()
	add_child(_http)
	_status.text = MAIN_MENU_HINT
	if not _releases.configured:
		_status.text = "This build has no release feed configured."
		_busy()
	else:
		_solo.grab_focus()
		_resume_update.call_deferred()


func _host() -> void:
	_play_or_host("host")


func _busy() -> void:
	super._busy()
	_solo.disabled = true


func _finish(message: String) -> void:
	super._finish(message)
	_solo.disabled = false


func _resume_update() -> void:
	if not _releases.configured:
		return
	var args := OS.get_cmdline_user_args()
	if args.size() == 4 and args[0] == "--resume-launcher-update":
		await get_tree().process_frame
		if not Updater.acknowledge(args[1], args[3], PackRelease.RUNTIME_VERSION):
			_finish("Could not acknowledge the executable update.")
			return
		if args[2] in ["solo", "host"]:
			_play_or_host(args[2])
		elif args[2] == "join":
			_join(false)
	elif args.size() == 1 and args[0] == "--launcher-update-failed":
		_skip_runtime_update = true
		_finish("The previous executable was restored. You can still play a compatible pack.")
	elif args.size() == 2 and args[0] == "--resume-pack":
		_resume_pack(args[1])


func _process(_delta: float) -> void:
	if _server != null:
		_server.poll()


func _http_get(url: String, output := "") -> Array:
	# GitHub release assets redirect to storage. LAN downloads stay on the host.
	_http.max_redirects = 5 if url.begins_with(_releases.base + "/") else 0
	return await super._http_get(url, output)


func _play_or_host(mode: String) -> void:
	_busy()
	_status.text = "Checking for a game update…"
	var candidates := _releases.cached_offers()
	var local_dir := OS.get_executable_path().get_base_dir()
	var bundled := _releases.verify(FileAccess.get_file_as_string(local_dir.path_join(PackRelease.MANIFEST)))
	var response := await _http_get(_releases.latest_url())
	if not response.is_empty():
		var latest := _releases.verify((response[3] as PackedByteArray).get_string_from_utf8())
		if not latest.is_empty() and (candidates.is_empty() or latest.sequence >= candidates[0].sequence):
			if await _update_runtime(latest, mode):
				return
			candidates.append(latest)
	if not bundled.is_empty():
		candidates.append(bundled)
	candidates.sort_custom(func(a, b): return a.sequence > b.sequence)
	var tried: Dictionary = {}
	for offer in candidates:
		var digest: String = offer.pack_sha256
		if tried.has(digest) or _failed_packs.has(digest) or not PackRelease.compatible(offer):
			continue
		tried[digest] = true
		if not _matches(PackRelease.path_for(offer), digest):
			_status.text = "Downloading game " + offer.tag + "…"
		if await _fetch_pack(offer, "", local_dir.path_join(PackRelease.PACK)):
			_status.text = "Opening " + offer.tag + "…"
			var problem := _run_pack(offer, mode)
			if problem.is_empty():
				return
			if problem != PACK_FAILED:
				_finish(problem)
				return
	_finish("No compatible game pack could start. Check the update connection and try again.")


func _join(allow_launcher_update := true) -> void:
	var address := _address.text.strip_edges()
	if not address.is_valid_ip_address() or address.contains(":"):
		_finish("Enter the host's IPv4 address, for example 192.168.1.10.")
		return
	_busy()
	_status.text = "Looking for a signed LAN session…"
	var base := "http://%s:%d" % [address, HostServer.PORT]
	var response := await _http_get(base + "/session.json")
	if response.is_empty():
		_finish("Couldn't reach the host on port 8000.")
		return
	var session: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if not session is Dictionary or not session.get("manifest") is String:
		_finish("Ask the host to open the pack edition of Stomp & Scurry.")
		return
	var offer := _releases.verify(session.manifest)
	if offer.is_empty() or session.get("build") != offer.pack_sha256 or session.get("download") != "/game/" + offer.pack_sha256 + ".pck":
		_finish("The host's pack could not be verified.")
		return
	if session.get("ready") != true:
		_finish("The host's game is still opening. Try Join again in a moment.")
		return
	_save_host(address)
	if allow_launcher_update and await _update_runtime(offer, "join"):
		return
	if not PackRelease.compatible(offer):
		_finish("This executable doesn't support the host's game pack.")
		return
	_status.text = "Getting the host's game pack…"
	if not await _fetch_pack(offer, base + session.download):
		_finish("Couldn't get a verified copy of the host's game pack.")
		return
	var problem := _run_pack(offer, "join", address)
	if not problem.is_empty():
		_finish(problem)


func _fetch_pack(offer: Dictionary, lan_url := "", bundled_path := "") -> bool:
	var target := PackRelease.path_for(offer)
	var digest: String = offer.pack_sha256
	if _matches(target, digest):
		return true
	var pending := _prepare_path(target)
	if pending.is_empty():
		return false
	if not bundled_path.is_empty() and _matches(bundled_path, digest):
		if DirAccess.copy_absolute(bundled_path, pending) == OK and _install(pending, target, digest):
			return true
		_remove(pending)
	if not lan_url.is_empty():
		if not (await _http_get(lan_url, pending)).is_empty() and _install(pending, target, digest):
			return true
		_remove(pending)
	var got := await _http_get(_releases.asset_url(offer, PackRelease.PACK), pending)
	if not got.is_empty() and _install(pending, target, digest):
		return true
	_remove(pending)
	return false


func _update_runtime(offer: Dictionary, action: String) -> bool:
	if _skip_runtime_update or OS.get_name() != "Windows" or offer.runtime_version <= PackRelease.RUNTIME_VERSION:
		return false
	var target := OS.get_executable_path()
	var pending := target + "." + Updater.nonce() + ".update"
	_status.text = "Downloading the new executable…"
	var got := await _http_get(_releases.asset_url(offer, PackRelease.EXE), pending)
	if not got.is_empty() and _matches(pending, offer.runtime_sha256):
		if Updater.restart(target, pending, action, int(offer.runtime_version)):
			get_tree().quit()
			return true
	_remove(pending)
	return false


func _run_pack(offer: Dictionary, mode: String, value := "-") -> String:
	var path := PackRelease.path_for(offer)
	var digest: String = offer.pack_sha256
	if _failed_packs.has(digest) or not _matches(path, digest):
		return PACK_FAILED
	# Godot keeps mounted packs and their loaded scripts for the life of the process.
	if not _mounted_digest.is_empty() and _mounted_digest != digest:
		return "" if _restart_into_pack(offer, mode, value) else "Couldn't reopen the game with the selected pack."
	if _mounted_digest.is_empty():
		if not ProjectSettings.load_resource_pack(path, false):
			_failed_packs[digest] = true
			return PACK_FAILED
		_mounted_digest = digest
	var scene := load("res://game.tscn") as PackedScene
	var game := scene.instantiate() if scene != null else null
	if not game is Node2D or not game.has_method("primary_action"):
		if game != null:
			game.free()
		_failed_packs[digest] = true
		return PACK_FAILED
	if mode == "host":
		_server = HostServer.new()
		if _server.start_pack(path, digest, offer.envelope) != OK:
			game.free()
			_stop_host()
			return "Port 8000 is busy. Close the other download server or game host."
	_import_solo_score()
	add_child(game)
	move_child(game, 0)
	if _muted:
		game.call("toggle_sound")
	var network: Node = game.get("lan")
	if network == null or not network.has_method("host"):
		game.free()
		_stop_host()
		_failed_packs[digest] = true
		return PACK_FAILED
	network.set("pack_build", digest)
	network.set("local_player_name", _player_name.text.strip_escapes().strip_edges())
	match mode:
		"host":
			network.call("host")
			_server.pack_ready = network.get("role") != 0
		"join":
			network.call("join", value)
		"solo":
			game.call("primary_action")
	if mode != "solo" and network.get("role") == 0:
		var message: String = network.get("status")
		game.free()
		_stop_host()
		return message if not message.is_empty() else "Couldn't open the LAN lobby."
	_game = game
	if mode == "solo":
		_menu.show()
	else:
		network.connect("changed", _network_changed.bind(network))
	# Joining an older host should leave the default offline pack selection alone.
	if mode != "join":
		PackRelease.remember(offer)
	_front.hide()
	return ""


func _network_changed(network: Node) -> void:
	if network.get("role") == 0:
		_return_to_menu.call_deferred(network.get("status"))


func _return_to_menu(message := "") -> void:
	if is_instance_valid(_game):
		_muted = _game.call("sound_is_muted")
		for player: AudioStreamPlayer in _game.find_children("*", "AudioStreamPlayer", true, false):
			player.stop()
		_game.hide()
		_game.process_mode = Node.PROCESS_MODE_DISABLED
		_game.queue_free()
		_game = null
	_stop_host()
	_menu.hide()
	_front.show()
	_finish(message if not message.is_empty() else MAIN_MENU_HINT)
	_solo.grab_focus()


func _restart_into_pack(offer: Dictionary, mode: String, value: String) -> bool:
	var token := Updater.nonce()
	var directory := ProjectSettings.globalize_path(RESUME_DIR)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return false
	var path := directory.path_join(token + ".json")
	var ticket := FileAccess.open(path, FileAccess.WRITE)
	if ticket == null:
		return false
	ticket.store_string(JSON.stringify({"manifest": offer.envelope, "mode": mode, "value": value, "failed": _failed_packs.keys()}))
	ticket.close()
	var args := PackedStringArray(["--", "--resume-pack", token])
	if DisplayServer.get_name() == "headless":
		args.insert(0, "--headless")
	if OS.create_process(OS.get_executable_path(), args) <= 0:
		_remove(path)
		return false
	get_tree().quit()
	return true


func _resume_pack(token: String) -> void:
	if token.length() != 24 or token.to_lower() != token or not token.is_valid_hex_number(false):
		return
	var path := ProjectSettings.globalize_path(RESUME_DIR.path_join(token + ".json"))
	if not FileAccess.file_exists(path):
		return
	var ticket: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_remove(path)
	if not ticket is Dictionary or not ticket.get("manifest") is String or not ticket.get("value") is String:
		return
	var mode: Variant = ticket.get("mode")
	if not mode in ["solo", "host", "join"]:
		return
	if mode == "join" and (not ticket.value.is_valid_ip_address() or ticket.value.contains(":")):
		return
	var offer := _releases.verify(ticket.manifest)
	if offer.is_empty() or not PackRelease.compatible(offer):
		_finish("Couldn't reopen the selected game pack.")
		return
	if ticket.get("failed") is Array:
		for digest in ticket.failed:
			if digest is String and Updater.valid_hash(digest):
				_failed_packs[digest] = true
	_busy()
	_status.text = "Opening " + offer.tag + "…"
	await get_tree().process_frame
	var problem := _run_pack(offer, mode, ticket.value)
	if problem == PACK_FAILED and mode != "join":
		_failed_packs[offer.pack_sha256] = true
		_play_or_host(mode)
	elif not problem.is_empty():
		_finish(problem)


func _import_solo_score() -> void:
	var current := ProjectSettings.globalize_path("user://scores.cfg")
	var old := current.get_base_dir().get_base_dir().path_join("Stomp & Scurry/scores.cfg")
	if not FileAccess.file_exists(current) and FileAccess.file_exists(old):
		DirAccess.copy_absolute(old, current)
