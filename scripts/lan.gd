extends Node

const PORT := 24567
const BUILD_PROTOCOL := "stomp-and-scurry-four-player-3"

enum Role { SOLO, HOST, GUEST }
enum Choice { NONE, ANT, SHOE }

const MAX_PLAYERS := 4

signal changed
signal lobby_changed
signal begin_round
signal stomp_requested(id: int, target: Vector2)
signal movement_received(id: int, direction: Vector2)
signal jump_requested(id: int, direction: Vector2)
signal state_received(state: Dictionary)

var role := Role.SOLO
var players: Dictionary = {}
var local_player_name := ""
var pack_build := ""
var _player_names: Dictionary = {}
var round_id := 0
var in_round := false
var status := ""
var address := ""
var _connect_time := 0.0
@onready var _session := multiplayer as SceneMultiplayer


func _ready() -> void:
	_session.auth_callback = _check_build
	_session.peer_authenticating.connect(_send_build)
	_session.peer_authentication_failed.connect(_build_check_failed)
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(leave.bind("Couldn't connect. Check the host's IP address."))
	multiplayer.server_disconnected.connect(leave.bind("The host left the game."))


func _send_build(id: int) -> void:
	_session.send_auth(id, _protocol_bytes())


func _check_build(id: int, data: PackedByteArray) -> void:
	if data == _protocol_bytes():
		_session.complete_auth(id)
	else:
		_session.disconnect_peer(id)


func _protocol_bytes() -> PackedByteArray:
	return (BUILD_PROTOCOL if pack_build.is_empty() else BUILD_PROTOCOL + ":" + pack_build).to_utf8_buffer()


func _build_check_failed(_id: int) -> void:
	var message := "Everyone needs the same Windows build."
	if role == Role.GUEST:
		leave.call_deferred(message)
	elif role == Role.HOST:
		status = message
		lobby_changed.emit()


func _process(delta: float) -> void:
	if _connect_time > 0.0:
		_connect_time -= delta
		if _connect_time <= 0.0:
			leave("Connection timed out. Check the host's IP address.")


func host() -> void:
	if role != Role.SOLO:
		return
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_PLAYERS - 1) != OK:
		leave("Couldn't host on UDP port %d." % PORT)
		return
	role = Role.HOST
	multiplayer.multiplayer_peer = peer
	var addresses := PackedStringArray()
	for local_address in IP.get_local_addresses():
		if not local_address.contains(":") and not local_address.begins_with("127.") and not local_address.begins_with("169.254."):
			addresses.append(local_address)
	address = "  /  ".join(addresses) if not addresses.is_empty() else "Find your IPv4 address with ipconfig."
	players = {1: Vector2i.ZERO}
	_player_names[1] = local_player_name
	status = ""
	changed.emit()


func join(host_address: String) -> void:
	if role != Role.SOLO:
		return
	host_address = host_address.strip_edges()
	if not host_address.is_valid_ip_address() or host_address.contains(":"):
		leave("Enter the host's IPv4 address, for example 192.168.1.10.")
		return
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(host_address, PORT) != OK:
		leave("Couldn't connect to " + host_address + ".")
		return
	role = Role.GUEST
	_connect_time = 8.0
	status = "Connecting to " + host_address + "…"
	multiplayer.multiplayer_peer = peer
	changed.emit()


func leave(message := "") -> void:
	var peer := multiplayer.multiplayer_peer
	role = Role.SOLO
	players.clear()
	_player_names.clear()
	in_round = false
	round_id = 0
	_connect_time = 0.0
	address = ""
	status = message
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if peer is ENetMultiplayerPeer:
		peer.close()
	changed.emit()


func local_id() -> int:
	return multiplayer.get_unique_id() if role != Role.SOLO and not players.is_empty() else 1


func slot(id: int) -> int:
	var ids := players.keys()
	ids.sort()
	return ids.find(id) + 1


static func clean_player_name(value: String) -> String:
	return value.strip_escapes().strip_edges().left(20)


func player_name(id: int) -> String:
	var display_name: String = _player_names.get(id, "")
	return display_name if not display_name.is_empty() else "Player %d" % slot(id)


func choice(id: int) -> int:
	var ballot: Vector2i = players.get(id, Vector2i.ZERO)
	return ballot.x


func ready(id: int) -> bool:
	var ballot: Vector2i = players.get(id, Vector2i.ZERO)
	return ballot.y != 0


func choose(value: int) -> void:
	_set_local_ballot(value, false)


func toggle_ready() -> void:
	_set_local_ballot(choice(local_id()), not ready(local_id()))


func _set_local_ballot(value: int, is_ready: bool) -> void:
	if role == Role.HOST:
		_set_ballot(1, value, is_ready)
	elif role == Role.GUEST and players.has(local_id()):
		_submit_ballot.rpc_id(1, value, is_ready)


