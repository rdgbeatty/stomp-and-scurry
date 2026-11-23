extends RefCounted

const Updater = preload("res://updater.gd")
const RUNTIME_VERSION := 2
const PACK_ABI := 1
const EXE := "StompAndScurry.exe"
const PACK := "StompAndScurry.pck"
const MANIFEST := "release.json"
const MAX_MANIFEST := 4096
const CACHE := "user://packs"

var base := ""
var public_key := CryptoKey.new()
var configured := false


func _init() -> void:
	if not FileAccess.file_exists("res://pack-feed.json"):
		return
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://pack-feed.json"))
	if config is Dictionary and config.get("base") is String and config.get("public_key") is String:
		base = config.base
		configured = public_key.load_from_string(config.public_key, true) == OK


func verify(envelope: String) -> Dictionary:
	if not configured or envelope.is_empty() or envelope.length() > MAX_MANIFEST:
		return {}
	var outer: Variant = JSON.parse_string(envelope)
	if not outer is Dictionary or not outer.get("payload") is String or not outer.get("signature") is String:
		return {}
	var payload := Marshalls.base64_to_raw(outer.payload)
	var signature := Marshalls.base64_to_raw(outer.signature)
	if payload.is_empty() or signature.is_empty():
		return {}
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(payload)
	if not Crypto.new().verify(HashingContext.HASH_SHA256, hash.finish(), signature, public_key):
		return {}
	var offer: Variant = JSON.parse_string(payload.get_string_from_utf8())
	if not offer is Dictionary or offer.get("schema") != 1 or not offer.get("tag") is String:
		return {}
	var tag_pattern := RegEx.create_from_string("^v[0-9]{1,8}\\.[0-9]{1,8}\\.[0-9]{1,8}$")
	if tag_pattern.search(offer.tag) == null:
		return {}
	for field in ["runtime_version", "pack_abi", "sequence"]:
		var value: Variant = offer.get(field)
		if not (value is int or value is float) or value < 1 or value > 2147483647 or value != floorf(value):
			return {}
	for field in ["runtime_sha256", "pack_sha256"]:
		var value: Variant = offer.get(field)
		if not value is String or not Updater.valid_hash(value):
			return {}
	offer["envelope"] = envelope
	return offer


func latest_url() -> String:
	return base + "/latest/download/" + MANIFEST


func asset_url(offer: Dictionary, name: String) -> String:
	return base + "/download/" + offer.tag + "/" + name


static func path_for(offer: Dictionary) -> String:
	return ProjectSettings.globalize_path(CACHE.path_join(offer.pack_sha256 + ".pck"))


static func compatible(offer: Dictionary) -> bool:
	return offer.pack_abi == PACK_ABI and offer.runtime_version <= RUNTIME_VERSION


func cached_offers() -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(CACHE)):
		return offers
	for name in DirAccess.get_files_at(CACHE):
		if not name.ends_with(".json"):
			continue
		var offer := verify(FileAccess.get_file_as_string(CACHE.path_join(name)))
		if not offer.is_empty() and compatible(offer) and FileAccess.get_sha256(path_for(offer)) == offer.pack_sha256:
			offers.append(offer)
	offers.sort_custom(func(a, b): return a.sequence > b.sequence)
	return offers


static func remember(offer: Dictionary) -> void:
	# Remember the pack only after its game scene starts successfully.
	var path := ProjectSettings.globalize_path(CACHE.path_join(str(int(offer.sequence)) + "-" + offer.pack_sha256 + ".json"))
	if FileAccess.file_exists(path):
		return
	var pending := path + "." + Updater.nonce() + ".partial"
	var output := FileAccess.open(pending, FileAccess.WRITE)
	if output == null:
		return
	output.store_string(offer.envelope)
	output.close()
	if DirAccess.rename_absolute(pending, path) != OK:
		DirAccess.remove_absolute(pending)
