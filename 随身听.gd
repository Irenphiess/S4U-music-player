extends Node2D

const Library = preload("res://music_library.gd")
const DiscScene = preload("res://CD盘.tscn")
const CONFIG_PATH := "user://folder_music.cfg"
const PAGE_SIZE := 11
const COVERS := ["便利店后武装少女两人", "阳电子涡流", "浓缩拼配", "碧色晴海风", "8号混凝土", "烂诡计", "网中鸟", "真相处方", "烟，花", "终局（纪念版）", "赛博纪元（精选集）"]

var library := Library.new()
var mac_bridge: RefCounted
var preferences: Node
var media_poll := 0.0
var last_media_state := ""
var 按键反馈: Dictionary = {}
var 音乐库路径 := ""
var 专辑列表: Array = []
var 当前专辑序号 := -1
var 当前播放序号 := 0
var 当前播放歌名 := "请放入音乐文件"
var 当前显示CD名 := ""
var 缩放倍率 := 1.0
var 当前页 := 0
var 正在拖拽 := false
var 拖拽起点 := Vector2i.ZERO
var 窗口起点 := Vector2i.ZERO
var 歌名显示刷新 := true
var 待恢复专辑 := ""
var 待恢复歌曲 := ""
var 菜单栏: MenuBar
var 文件菜单: PopupMenu
var 显示菜单: PopupMenu
var 控制菜单: PopupMenu
const 控制菜单文字 := ["暂停", "播放", "上一首", "下一首", "提升音量", "降低音量", "乱序播放"]
var 系统音量任务: Thread
var 系统音量请求: Array[int] = []
var 显示专辑信息 := true
var 显示歌曲信息 := true
var 目录选择器: FileDialog
var 状态栏: Label
var 专辑标题: Label
var 页码: Label
var 前页按钮: Button
var 后页按钮: Button
var 工具栏: HBoxContainer
var 正在插入 := false
var 随机模式 := false
var 记住窗口 := false
var 保存的位置 := Vector2i.ZERO
var 保存的大小 := Vector2i(1100, 460)
var 上次窗口矩形 := Rect2i()
var 窗口保存倒计时 := 0.0

func _ready() -> void:
	# Native macOS FAST/REWIND keys need a small foreground bridge in Godot 4.3.
	if OS.has_feature("macos"):
		var bridge := "res://addons/macos_media_keys/media_keys.gdextension"
		if not GDExtensionManager.is_extension_loaded(bridge):
			if GDExtensionManager.load_extension(bridge) != GDExtensionManager.LOAD_STATUS_OK:
				push_warning("Mac 媒体键适配未加载；普通 F7/F9 仍可使用。")
	if ClassDB.class_exists("S4UMacBridge"):
		mac_bridge = ClassDB.instantiate("S4UMacBridge")
		library.mac_bridge = mac_bridge
	preferences = preload("res://player_preferences.gd").new()
	add_child(preferences)
	preferences.initialize(self)
	get_viewport().transparent_bg = true
	%Label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	%"显示唱片名".auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	# Decorative controls must not consume the primary-button drag gesture.
	$Panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$"Panel/歌名显示".mouse_filter = Control.MOUSE_FILTER_IGNORE
	$"Panel/歌名显示/Control".mouse_filter = Control.MOUSE_FILTER_IGNORE
	创建音乐库界面()
	加载游戏()
	应用文字显示设置()
	恢复窗口布局()
	$随机播放.set_pressed_no_signal(随机模式)
	控制菜单.set_item_checked(6, 随机模式)
	$TextureButton.set_pressed_no_signal(记住窗口)
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(保存并退出)
	刷新音乐库(false)

func 默认音乐库() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://音乐库")
	var base := OS.get_executable_path().get_base_dir()
	if OS.has_feature("macos") and base.ends_with(".app/Contents/MacOS"):
		base = base.get_base_dir().get_base_dir().get_base_dir()
	return base.path_join("音乐库")

