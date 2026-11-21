extends Node

const CONFIG := "user://player_preferences.cfg"
const EXTRA_TRANSLATIONS = preload("res://ui_translations.gd")
const LANGUAGES := ["zh_CN", "zh_TW", "en", "ja", "fr", "de", "es", "it", "pt_BR", "ko"]
const LANGUAGE_NAMES := ["简体中文", "繁體中文", "English", "日本語", "Français", "Deutsch", "Español", "Italiano", "Português (Brasil)", "한국어"]
const PRESET_KEYS := ["平直", "蓝调", "Disco", "重低音", "摇滚", "古典", "人声", "自定义"]
const PRESETS := [
	[0,0,0,0,0,0,0,0,0,0], [2,3,2,0,-1,0,1,2,2,1],
	[4,4,2,0,-2,-1,1,3,4,3], [6,5,4,2,0,0,0,0,0,0],
	[4,3,1,-1,-2,0,2,3,4,3], [2,1,0,0,-1,-1,0,1,2,2],
	[-2,-2,-1,1,3,4,3,1,0,-1]
]
# Source messages are Chinese; music/folder names are never translated.
const MESSAGES := {
	"控制": ["Controls", "コントロール"],
	"暂停": ["Pause", "一時停止"],
	"播放": ["Play", "再生"],
	"提升音量": ["Increase Volume", "音量を上げる"],
	"降低音量": ["Decrease Volume", "音量を下げる"],
	"乱序播放": ["Shuffle", "シャッフル再生"],
	"无法调整系统音量；当前输出设备可能不支持系统音量控制。": ["Cannot change system volume. The current output device may not support system volume control.", "システム音量を変更できません。現在の出力機器が音量調整に対応していない可能性があります。"],
	"文件": ["File", "ファイル"], "显示": ["View", "表示"], "编辑": ["Edit", "編集"],
	"选择音乐库…": ["Choose Music Library…", "音楽ライブラリを選択…"],
	"打开音乐库文件夹": ["Open Music Library Folder", "ライブラリのフォルダを開く"],
	"刷新音乐库": ["Refresh Music Library", "ライブラリを更新"],
	"显示专辑名称和歌曲数量": ["Show Album Name and Track Count", "アルバム名と曲数を表示"],
	"显示歌曲序号和名称": ["Show Track Number and Title", "曲番号と曲名を表示"],
	"均衡器": ["Equalizer", "イコライザ"], "设置…": ["Settings…", "設定…"],
	"语言": ["Language", "言語"], "关闭": ["Close", "閉じる"],
	"启用均衡器": ["Enable Equalizer", "イコライザを有効にする"],
	"预设": ["Preset", "プリセット"], "前级增益": ["Preamp", "プリアンプ"],
	"保存为自定义": ["Save as Custom", "カスタムとして保存"],
	"重置为平直": ["Reset to Flat", "フラットに戻す"],
	"平直": ["Flat", "フラット"], "蓝调": ["Blues", "ブルース"],
	"重低音": ["Bass Boost", "低音強調"], "摇滚": ["Rock", "ロック"],
	"古典": ["Classical", "クラシック"], "人声": ["Vocal", "ボーカル"],
	"自定义": ["Custom", "カスタム"],
	"Disco": ["Disco", "ディスコ"],
	"调整后立即生效并自动保存。": ["Changes apply immediately and are saved automatically.", "変更はすぐに適用され、自動保存されます。"],
	"选择音乐库总文件夹（内含各专辑文件夹）": ["Choose Library Folder (Containing Album Folders)", "アルバムのフォルダを含む親フォルダを選択"],
	"暂无音乐": ["No music", "曲がありません"], "尚无专辑": ["No albums", "アルバムがありません"],
	"%s  ·  %d 首": ["%s  ·  %d tracks", "%s  ·  %d 曲"],
	"请放入音乐文件": ["Add music files", "音楽ファイルを追加してください"],
	"此专辑暂无音乐": ["This album is empty", "このアルバムには曲がありません"],
	"请在音乐库内创建专辑文件夹并放入音频文件": ["Create album folders and add audio files", "アルバムのフォルダを作り、音楽ファイルを追加してください"],
	"无法读取音乐库，请检查文件夹是否存在或重新选择。": ["Cannot read the library. Check the folder or choose another one.", "ライブラリを読み込めません。フォルダを確認するか、選び直してください。"],
	"无法读取此专辑文件夹": ["Cannot read this album folder", "このアルバムのフォルダを読み込めません"],
	"音乐库文件夹不存在，请重新选择。": ["Library folder is missing. Please choose it again.", "ライブラリのフォルダがありません。選び直してください。"],
	"音乐库：": ["Library: ", "ライブラリ："],
	"在「%s」文件夹放入音频文件，然后刷新音乐库。": ["Add audio files to “%s”, then refresh the library.", "「%s」に音楽ファイルを追加し、ライブラリを更新してください。"],
	"（已跳过 %d 个无法播放的文件）": [" (%d unplayable files skipped)", "（再生できないファイルを %d 個スキップしました）"],
	"此专辑的音频均无法播放，请检查文件是否损坏、受保护或已移动。": ["No playable audio in this album. Files may be damaged, protected, or missing.", "再生できる曲がありません。ファイルの破損、保護、移動を確認してください。"],
	"无法保存设置；请检查用户数据目录的写入权限。": ["Cannot save settings. Check the user data folder permissions.", "設定を保存できません。ユーザーデータフォルダの書き込み権限を確認してください。"],
	"记住窗口位置和大小（重启后恢复）": ["Remember window position and size", "ウィンドウの位置とサイズを記憶"],
	"随机播放模式：按下随机切歌，抬起顺序切歌": ["Shuffle: pressed = random, released = in order", "シャッフル：オンでランダム、オフで曲順どおり"],
	"上一首": ["Previous Track", "前の曲"], "下一首": ["Next Track", "次の曲"],
	"播放/暂停": ["Play/Pause", "再生／一時停止"],
	"放大": ["Larger", "拡大"], "缩小": ["Smaller", "縮小"]
}
var player: Node
var language := "zh_CN"
var enabled := false
var preset := 0
var gains: Array = PRESETS[0].duplicate()
var custom: Array = PRESETS[0].duplicate()
var preamp := 0.0
var custom_preamp := 0.0
var effect: AudioEffectEQ10
var bus := -1
var edit_menu: PopupMenu
var eq_menu: PopupMenu
var eq_window: Window
var settings_window: Window
var sliders: Array[HSlider] = []
var values: Array[Label] = []
var selector: OptionButton
var enable_button: CheckBox
var preamp_slider: HSlider
var preamp_value: Label
var language_selector: OptionButton
var localized: Array = []
var refreshing := false

