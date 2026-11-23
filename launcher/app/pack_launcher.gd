extends "res://launcher.gd"

const PackRelease = preload("res://pack_release.gd")

var _releases := PackRelease.new()
var _solo: Button
var _game_pid := -1
var _starting := false
var _skip_runtime_update := false


func _ready() -> void:
	# A failed external pack can leave Godot in the embedded main scene.
	if OS.get_cmdline_user_args().has("--game-pack"):
		get_tree().quit(1)
		return
	super._ready()
	_solo = Button.new()
	_solo.text = "Play solo"
	_solo.custom_minimum_size = Vector2(175, 40)
	_solo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_solo.pressed.connect(_play_or_host.bind("solo"))
	var box := _status.get_parent()
	box.add_child(_solo)
	box.move_child(_solo, 2)
	_status.text = "Play solo, host a LAN lobby, or enter a host's address to join."
	if not _releases.configured:
		_status.text = "This build has no release feed configured."
		_busy()


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


func _process(_delta: float) -> void:
	if _starting:
		return
	if _game_pid > 0 and not OS.is_process_running(_game_pid):
		_game_pid = -1
		_stop_host()
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_finish("Play solo, host, or join another lobby.")
	elif _server != null:
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
		if tried.has(digest) or not PackRelease.compatible(offer):
			continue
		tried[digest] = true
		if await _fetch_pack(offer, "", local_dir.path_join(PackRelease.PACK)):
			_status.text = "Opening " + offer.tag + "…"
			var problem := await _run_pack(offer, mode)
			if problem.is_empty():
				PackRelease.remember(offer)
				return
			if problem != "The game pack did not start.":
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
	var problem := await _run_pack(offer, "join", address)
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
	if not _matches(path, offer.pack_sha256):
		return "The game pack did not start."
	_marker = ProjectSettings.globalize_path("user://" + Updater.nonce() + ".ready")
	if mode == "host":
		_server = HostServer.new()
		if _server.start_pack(path, offer.pack_sha256, _marker, offer.envelope) != OK:
			_stop_host()
			return "Port 8000 is busy. Close the other download server or game host."
	var player_name := _player_name.text.strip_edges()
	var encoded := "-" if player_name.is_empty() else Marshalls.utf8_to_base64(player_name)
	var args := PackedStringArray()
	if DisplayServer.get_name() == "headless":
		args.append("--headless")
	args.append_array(["--main-pack", path, "--", "--game-pack", offer.pack_sha256, _marker, mode, value, encoded])
	_starting = true
	_game_pid = OS.create_process(OS.get_executable_path(), args)
	var until := Time.get_ticks_msec() + 12000
	while _game_pid > 0 and OS.is_process_running(_game_pid) and Time.get_ticks_msec() < until:
		if _server != null:
			_server.poll()
		if FileAccess.file_exists(_marker):
			var marker := FileAccess.get_file_as_string(_marker)
			if marker == "ready":
				_starting = false
				if DisplayServer.get_name() != "headless":
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
				return ""
			if not marker.is_empty():
				_close_failed_game()
				return marker
		await get_tree().create_timer(0.1).timeout
	_close_failed_game()
	return "The game pack did not start."


func _close_failed_game() -> void:
	if _game_pid > 0 and OS.is_process_running(_game_pid):
		OS.kill(_game_pid)
	_game_pid = -1
	_starting = false
	_stop_host()
