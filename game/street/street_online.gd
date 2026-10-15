class_name StreetOnline
extends Node
## Online street features (M11): races, crews, co-op jobs, boxing, trading, photos and the
## online Lagos Gist feed. (Filled in by M11.)

var host: StreetHost
var main: Node2D
var crew_tag := ""


func setup(h: StreetHost) -> void:
	host = h
	main = h.main


func tick(_dt: float) -> void:
	pass


func gist_online_into(_phone: Control) -> void:
	pass