func initialize(owner_player: Node) -> void:
	player = owner_player
	# Replace the old OST translations and register Chinese explicitly too.
	# Without an identity catalog, Chinese source messages fell back to English.
	TranslationServer.clear()
	for locale in LANGUAGES:
		var translation := Translation.new()
		translation.locale = locale
		for key in MESSAGES:
			var message: String = key
			if locale == "en":
				message = MESSAGES[key][0]
			elif locale == "ja":
				message = MESSAGES[key][1]
			elif locale != "zh_CN":
				var column: int = EXTRA_TRANSLATIONS.LOCALES.find(locale)
				message = EXTRA_TRANSLATIONS.MESSAGES[key][column]
			translation.add_message(key, message)
		TranslationServer.add_translation(translation)
	var cfg := ConfigFile.new()
	language = normalize_locale(OS.get_locale())
	if cfg.load(CONFIG) == OK:
		language = str(cfg.get_value("ui", "language", language))
		enabled = bool(cfg.get_value("eq", "enabled", false))
		preset = clampi(int(cfg.get_value("eq", "preset", 0)), 0, 7)
		gains = valid_gains(cfg.get_value("eq", "gains", gains))
		custom = valid_gains(cfg.get_value("eq", "custom", custom))
		preamp = clampf(float(cfg.get_value("eq", "preamp", 0.0)), -18.0, 0.0)
		custom_preamp = clampf(float(cfg.get_value("eq", "custom_preamp", 0.0)), -18.0, 0.0)
	language = normalize_locale(language)
	TranslationServer.set_locale(language)
	bus = AudioServer.get_bus_count()
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus, "S4U Equalizer")
	AudioServer.set_bus_send(bus, "Master")
	effect = AudioEffectEQ10.new()
	AudioServer.add_bus_effect(bus, effect)
	player.get_node("音频播放").bus = "S4U Equalizer"
	apply_equalizer()

func valid_gains(value: Variant) -> Array:
	var result: Array = PRESETS[0].duplicate()
	if value is Array and value.size() == 10:
		for i in range(10): result[i] = clampf(float(value[i]), -12.0, 12.0)
	return result

