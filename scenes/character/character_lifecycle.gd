extends Node

# CharacterLifecycle is a transition controller, not a state store.
# It owns cross-component state transitions and their side effects.
# State itself lives in CharacterAI (life_state, behavior_state).
#
# Rule: only use this node when a transition crosses multiple sibling components.
# Purely internal AI behavior transitions (patrol, investigate, return) stay in CharacterAI.

signal died(character: Node)
signal knocked_out(character: Node)
signal revived(character: Node)
signal entered_combat(character: Node)

var _occupancy_map: Node

func setup(occupancy_map: Node) -> void:
	_occupancy_map = occupancy_map


# Called by the attacker's CharacterCombat when target HP reaches 0.
func die(target: Node) -> void:
	var ai := target.get_node_or_null("CharacterAI")
	if ai == null or ai.life_state == ai.LifeState.DEAD:
		return
	ai.life_state = ai.LifeState.DEAD
	_disable_active_components(target, ai)
	var movement := target.get_node("CharacterMovement")
	_occupancy_map.unregister_solid(movement.grid_pos, target)
	_occupancy_map.register_passable(movement.grid_pos, target)
	if target.corpse_item_id != "":
		target.get_node("CharacterInventory").add_item(target.corpse_item_id)
	target.get_node("CharacterSprite").set_defeated(target.defeated_sprite)
	died.emit(target)


# Called when a character is rendered unconscious but not dead.
func knock_out(target: Node) -> void:
	var ai := target.get_node_or_null("CharacterAI")
	if ai == null or ai.life_state != ai.LifeState.ALIVE:
		return
	ai.life_state = ai.LifeState.KNOCKED_OUT
	_disable_active_components(target, ai)
	var movement := target.get_node("CharacterMovement")
	_occupancy_map.unregister_solid(movement.grid_pos, target)
	_occupancy_map.register_passable(movement.grid_pos, target)
	knocked_out.emit(target)


# Called by CharacterMovement when the player bumps a hostile enemy.
# This crosses components (Movement detects the bump, AI owns the state)
# so it belongs here rather than in either sibling.
func enter_combat(target: Node) -> void:
	var ai := target.get_node_or_null("CharacterAI")
	if ai == null or ai.life_state != ai.LifeState.ALIVE:
		return
	if ai.behavior_state == ai.BehaviorState.COMBAT:
		return
	ai.behavior_state = ai.BehaviorState.COMBAT
	entered_combat.emit(target)


# Restores a non-alive life_state from serialized data without side effects.
# Does not add corpse items (already in serialized inventory) or call set_defeated
# (EnemyConfigurator handles sprite and splatter restoration separately).
func restore_incapacitated(target: Node, saved_life_state: int) -> void:
	var ai := target.get_node_or_null("CharacterAI")
	if ai == null or saved_life_state == ai.LifeState.ALIVE:
		return
	ai.life_state = saved_life_state
	_disable_active_components(target, ai)
	var movement := target.get_node("CharacterMovement")
	_occupancy_map.unregister_solid(movement.grid_pos, target)
	_occupancy_map.register_passable(movement.grid_pos, target)


func _disable_active_components(target: Node, ai: Node) -> void:
	target.get_node("CharacterVision").clear()
	ai.set_process(false)
	target.get_node("CharacterMovement").set_process(false)
	target.get_node("CharacterCombat").set_process(false)
