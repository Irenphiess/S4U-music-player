extends RefCounted
## Scan one directory level; decode audio only when selected for playback.
var mac_bridge: RefCounted

const AUDIO_EXTENSIONS := ["mp3", "wav", "ogg", "oga", "flac", "m4a", "aac", "aif", "aiff", "caf"]


func scan(root_path: String) -> Dictionary:
	var albums: Array = []
	var root_dir := DirAccess.open(root_path)
	if root_dir == null:
		return {"albums": albums, "error": "无法读取音乐库，请检查文件夹是否存在或重新选择。"}
	var folders := Array(root_dir.get_directories())
	folders.sort_custom(_natural_less)
	for folder in folders:
		if str(folder).begins_with("."):
			continue
		var album_path := root_path.path_join(folder)
		var album_dir := DirAccess.open(album_path)
		var tracks: Array = []
		var issue := ""
		if album_dir == null:
			issue = "无法读取此专辑文件夹"
		else:
			var files := Array(album_dir.get_files())
			files.sort_custom(_natural_less)
			for file in files:
				if not str(file).begins_with(".") and str(file).get_extension().to_lower() in AUDIO_EXTENSIONS:
					tracks.append({"name": str(file).get_basename(), "path": album_path.path_join(file)})
		albums.append({"name": str(folder), "path": album_path, "tracks": tracks, "error": issue})
	return {"albums": albums, "error": ""}

func _natural_less(a: String, b: String) -> bool:
	var comparison := a.naturalnocasecmp_to(b)
	return a < b if comparison == 0 else comparison < 0

func load_mp3(path: String) -> AudioStreamMP3:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() == 0:
		return null
	var bytes := file.get_buffer(file.get_length())
	file.close()
	# Godot 4.3 runtime loading: external files need no .import sidecars.
	var stream := AudioStreamMP3.new()
	stream.data = bytes
	if stream.get_length() <= 0:
		return null
	stream.loop = false
	return stream

func load_audio(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		return null
	var extension := path.get_extension().to_lower()
	if extension not in AUDIO_EXTENSIONS:
		return null
	if extension == "mp3":
		return load_mp3(path)
	if extension in ["ogg", "oga"]:
		var ogg := AudioStreamOggVorbis.load_from_file(path)
		if ogg != null and ogg.get_length() > 0:
			ogg.loop = false
			return ogg
	if extension == "wav":
		var wav := _load_pcm_wav(path)
		if wav != null:
			return wav
	# Decode inside the app through Core Audio first (AAC/ALAC M4A included).
	# This avoids spawning a codec subprocess from a packaged/sandboxed app.
	if OS.has_feature("macos"):
		var temp_path := ProjectSettings.globalize_path("user://decode-%s-%s.wav" % [OS.get_process_id(), Time.get_ticks_usec()])
		var succeeded := false
		if mac_bridge != null:
			var response = JSON.parse_string(mac_bridge.call("exchange", JSON.stringify({
				"op": "decode", "source": ProjectSettings.globalize_path(path), "destination": temp_path
			})))
			succeeded = response is Dictionary and bool(response.get("ok", false))
		if not succeeded and FileAccess.file_exists("/usr/bin/afconvert"):
			var output: Array = []
			succeeded = OS.execute("/usr/bin/afconvert", PackedStringArray([
				"-f", "WAVE", "-d", "LEI16", "-c", "2", ProjectSettings.globalize_path(path), temp_path
			]), output, true) == 0
		var decoded: AudioStreamWAV = _load_pcm_wav(temp_path) if succeeded else null
		if FileAccess.file_exists(temp_path): DirAccess.remove_absolute(temp_path)
		return decoded
	return null

func _load_pcm_wav(path: String) -> AudioStreamWAV:
	# Godot 4.3 has no AudioStreamWAV.load_from_file. Parse RIFF chunks, not a fixed
	# 44-byte header: metadata, padding, and data-before-fmt are all legal.
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 12 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF" or bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return null
	var limit := int(bytes.decode_u32(4)) + 8
	if limit > bytes.size() or limit < 12:
		return null
	var cursor := 12
	var format_code := 0
	var channels := 0
	var rate := 0
	var bits := 0
	var block_align := 0
	var audio := PackedByteArray()
	while cursor + 8 <= limit:
		var chunk := bytes.slice(cursor, cursor + 4).get_string_from_ascii()
		var length := int(bytes.decode_u32(cursor + 4))
		var begin := cursor + 8
		if length > limit - begin:
			return null
		if chunk == "fmt ":
			if length < 16:
				return null
			format_code = bytes.decode_u16(begin)
			channels = bytes.decode_u16(begin + 2)
			rate = bytes.decode_u32(begin + 4)
			block_align = bytes.decode_u16(begin + 12)
			bits = bytes.decode_u16(begin + 14)
		elif chunk == "data":
			audio = bytes.slice(begin, begin + length)
		cursor = begin + length + (length % 2)
	if format_code != 1 or channels not in [1, 2] or bits not in [8, 16] or rate <= 0:
		return null
	if audio.is_empty() or block_align != channels * (bits / 8) or audio.size() % block_align != 0:
		return null
	if bits == 8:
		# RIFF 8-bit PCM is unsigned; Godot's 8-bit PCM is signed.
		for i in range(audio.size()):
			audio[i] = (int(audio[i]) - 128) & 0xff
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS if bits == 8 else AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = channels == 2
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = audio
	return stream
