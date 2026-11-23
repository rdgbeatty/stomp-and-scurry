extends RefCounted

# Bump when releasing a launcher change. A new game release alone does not
# change this version or trigger another launcher download.
const VERSION := 2
const UPDATE_DIR := "user://launcher-update"
const HELPER_RESOURCE := "res://restart_helper.bin"


static func valid_hash(digest: String) -> bool:
	return digest.length() == 64 and digest.to_lower() == digest and digest.is_valid_hex_number(false)


static func download_path(digest: String) -> String:
	return "/launcher/" + digest + ".exe"


static func advertised_version(session: Dictionary) -> int:
	var version: Variant = session.get("launcher_version", 0)
	if version is int or version is float:
		if version >= 1 and version <= 2147483647 and version == floorf(version):
			return int(version)
	return 0


static func valid_offer(session: Dictionary) -> bool:
	var digest: Variant = session.get("launcher_hash")
	return digest is String and valid_hash(digest) and session.get("launcher_download") == download_path(digest)


static func nonce() -> String:
	return Crypto.new().generate_random_bytes(12).hex_encode()


static func helper_path() -> String:
	var dir := ProjectSettings.globalize_path(UPDATE_DIR)
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return ""
	var digest := FileAccess.get_sha256(HELPER_RESOURCE)
	if not valid_hash(digest):
		return ""
	var path := dir.path_join("restart-" + digest.substr(0, 20) + ".exe")
	if FileAccess.file_exists(path) and FileAccess.get_sha256(path) == digest:
		return path
	var tmp := path + "." + nonce() + ".partial"
	var output := FileAccess.open(tmp, FileAccess.WRITE)
	if output == null:
		return ""
	output.store_buffer(FileAccess.get_file_as_bytes(HELPER_RESOURCE))
	output.close()
	if FileAccess.get_sha256(tmp) != digest:
		DirAccess.remove_absolute(tmp)
		return ""
	var moved := DirAccess.rename_absolute(tmp, path)
	if moved != OK:
		DirAccess.remove_absolute(tmp)
	if FileAccess.file_exists(path) and FileAccess.get_sha256(path) == digest:
		return path
	return ""


static func restart(target: String, pending: String, address: String, version: int) -> bool:
	var helper := helper_path()
	if helper.is_empty():
		return false
	var token := nonce()
	var backup := target + "." + token + ".backup"
	var marker := ProjectSettings.globalize_path(UPDATE_DIR.path_join(token + ".ready"))
	var arguments := PackedStringArray([str(OS.get_process_id()), target, pending, backup, marker, address, str(version)])
	return OS.create_process(helper, arguments) > 0


static func acknowledge(marker: String, version: String, expected := VERSION) -> bool:
	# A launcher started directly with CLI arguments can only write a temporary
	# marker in the launcher's own update directory.
	var dir := ProjectSettings.globalize_path(UPDATE_DIR).replace("\\", "/").simplify_path()
	marker = marker.replace("\\", "/").simplify_path()
	if version != str(expected) or marker.get_base_dir() != dir or not marker.ends_with(".ready"):
		return false
	var ready := FileAccess.open(marker, FileAccess.WRITE)
	if ready == null:
		return false
	ready.store_string("ready")
	ready.close()
	return true