func _set_ballot(id: int, value: int, is_ready: bool) -> void:
	if in_round or not players.has(id) or value < Choice.NONE or value > Choice.SHOE:
		return
	players[id] = Vector2i(value, int(is_ready and value != Choice.NONE))
	var has_ant := false
	var has_shoe := false
	var everyone_ready := players.size() >= 2
	for ballot: Vector2i in players.values():
		has_ant = has_ant or ballot.x == Choice.ANT
		has_shoe = has_shoe or ballot.x == Choice.SHOE
		everyone_ready = everyone_ready and ballot.y != 0
	if everyone_ready and has_ant and has_shoe:
		in_round = true
		round_id += 1
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			_session.refuse_new_connections = true
		_announce_lobby()
		begin_round.emit()
	else:
		_announce_lobby()


func reopen_lobby(message := "") -> void:
	if role != Role.HOST:
		return
	in_round = false
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		_session.refuse_new_connections = false
	status = message
	for id in players:
		players[id] = Vector2i(choice(id), 0)
	_announce_lobby()


func _announce_lobby() -> void:
	if not multiplayer.get_peers().is_empty():
		_receive_lobby.rpc(players, in_round, round_id, status, _player_names)
	lobby_changed.emit()


func request_stomp(target: Vector2) -> void:
	if role == Role.HOST:
		stomp_requested.emit(1, target)
	elif role == Role.GUEST and in_round:
		_send_stomp.rpc_id(1, round_id, target)


func send_movement(direction: Vector2) -> void:
	if role == Role.GUEST and in_round:
		_send_movement.rpc_id(1, round_id, direction)


func request_jump(direction := Vector2.ZERO) -> void:
	if role == Role.HOST:
		jump_requested.emit(1, direction)
	elif role == Role.GUEST and in_round:
		_send_jump.rpc_id(1, round_id, direction)


func publish(state: Dictionary) -> void:
	if role == Role.HOST and in_round and not multiplayer.get_peers().is_empty():
		_receive_state.rpc(round_id, state)


func _connected() -> void:
	_connect_time = 0.0
	if not local_player_name.is_empty():
		_submit_name.rpc_id(1, local_player_name)
	if players.is_empty():
		status = "Connected. Opening the lobby…"
	lobby_changed.emit()


func _peer_connected(id: int) -> void:
	if role == Role.HOST:
		if in_round or players.size() >= MAX_PLAYERS:
			_session.disconnect_peer(id)
			return
		if not players.has(1):
			players[1] = Vector2i.ZERO
		players[id] = Vector2i.ZERO
		status = ""
		_announce_lobby()


func _peer_disconnected(id: int) -> void:
	if role == Role.HOST and players.erase(id):
		_player_names.erase(id)
		reopen_lobby("A player left. Pick Ready to start again.")


func _valid_input(epoch: int, selected_role: int) -> int:
	var sender := multiplayer.get_remote_sender_id()
	return sender if role == Role.HOST and in_round and epoch == round_id and choice(sender) == selected_role else 0


@rpc("any_peer", "call_remote", "reliable")
func _submit_name(value: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if role == Role.HOST and not in_round and players.has(id):
		_player_names[id] = clean_player_name(value)
		_announce_lobby()


@rpc("any_peer", "call_remote", "reliable")
func _submit_ballot(value: int, is_ready: bool) -> void:
	if role == Role.HOST:
		_set_ballot(multiplayer.get_remote_sender_id(), value, is_ready)


@rpc("authority", "call_remote", "reliable")
func _receive_lobby(roster: Dictionary, started: bool, epoch: int, message: String, names: Dictionary) -> void:
	if role != Role.GUEST:
		return
	var new_round := started and (not in_round or round_id != epoch)
	players = roster
	_player_names = names
	in_round = started
	round_id = epoch
	status = message
	lobby_changed.emit()
	if new_round:
		begin_round.emit()


@rpc("any_peer", "call_remote", "reliable")
func _send_stomp(epoch: int, target: Vector2) -> void:
	var id := _valid_input(epoch, Choice.SHOE)
	if id != 0 and target.is_finite():
		stomp_requested.emit(id, target)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _send_movement(epoch: int, direction: Vector2) -> void:
	var id := _valid_input(epoch, Choice.ANT)
	if id != 0 and direction.is_finite():
		movement_received.emit(id, direction.limit_length())


@rpc("any_peer", "call_remote", "reliable")
func _send_jump(epoch: int, direction: Vector2) -> void:
	var id := _valid_input(epoch, Choice.ANT)
	if id != 0 and direction.is_finite():
		jump_requested.emit(id, direction.limit_length())


@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_state(epoch: int, state: Dictionary) -> void:
	if role == Role.GUEST and in_round and epoch == round_id:
		state_received.emit(state)
