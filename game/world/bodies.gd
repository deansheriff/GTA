class_name Bodies
extends RefCounted
## People are solid too (owner request 2026-10-15: "add collision for vehicles and humans").
## Each frame, after everyone has moved:
##  - people (the crowd, you on foot) are pushed out of every vehicle: traffic, your danfo
##    (driven or parked) and other players' vehicles; a moving danfo shoves pedestrians aside,
##  - people don't walk through each other (you, the crowd, other players on foot).
## Vehicles against vehicles live in traffic.gd and story/street_clash.gd.

const PERSON_HALF := Vector2(11, 8) # a walker's footprint as a small box
const PERSON_R := 13.0


static func resolve(main: Node2D) -> void:
	var map: MapData = main.map
	var people: Array = main.crowd.people.duplicate()
	if main.mode == "walking":
		people.append(main.player)
	var vehicles: Array = []
	for v in main.traffic.vehicles:
		vehicles.append(v["node"])
	vehicles.append(main.danfo)
	if main.street:
		vehicles.append_array(main.street.garage.nodes)
	for id in main.remotes:
		var r: Dictionary = main.remotes[id]
		if r["mode"] == 1 and (r["danfo"] as Node2D).visible:
			vehicles.append(r["danfo"])
	# People out of vehicles.
	for p: Node2D in people:
		for veh: Node2D in vehicles:
			if p.position.distance_squared_to(veh.position) > 110.0 * 110.0:
				continue
			var half := Vector2(veh.LENGTH, veh.WIDTH) * 0.5
			var mtv := Collide.obb_mtv(p.position, 0.0, PERSON_HALF, veh.position, veh.heading, half)
			if mtv == Vector2.ZERO:
				continue
			var to := p.position + mtv
			if map.is_blocked(to):
				# Against a wall: try sliding out along the vehicle's side instead.
				var side := Vector2.from_angle(veh.heading + PI / 2.0)
				to = p.position + side * signf(side.dot(p.position - veh.position) + 0.001) * mtv.length()
			if not map.is_blocked(to):
				p.position = to
				if p != main.player and p.get("target") != null:
					p.target = Vector2.INF # the pedestrian stops and rethinks their route
	# People apart from each other (cheap: only nearby pairs matter).
	var solid: Array = people.duplicate()
	for id in main.remotes:
		var r: Dictionary = main.remotes[id]
		if r["mode"] == 0 and (r["walker"] as Node2D).visible:
			solid.append(r["walker"])
	var remote_start: int = people.size()
	for i in people.size():
		var a: Node2D = people[i]
		for j in range(i + 1, solid.size()):
			var b: Node2D = solid[j]
			var d := a.position - b.position
			var l2 := d.length_squared()
			if l2 >= (PERSON_R * 2.0) * (PERSON_R * 2.0) or l2 < 0.0001:
				continue
			var l := sqrt(l2)
			var push := d / l * (PERSON_R * 2.0 - l)
			if j >= remote_start:
				_nudge(a, push, map) # other players' positions come from the server
			else:
				_nudge(a, push * 0.5, map)
				_nudge(b, -push * 0.5, map)


static func _nudge(p: Node2D, by: Vector2, map: MapData) -> void:
	if not map.is_blocked(p.position + by):
		p.position += by