func build_ui() -> void:
	edit_menu = PopupMenu.new()
	edit_menu.name = "编辑"
	eq_menu = PopupMenu.new()
	eq_menu.name = "Equalizer"
	eq_menu.add_item(tr("均衡器") + "…", 100, KEY_MASK_META | KEY_E)
	eq_menu.add_separator()
	for i in range(PRESET_KEYS.size()): eq_menu.add_radio_check_item(tr(PRESET_KEYS[i]), i)
	eq_menu.id_pressed.connect(func(id: int):
		if id == 100: show_equalizer()
		else: select_preset(id))
	edit_menu.add_child(eq_menu)
	edit_menu.add_submenu_item(tr("均衡器"), "Equalizer")
	player.菜单栏.add_child(edit_menu)
	player.创建控制菜单()
	edit_menu.about_to_popup.connect(player.取消拖动)
	build_settings()
	build_equalizer()
	apply_language()
	refresh_equalizer()

func normalize_locale(value: String) -> String:
	var locale := value.replace("-", "_").to_lower()
	if locale.begins_with("zh"):
		return "zh_TW" if "hant" in locale or "_tw" in locale or "_hk" in locale or "_mo" in locale else "zh_CN"
	if locale.begins_with("pt"): return "pt_BR"
	var base := locale.get_slice("_", 0)
	return base if base in LANGUAGES else "en"

func make_window(logical_size: Vector2i) -> Window:
	var window := Window.new()
	window.set_meta("logical_size", logical_size)
	window.content_scale_size = logical_size
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.size = logical_size
	window.unresizable = false
	window.transient = true
	window.exclusive = true
	window.visible = false
	window.close_requested.connect(window.hide)
	add_child(window)
	if window.has_signal("dpi_changed"):
		window.connect("dpi_changed", func(): fit_dialog.call_deferred(window))
	return window

func fit_dialog(window: Window) -> void:
	# Godot's macOS window dimensions are backing pixels; match logical controls
	# to the target display's scale once, without double-scaling the content.
	var logical_size: Vector2i = window.get_meta("logical_size")
	var screen := window.current_screen
	var scale := maxf(1.0, DisplayServer.screen_get_scale(screen))
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var desired := Vector2i(Vector2(logical_size) * scale)
	var available := Vector2i(Vector2(usable.size) * 0.9)
	window.min_size = Vector2i(mini(logical_size.x, available.x), mini(logical_size.y, available.y))
	window.size = Vector2i(mini(desired.x, available.x), mini(desired.y, available.y))

func content(window: Window) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 24)
	var theme := Theme.new()
	theme.default_font = SystemFont.new()
	theme.default_font_size = 20
	margin.theme = theme
	window.add_child(margin)
	var scroll := ScrollContainer.new()
	margin.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 16)
	scroll.add_child(box)
	return box

func label(key: String, parent: Node) -> Label:
	var item := Label.new()
	item.text = tr(key)
	if key == "调整后立即生效并自动保存。":
		item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(item)
	localized.append([item, key])
	return item

func button(key: String, parent: Node, action: Callable) -> Button:
	var item := Button.new()
	item.text = tr(key)
	item.custom_minimum_size.y = 36
	item.pressed.connect(action)
	parent.add_child(item)
	localized.append([item, key])
	return item

func build_settings() -> void:
	settings_window = make_window(Vector2i(560, 300))
	var box := content(settings_window)
	label("语言", box)
	language_selector = OptionButton.new()
	language_selector.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	language_selector.custom_minimum_size.y = 38
	for title in LANGUAGE_NAMES: language_selector.add_item(title)
	box.add_child(language_selector)
	language_selector.item_selected.connect(func(index: int):
		language = LANGUAGES[index]
		TranslationServer.set_locale(language)
		apply_language()
		save())
	button("关闭", box, settings_window.hide)