func 创建音乐库界面() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var theme := Theme.new()
	theme.default_font = load("res://assets/font/(mod)Fusion-Pixel-12px.otf")
	theme.default_font_size = 24
	工具栏 = HBoxContainer.new()
	工具栏.theme = theme
	工具栏.position = Vector2(18, 10)
	工具栏.add_theme_constant_override("separation", 8)
	layer.add_child(工具栏)
	前页按钮 = 添加按钮("‹", func(): 切换页(-1))
	页码 = Label.new()
	页码.custom_minimum_size.x = 64
	页码.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	工具栏.add_child(页码)
	后页按钮 = 添加按钮("›", func(): 切换页(1))
	专辑标题 = Label.new()
	专辑标题.theme = theme
	专辑标题.position = Vector2(18, 52)
	专辑标题.size = Vector2(1064, 32)
	专辑标题.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	专辑标题.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	layer.add_child(专辑标题)
	状态栏 = Label.new()
	状态栏.theme = theme
	状态栏.position = Vector2(18, 426)
	状态栏.size = Vector2(1064, 30)
	状态栏.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	状态栏.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	layer.add_child(状态栏)
	创建菜单栏(layer)
	目录选择器 = FileDialog.new()
	目录选择器.title = "选择音乐库总文件夹（内含各专辑文件夹）"
	目录选择器.access = FileDialog.ACCESS_FILESYSTEM
	目录选择器.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	目录选择器.use_native_dialog = true
	目录选择器.dir_selected.connect(更换音乐库)
	add_child(目录选择器)
	preferences.build_ui()

func 创建菜单栏(layer: CanvasLayer) -> void:
	菜单栏 = MenuBar.new()
	菜单栏.prefer_global_menu = true
	菜单栏.name = "系统菜单栏"
	文件菜单 = PopupMenu.new()
	文件菜单.name = "文件"
	文件菜单.add_item("选择音乐库…", 0, KEY_MASK_META | KEY_O)
	文件菜单.add_item("打开音乐库文件夹", 1, KEY_MASK_META | KEY_MASK_SHIFT | KEY_O)
	文件菜单.add_item("刷新音乐库", 2, KEY_MASK_META | KEY_R)
	文件菜单.id_pressed.connect(文件菜单操作)
	文件菜单.about_to_popup.connect(取消拖动)
	菜单栏.add_child(文件菜单)
	显示菜单 = PopupMenu.new()
	显示菜单.name = "显示"
	显示菜单.add_check_item("显示专辑名称和歌曲数量", 0, KEY_MASK_META | KEY_MASK_SHIFT | KEY_A)
	显示菜单.add_check_item("显示歌曲序号和名称", 1, KEY_MASK_META | KEY_MASK_SHIFT | KEY_T)
	显示菜单.id_pressed.connect(切换文字显示)
	显示菜单.about_to_popup.connect(取消拖动)
	菜单栏.add_child(显示菜单)
	layer.add_child(菜单栏)

func 文件菜单操作(id: int) -> void:
	取消拖动()
	match id:
		0: 选择音乐库()
		1: 打开音乐库()
		2: 刷新音乐库()

func 切换文字显示(id: int) -> void:
	取消拖动()
	match id:
		0: 显示专辑信息 = not 显示专辑信息
		1: 显示歌曲信息 = not 显示歌曲信息
		_: return
	应用文字显示设置()
	储存游戏()

func 应用文字显示设置() -> void:
	专辑标题.visible = 显示专辑信息
	状态栏.visible = 显示歌曲信息
	显示菜单.set_item_checked(0, 显示专辑信息)
	显示菜单.set_item_checked(1, 显示歌曲信息)

func 更新歌曲文字() -> void:
	if 当前歌曲路径().is_empty():
		显示状态("0 / 0 · " + tr("暂无音乐"))
	else:
		显示状态("%d / %d · %s" % [当前播放序号 + 1, 专辑列表[当前专辑序号].tracks.size(), 当前播放歌名])

