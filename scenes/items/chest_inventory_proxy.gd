extends Node

# Lightweight inventory proxy for viewing/taking items from a carried chest.
# Mirrors the interface loot_modal expects from a CharacterInventory node.
# On remove_item, syncs back to the owning CharacterInventory's chest_contents.

var items: Array[String] = []
var _owner_inventory: Node
var _owner_uid: int


func init(owner_inventory: Node, owner_uid: int, contents: Array) -> void:
	_owner_inventory = owner_inventory
	_owner_uid = owner_uid
	for id in contents:
		items.append(id as String)


func remove_item(id: String) -> bool:
	var idx := items.find(id)
	if idx == -1:
		return false
	items.remove_at(idx)
	_owner_inventory.chest_contents[_owner_uid] = items.duplicate()
	return true