func build_equalizer() -> void:
	eq_window = make_window(Vector2i(900, 600))
	var box := content(eq_window)
	enable_button = CheckBox.new()
	enable_button.text = tr("启用均衡器")
	localized.append([enable_button, "启用均衡器"])
	box.add_child(enable_button)
	enable_button.toggled.connect(func(value: bool):
		if refreshing: return
		enabled = value
		apply_equalizer()
		save())
	var row := HBoxContainer.new()
	box.add_child(row)
	label("预设", row)
	selector = OptionButton.new()
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key in PRESET_KEYS: selector.add_item(tr(key))
	row.add_child(selector)
	selector.item_selected.connect(select_preset)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 12)
	box.add_child(grid)
	for i in range(10):
		var frequency: float = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000][i]
		var frequency_label := Label.new()
		frequency_label.text = ("%.1f kHz" % (frequency / 1000.0)) if frequency >= 1000 else ("%d Hz" % frequency)
		grid.add_child(frequency_label)
		var slider := HSlider.new()
		slider.min_value = -12
		slider.max_value = 12
		slider.step = 0.5
		slider.custom_minimum_size = Vector2(170, 32)
		grid.add_child(slider)
		sliders.append(slider)
		var value_label := Label.new()
		value_label.custom_minimum_size.x = 60
		grid.add_child(value_label)
		values.append(value_label)
		slider.value_changed.connect(func(value: float):
			if refreshing: return
			gains[i] = value
			preset = 7
			custom = gains.duplicate()
			custom_preamp = preamp
			apply_equalizer()
			refresh_equalizer()
			save())
	label("前级增益", box)
	var preamp_row := HBoxContainer.new()
	box.add_child(preamp_row)
	preamp_slider = HSlider.new()
	preamp_slider.min_value = -18
	preamp_slider.max_value = 0
	preamp_slider.step = 0.5
	preamp_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preamp_slider.custom_minimum_size.y = 32
	preamp_row.add_child(preamp_slider)
	preamp_value = Label.new()
	preamp_value.custom_minimum_size.x = 80
	preamp_row.add_child(preamp_value)
	preamp_slider.value_changed.connect(func(value: float):
		if refreshing: return
		preamp = value
		preset = 7
		custom = gains.duplicate()
		custom_preamp = preamp
		apply_equalizer()
		refresh_equalizer()
		save())
	var actions := HBoxContainer.new()
	box.add_child(actions)
	button("保存为自定义", actions, func():
		custom = gains.duplicate()
		custom_preamp = preamp
		preset = 7
		refresh_equalizer()
		save())
	button("重置为平直", actions, func(): select_preset(0))
	label("调整后立即生效并自动保存。", box)
	button("关闭", box, eq_window.hide)

func select_preset(index: int) -> void:
	preset = index
	gains = custom.duplicate() if index == 7 else PRESETS[index].duplicate()
	# Provide headroom for boosted presets rather than clipping the output.
	preamp = custom_preamp if index == 7 else -maxf(0.0, float(gains.max()))
	enabled = true
	apply_equalizer()
	refresh_equalizer()
	save()

func apply_equalizer() -> void:
	if effect == null: return
	for i in range(10): effect.set_band_gain_db(i, gains[i])
	AudioServer.set_bus_effect_enabled(bus, 0, enabled)
	player.get_node("音频播放").volume_db = preamp if enabled else 0.0

func refresh_equalizer() -> void:
	refreshing = true
	enable_button.set_pressed_no_signal(enabled)
	selector.select(preset)
	for i in range(10):
		sliders[i].set_value_no_signal(gains[i])
		values[i].text = "%+.1f dB" % gains[i]
	preamp_slider.set_value_no_signal(preamp)
	preamp_value.text = "%+.1f dB" % preamp
	for i in range(8): eq_menu.set_item_checked(i + 2, i == preset)
	refreshing = false

func apply_language() -> void:
	for item in localized: item[0].text = tr(item[1])
	settings_window.title = tr("设置…")
	eq_window.title = tr("均衡器")
	language_selector.select(LANGUAGES.find(language))
	for i in range(PRESET_KEYS.size()):
		selector.set_item_text(i, tr(PRESET_KEYS[i]))
		eq_menu.set_item_text(i + 2, tr(PRESET_KEYS[i]))
	eq_menu.set_item_text(0, tr("均衡器") + "…")
	edit_menu.set_item_text(0, tr("均衡器"))
	player.刷新界面语言()

func show_settings() -> void:
	player.取消拖动()
	settings_window.current_screen = player.get_window().current_screen
	fit_dialog(settings_window)
	settings_window.popup_centered(settings_window.size)

func show_equalizer() -> void:
	player.取消拖动()
	eq_window.current_screen = player.get_window().current_screen
	fit_dialog(eq_window)
	eq_window.popup_centered(eq_window.size)

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "language", language)
	cfg.set_value("eq", "enabled", enabled)
	cfg.set_value("eq", "preset", preset)
	cfg.set_value("eq", "gains", gains)
	cfg.set_value("eq", "custom", custom)
	cfg.set_value("eq", "preamp", preamp)
	cfg.set_value("eq", "custom_preamp", custom_preamp)
	cfg.save(CONFIG)

func _exit_tree() -> void:
	if bus >= 0 and bus < AudioServer.get_bus_count(): AudioServer.remove_bus(bus)
