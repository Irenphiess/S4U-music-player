extends Control

var album_index := -1
var album_name := ""
var cover_name := "碧色晴海风"

func _ready() -> void:
	$"显示".texture = load("res://assets/texture/CD_side/" + cover_name + "side.png")
	$Button.tooltip_text = album_name

func 点击() -> void:
	get_parent().get_parent().选择专辑(album_index)

func 鼠标进入() -> void:
	$AnimationPlayer.play("选中")
	get_parent().get_parent().显示专辑提示(album_name)

func 鼠标离开() -> void:
	$AnimationPlayer.play("复原")
	get_parent().get_parent().隐藏专辑提示()

func _process(_delta: float) -> void:
	visible = album_index != get_parent().get_parent().当前专辑序号
