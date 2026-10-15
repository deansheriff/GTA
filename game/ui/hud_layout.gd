class_name HudLayout
extends RefCounted
## Pinning HUD controls to screen corners. Setting `position` on a bottom-right-anchored control
## before the screen has a size left the action button mostly off-screen on phones (owner report:
## "can't get back into my vehicle"); offsets from the anchor stay correct at every size.


static func pin_bottom_right(c: Control, right: float, bottom: float) -> void:
	c.anchor_left = 1.0
	c.anchor_top = 1.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN
	c.offset_right = -right
	c.offset_bottom = -bottom
	var m := c.get_combined_minimum_size()
	c.offset_left = -right - maxf(c.custom_minimum_size.x, m.x)
	c.offset_top = -bottom - maxf(c.custom_minimum_size.y, m.y)