func 添加按钮(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	工具栏.add_child(button)
	return button

func 选择音乐库() -> void:
	取消拖动()
	目录选择器.current_dir = 音乐库路径
	目录选择器.popup_centered(Vector2i(850, 550))

func 打开音乐库() -> void:
	if DirAccess.dir_exists_absolute(音乐库路径):
		OS.shell_open(音乐库路径)
	else:
		显示状态("音乐库文件夹不存在，请重新选择。")

func 更换音乐库(path: String) -> void:
	音乐库路径 = path
	待恢复专辑 = ""
	待恢复歌曲 = ""
	刷新音乐库(false)

func 当前专辑路径() -> String:
	if 当前专辑序号 < 0 or 当前专辑序号 >= 专辑列表.size():
		return ""
	return 专辑列表[当前专辑序号].path

func 当前歌曲路径() -> String:
	if 当前专辑路径().is_empty():
		return ""
	var tracks: Array = 专辑列表[当前专辑序号].tracks
	if 当前播放序号 < 0 or 当前播放序号 >= tracks.size():
		return ""
	return tracks[当前播放序号].path

func 刷新音乐库(保留选择: bool = true) -> void:
	var album_path := 当前专辑路径() if 保留选择 else 待恢复专辑
	var track_path := 当前歌曲路径() if 保留选择 else 待恢复歌曲
	var resume: bool = 保留选择 and $音频播放.playing and not $音频播放.stream_paused
	var position_seconds: float = $音频播放.get_playback_position()
	停止播放()
	var result: Dictionary = library.scan(音乐库路径)
	专辑列表 = result.albums
	当前专辑序号 = -1
	当前播放序号 = 0
	当前页 = 0
	if 专辑列表.is_empty():
		当前播放歌名 = tr("请在音乐库内创建专辑文件夹并放入音频文件")
		专辑标题.text = tr("尚无专辑")
		显示状态(result.error if not result.error.is_empty() else tr("音乐库：") + 音乐库路径)
		更新唱片架()
		储存游戏()
		return
	var selected := 0
	for i in range(专辑列表.size()):
		if 专辑列表[i].path == album_path:
			selected = i
			break
	选择专辑(selected, false)
	var tracks: Array = 专辑列表[selected].tracks
	for i in range(tracks.size()):
		if tracks[i].path == track_path:
			当前播放序号 = i
			break
	if not tracks.is_empty():
		当前播放歌名 = tracks[当前播放序号].name
		更新歌曲文字()
	if resume and not tracks.is_empty():
		if 修改音频播放(当前播放序号) and 当前歌曲路径() == track_path:
			$音频播放.seek(minf(position_seconds, $音频播放.stream.get_length()))
	储存游戏()

func 选择专辑(index: int, autoplay: bool = true) -> void:
	if index < 0 or index >= 专辑列表.size():
		return
	停止播放()
	当前专辑序号 = index
	当前播放序号 = 0
	当前页 = index / PAGE_SIZE
	var album: Dictionary = 专辑列表[index]
	当前显示CD名 = album.name
	专辑标题.text = tr("%s  ·  %d 首") % [album.name, album.tracks.size()]
	专辑标题.tooltip_text = album.path
	$"唱片".texture = load("res://assets/texture/CD_front/" + COVERS[index % COVERS.size()] + ".png")
	当前播放歌名 = tr("此专辑暂无音乐") if album.tracks.is_empty() else album.tracks[0].name
	更新歌曲文字()
	if not album.error.is_empty():
		显示状态(album.error)
	if album.tracks.is_empty() and album.error.is_empty():
		显示状态(tr("在「%s」文件夹放入音频文件，然后刷新音乐库。") % album.name)
	更新唱片架()
	正在插入 = autoplay and not album.tracks.is_empty()
	$AnimationPlayer3.play("插入碟片")
	储存游戏()

func 停止播放() -> void:
	正在插入 = false
	$AnimationPlayer3.stop()
	$音频播放.stop()
	$音频播放.stream_paused = false
	$音频播放.stream = null

func CD已插入() -> void:
	if 正在插入:
		正在插入 = false
		修改音频播放(当前播放序号)

func 修改音频播放(index: int, direction: int = 1) -> bool:
	if 当前专辑路径().is_empty():
		return false
	var tracks: Array = 专辑列表[当前专辑序号].tracks
	var candidates: Array[int] = []
	for offset in range(tracks.size()):
		candidates.append(posmod(index + offset * direction, tracks.size()))
	return 播放候选曲目(candidates)

func 播放候选曲目(candidates: Array[int]) -> bool:
	if 当前专辑路径().is_empty():
		return false
	var tracks: Array = 专辑列表[当前专辑序号].tracks
	if tracks.is_empty():
		return false
	$音频播放.stop()
	$音频播放.stream_paused = false
	var skipped := 0
	for candidate in candidates:
		var stream: AudioStream = library.load_audio(tracks[candidate].path)
		if stream == null:
			skipped += 1
			continue
		当前播放序号 = candidate
		当前播放歌名 = tracks[candidate].name
		$"Panel/歌名显示".position.x = 0
		$音频播放.stream = stream
		$音频播放.play()
		更新歌曲文字()
		if skipped > 0:
			状态栏.tooltip_text += tr("（已跳过 %d 个无法播放的文件）") % skipped
		储存游戏()
		return true
	$音频播放.stream = null
	显示状态("此专辑的音频均无法播放，请检查文件是否损坏、受保护或已移动。")
	return false

func 随机播放() -> void:
	if 正在插入 or 当前专辑路径().is_empty():
		return
	var tracks: Array = 专辑列表[当前专辑序号].tracks
	var candidates: Array[int] = []
	for i in range(tracks.size()):
		if i != 当前播放序号:
			candidates.append(i)
	candidates.shuffle()
	# Try every alternative once; replay the current song only if none can play.
	if not tracks.is_empty():
		candidates.append(当前播放序号)
	播放候选曲目(candidates)

func 切换随机模式(enabled: bool) -> void:
	随机模式 = enabled
	$随机播放.set_pressed_no_signal(enabled)
	if 控制菜单 != null:
		控制菜单.set_item_checked(6, enabled)
	储存游戏()

func 上一首() -> void:
	if 正在插入:
		return
	if 随机模式:
		随机播放()
	else:
		修改音频播放(当前播放序号 - 1, -1)

func 下一首() -> void:
	if 正在插入:
		return
	if 随机模式:
		随机播放()
	else:
		修改音频播放(当前播放序号 + 1)

func 重播() -> void:
	修改音频播放(当前播放序号)

func 播放() -> void:
	if 正在插入:
		return
	if $音频播放.stream_paused:
		$音频播放.stream_paused = false
	elif $音频播放.playing:
		$音频播放.stream_paused = true
	else:
		修改音频播放(当前播放序号)

func 当前歌曲播放完成() -> void:
	下一首()

func 更新唱片架() -> void:
	隐藏专辑提示()
	for child in $"CD盘集合".get_children():
		$"CD盘集合".remove_child(child)
		child.queue_free()
	var start := 当前页 * PAGE_SIZE
	var end := mini(start + PAGE_SIZE, 专辑列表.size())
	# Add right to left so overlapping original disc artwork remains clickable.
	for i in range(end - 1, start - 1, -1):
		var disc = DiscScene.instantiate()
		disc.album_index = i
		disc.album_name = 专辑列表[i].name
		disc.cover_name = COVERS[i % COVERS.size()]
		disc.position = Vector2(-3 + (i - start) * 12, 0)
		$"CD盘集合".add_child(disc)
	var pages := maxi(1, ceili(float(专辑列表.size()) / PAGE_SIZE))
	页码.text = "%d / %d" % [当前页 + 1, pages]
	前页按钮.disabled = 当前页 == 0
	后页按钮.disabled = 当前页 >= pages - 1

func 切换页(direction: int) -> void:
	var pages := maxi(1, ceili(float(专辑列表.size()) / PAGE_SIZE))
	当前页 = clampi(当前页 + direction, 0, pages - 1)
	更新唱片架()

func 显示专辑提示(album_name: String) -> void:
	当前显示CD名 = album_name
	$"唱片名".show()

func 隐藏专辑提示() -> void:
	$"唱片名".hide()

func 显示状态(message: String) -> void:
	状态栏.text = tr(message)
	状态栏.tooltip_text = tr(message)

func _process(delta: float) -> void:
	处理系统音量任务()
	for button_name in 按键反馈:
		var feedback: Dictionary = 按键反馈[button_name]
		feedback.remaining = maxf(0.0, float(feedback.remaining) - delta)
		feedback.overlay.visible = feedback.remaining > 0
	更新系统播放状态(delta)
	# A release can arrive while a native dialog/menu owns focus. Do not rely only
	# on our old "dragging" flag; validate button state every frame as well.
	if 正在拖拽 and (not get_window().has_focus() or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		取消拖动()
	elif 正在拖拽:
		# Follow the desktop pointer even after it leaves the artwork/window.
		get_window().position = 窗口起点 + DisplayServer.mouse_get_position() - 拖拽起点
	if 记住窗口:
		var bounds := Rect2i(get_window().position, get_window().size)
		if bounds != 上次窗口矩形:
			上次窗口矩形 = bounds
			窗口保存倒计时 = 0.3
		elif 窗口保存倒计时 > 0:
			窗口保存倒计时 -= delta
			if 窗口保存倒计时 <= 0:
				储存游戏()
	if 歌名显示刷新:
		$"Panel/歌名显示".position.x -= 6.0 * delta
	$"唱片名".position = get_global_mouse_position()
	%"显示唱片名".text = 当前显示CD名
	%Label.text = 当前播放歌名
	if $音频播放.playing and not $音频播放.stream_paused:
		$AnimationPlayer2.play()
	else:
		$AnimationPlayer2.pause()

func _unhandled_input(event: InputEvent) -> void:
	# Controls consume their clicks before this handler; decorations allow dragging.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not event.canceled:
		正在拖拽 = true
		拖拽起点 = DisplayServer.mouse_get_position()
		窗口起点 = get_window().position

func _input(event: InputEvent) -> void:
	# Handle Space before a focused button receives ui_accept, including key-up.
	if event is InputEventKey and event.keycode == KEY_SPACE and not (event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed):
		get_viewport().set_input_as_handled()
		if event.pressed and not event.echo:
			键盘操作("toggle")
		return
	if mac_bridge != null and event is InputEventKey and event.keycode in [KEY_MEDIAPLAY, KEY_MEDIAPREVIOUS, KEY_MEDIANEXT]:
		# MediaPlayer remote commands own these keys; do not handle them twice.
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and (not event.pressed or event.canceled):
		取消拖动()
	if event is InputEventMouseMotion and 正在拖拽:
		# In particular, an ordinary touchpad move after a missed button-up must
		# terminate the old gesture BEFORE it is allowed to move the window.
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0 or not get_window().has_focus():
			取消拖动()
			return
		get_window().position = 窗口起点 + DisplayServer.mouse_get_position() - 拖拽起点

func _unhandled_key_input(event: InputEvent) -> void:
	if mac_bridge != null and event is InputEventKey and event.keycode in [KEY_MEDIAPLAY, KEY_MEDIAPREVIOUS, KEY_MEDIANEXT]:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.meta_pressed and event.keycode == KEY_COMMA:
		preferences.show_settings()
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed:
		return
	if event.keycode in [KEY_F7, KEY_MEDIAPREVIOUS] or event.physical_keycode == KEY_F7:
		键盘操作("previous")
	elif event.keycode in [KEY_F8, KEY_MEDIAPLAY] or event.physical_keycode == KEY_F8:
		键盘操作("toggle")
	elif event.keycode in [KEY_F9, KEY_MEDIANEXT] or event.physical_keycode == KEY_F9:
		键盘操作("next")
	else:
		return
	get_viewport().set_input_as_handled()

func 取消拖动() -> void:
	正在拖拽 = false

func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		取消拖动()

func 文字离开(_area: Area2D) -> void:
	if not 歌名显示刷新:
		return
	歌名显示刷新 = false
	await get_tree().create_timer(1).timeout
	歌名显示刷新 = true
	$"Panel/歌名显示".position.x = 30


func 记忆窗口布局(enabled: bool) -> void:
	记住窗口 = enabled
	储存游戏()

func 恢复窗口布局() -> void:
	var window := get_window()
	window.always_on_top = false
	if 记住窗口:
		window.size = 保存的大小
		window.position = 保存的位置
		# If a saved monitor is disconnected, keep the player reachable.
		var visible_on_screen := false
		for screen in range(DisplayServer.get_screen_count()):
			if DisplayServer.screen_get_usable_rect(screen).has_point(window.position + window.size / 2):
				visible_on_screen = true
				break
		if visible_on_screen:
			上次窗口矩形 = Rect2i(window.position, window.size)
			return
	else:
		缩放倍率 = 1.0
		调整窗口大小(false)
	var screen_rect := DisplayServer.screen_get_usable_rect(window.current_screen)
	window.position = screen_rect.position + (screen_rect.size - window.size) / 2
	上次窗口矩形 = Rect2i(window.position, window.size)

func 保存并退出() -> void:
	调用Mac({"op": "clear"})
	储存游戏()
	get_tree().quit()

func 修改窗口大小(_enabled: bool) -> void:
	get_window().borderless = not get_window().borderless
	调整窗口大小()

func 放大窗口() -> void:
	缩放倍率 = minf(1.5, 缩放倍率 + 0.25)
	调整窗口大小()

func 缩小窗口() -> void:
	缩放倍率 = maxf(0.5, 缩放倍率 - 0.25)
	调整窗口大小()

func 调整窗口大小(save: bool = true) -> void:
	get_window().size = Vector2i(Vector2(1100, 460) * 缩放倍率)
	if save:
		储存游戏()

func 储存游戏() -> void:
	var config := ConfigFile.new()
	config.set_value("library", "root", 音乐库路径)
	config.set_value("library", "album", 当前专辑路径())
	config.set_value("library", "track", 当前歌曲路径())
	config.set_value("settings", "scale", 缩放倍率)
	config.set_value("settings", "shuffle", 随机模式)
	config.set_value("window", "remember", 记住窗口)
	if 记住窗口:
		保存的位置 = get_window().position
		保存的大小 = get_window().size
	config.set_value("window", "position", 保存的位置)
	config.set_value("window", "size", 保存的大小)
	config.set_value("display", "album_info", 显示专辑信息)
	config.set_value("display", "track_info", 显示歌曲信息)
	if config.save(CONFIG_PATH) != OK:
		显示状态("无法保存设置；请检查用户数据目录的写入权限。")

func 加载游戏() -> void:
	音乐库路径 = 默认音乐库()
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		音乐库路径 = str(config.get_value("library", "root", 音乐库路径))
		待恢复专辑 = str(config.get_value("library", "album", ""))
		待恢复歌曲 = str(config.get_value("library", "track", ""))
		随机模式 = bool(config.get_value("settings", "shuffle", false))
		记住窗口 = bool(config.get_value("window", "remember", false))
		var position_value = config.get_value("window", "position", Vector2i.ZERO)
		var size_value = config.get_value("window", "size", Vector2i(1100, 460))
		if position_value is Vector2i:
			保存的位置 = position_value
		if size_value is Vector2i and size_value.x > 0 and size_value.y > 0:
			保存的大小 = size_value
		缩放倍率 = clampf(float(config.get_value("settings", "scale", 1.0)), 0.5, 1.5)
		显示专辑信息 = bool(config.get_value("display", "album_info", true))
		显示歌曲信息 = bool(config.get_value("display", "track_info", true))


func 调用Mac(request: Dictionary) -> Dictionary:
	if mac_bridge == null: return {}
	var response = JSON.parse_string(mac_bridge.call("exchange", JSON.stringify(request)))
	return response if response is Dictionary else {}

func 更新系统播放状态(delta: float) -> void:
	if mac_bridge == null: return
	media_poll -= delta
	if media_poll <= 0:
		media_poll = 0.1
		for command in 调用Mac({"op": "poll"}).get("commands", []):
			match command.get("action", ""):
				"settings": preferences.show_settings()
				"toggle": 键盘操作("toggle")
				"play": 键盘操作("play")
				"pause": 键盘操作("pause")
				"next": 键盘操作("next")
				"previous": 键盘操作("previous")
				"seek":
					if $音频播放.stream != null:
						$音频播放.seek(clampf(float(command.get("position", 0)), 0, $音频播放.stream.get_length()))
						last_media_state = ""
	var active: bool = $音频播放.stream != null and ($音频播放.playing or $音频播放.stream_paused)
	var playing: bool = active and not $音频播放.stream_paused
	var state := 当前歌曲路径() + str(active) + str(playing)
	# The system extrapolates elapsed time; do not reclaim media focus each second.
	if state == last_media_state: return
	last_media_state = state
	if active:
		调用Mac({"op": "publish", "title": 当前播放歌名,
			"album": 专辑列表[当前专辑序号].name if 当前专辑序号 >= 0 else "",
			"duration": $音频播放.stream.get_length(), "position": $音频播放.get_playback_position(), "playing": playing})
	else:
		调用Mac({"op": "clear"})

func 刷新界面语言() -> void:
	菜单栏.set_menu_title(0, tr("文件"))
	菜单栏.set_menu_title(1, tr("显示"))
	菜单栏.set_menu_title(2, tr("编辑"))
	菜单栏.set_menu_title(3, tr("控制"))
	for i in range(控制菜单文字.size()):
		控制菜单.set_item_text(i, tr(控制菜单文字[i]))
	for i in range(3): 文件菜单.set_item_text(i, tr(["选择音乐库…", "打开音乐库文件夹", "刷新音乐库"][i]))
	for i in range(2): 显示菜单.set_item_text(i, tr(["显示专辑名称和歌曲数量", "显示歌曲序号和名称"][i]))
	目录选择器.title = tr("选择音乐库总文件夹（内含各专辑文件夹）")
	$TextureButton.tooltip_text = tr("记住窗口位置和大小（重启后恢复）")
	$随机播放.tooltip_text = tr("随机播放模式：按下随机切歌，抬起顺序切歌")
	$上一首.tooltip_text = tr("上一首")
	$下一首.tooltip_text = tr("下一首")
	$播放.tooltip_text = tr("播放/暂停")
	$TextureButton3.tooltip_text = tr("放大")
	$TextureButton4.tooltip_text = tr("缩小")
	调用Mac({"op": "settings_title", "title": tr("设置…")})
	if 当前专辑序号 >= 0:
		var album: Dictionary = 专辑列表[当前专辑序号]
		专辑标题.text = tr("%s  ·  %d 首") % [album.name, album.tracks.size()]
		if album.tracks.is_empty(): 当前播放歌名 = tr("此专辑暂无音乐")
	else:
		专辑标题.text = tr("尚无专辑")
		当前播放歌名 = tr("请放入音乐文件")
	更新歌曲文字()

func _exit_tree() -> void:
	if 系统音量任务 != null and 系统音量任务.is_started():
		系统音量任务.wait_to_finish()
	调用Mac({"op": "clear"})


func 键盘操作(action: String) -> void:
	match action:
		"play":
			显示按键反馈("播放")
			if $音频播放.stream_paused or not $音频播放.playing:
				播放()
		"pause":
			显示按键反馈("播放")
			# Cancel pending insertion autoplay as well as pausing an active song.
			正在插入 = false
			if $音频播放.playing:
				$音频播放.stream_paused = true
		"previous":
			显示按键反馈("上一首")
			上一首()
		"toggle":
			显示按键反馈("播放")
			播放()
		"next":
			显示按键反馈("下一首")
			下一首()

func 显示按键反馈(button_name: String) -> void:
	if not 按键反馈.has(button_name):
		var button := get_node(button_name) as TextureButton
		if button == null or button.texture_pressed == null: return
		# Visual-only overlay: never emit a button signal or change toggle state.
		var overlay := TextureRect.new()
		overlay.texture = button.texture_pressed
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		overlay.stretch_mode = TextureRect.STRETCH_SCALE
		button.add_child(overlay)
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		按键反馈[button_name] = {"overlay": overlay, "remaining": 0.0}
	var feedback: Dictionary = 按键反馈[button_name]
	feedback.remaining = 0.16
	feedback.overlay.show()


func 创建控制菜单() -> void:
	# Called immediately after Edit is added; the native Window menu follows.
	控制菜单 = PopupMenu.new()
	控制菜单.name = "控制"
	for i in range(控制菜单文字.size()):
		if i == 6:
			控制菜单.add_check_item(tr(控制菜单文字[i]), i)
		else:
			控制菜单.add_item(tr(控制菜单文字[i]), i)
	控制菜单.set_item_checked(6, 随机模式)
	控制菜单.id_pressed.connect(控制菜单操作)
	控制菜单.about_to_popup.connect(取消拖动)
	菜单栏.add_child(控制菜单)

func 控制菜单操作(id: int) -> void:
	取消拖动()
	match id:
		0: 键盘操作("pause")
		1: 键盘操作("play")
		2: 键盘操作("previous")
		3: 键盘操作("next")
		4: 修改系统音量(1)
		5: 修改系统音量(-1)
		6: 切换随机模式(not 随机模式)

func 修改系统音量(direction: int) -> void:
	系统音量请求.append(1 if direction > 0 else -1)

func 处理系统音量任务() -> void:
	# Serialize read/modify/write operations, without blocking button animation
	# or audio decoding on the main thread while macOS changes output volume.
	if 系统音量任务 != null:
		if 系统音量任务.is_alive(): return
		var result: Dictionary = 系统音量任务.wait_to_finish()
		系统音量任务 = null
		if not result.get("ok", false):
			显示状态("无法调整系统音量；当前输出设备可能不支持系统音量控制。")
	if 系统音量请求.is_empty(): return
	var direction: int = 系统音量请求.pop_front()
	系统音量任务 = Thread.new()
	if 系统音量任务.start(执行系统音量调整.bind(direction)) != OK:
		系统音量任务 = null
		显示状态("无法调整系统音量；当前输出设备可能不支持系统音量控制。")

func 执行系统音量调整(direction: int) -> Dictionary:
	if not OS.has_feature("macos"): return {"ok": false}
	# Standard Additions controls macOS output volume, not any Godot audio bus.
	# The script is fixed except for our own +/-6 integer; no paths/user text.
	var script := """with timeout of 3 seconds
set currentVolume to output volume of (get volume settings)
set targetVolume to currentVolume + (%d)
if targetVolume > 100 then set targetVolume to 100
if targetVolume < 0 then set targetVolume to 0
set volume output volume targetVolume
if targetVolume > 0 then set volume without output muted
end timeout""" % (6 * direction)
	var output: Array = []
	var exit_code := OS.execute("/usr/bin/osascript", PackedStringArray(["-e", script]), output, true)
	return {"ok": exit_code == 0}
