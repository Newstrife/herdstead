class_name ZoneRef
extends RefCounted
## A zone together with the building (machine) it stands in, as
## OfficeFrame.find_zone() answers: the machine is what a zone pick shows, and
## the sign's tooltip reads its siblings, so they travel together.

var building: BuildingModel
var zone_model: ZoneModel


func _init(in_building: BuildingModel, at_zone: ZoneModel) -> void:
	building = in_building
	zone_model = at_zone


## What the zone's sign tooltip says: `repo · checkout · worktree of 3`, each
## part only when it has one; a zone with none of them says so. Pure (models
## only), here so the HUD can say it with no dependency on the world's tooltip
## reader (OfficeQuestionTips.sign_text() asks this).
func sign_text() -> String:
	var parts := PackedStringArray()
	if not zone_model.repo.is_empty():
		parts.append(zone_model.repo)
	if not zone_model.worktree.is_empty():
		parts.append(zone_model.worktree)
	if not zone_model.mezzanine_of.is_empty():
		for other in building.zones:
			if other.key == zone_model.mezzanine_of:
				parts.append("worktree of " + other.number_text())
	return "No repository" if parts.is_empty() else " · ".join(parts)
