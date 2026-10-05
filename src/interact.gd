# Anything the player can press E on. hold_time > 0 means "hold E".
extends StaticBody3D

var prompt := "Use"
var hold_time := 0.0
var action := Callable()


func interact(_who: Node) -> void:
	if action.is_valid():
		action.call()
