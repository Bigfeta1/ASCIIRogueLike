extends Control

enum Tab { STATS, SKILLS, INVENTORY }

var _tab: Tab = Tab.STATS

func _ready() -> void:
	$TabBar/StatsButton.pressed.connect(_set_tab.bind(Tab.STATS))
	$TabBar/SkillsButton.pressed.connect(_set_tab.bind(Tab.SKILLS))
	$TabBar/InventoryButton.pressed.connect(_set_tab.bind(Tab.INVENTORY))
	_set_tab(Tab.STATS)

func _set_tab(tab: Tab) -> void:
	_tab = tab
	$StatsPanel.visible = _tab == Tab.STATS
	$SkillsPanel.visible = _tab == Tab.SKILLS
	$InventoryPanel.visible = _tab == Tab.INVENTORY
