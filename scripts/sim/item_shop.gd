class_name ItemShop
extends RefCounted
## Build paths through the shop, shared by bots and the shop panel's
## suggestions. Shop numbers are 1-based indices into Unit.ECONOMY.items.


## Which economy a match uses; call before units spawn. Every peer must agree.
static func use_adventurer(on: bool) -> void:
	Unit.ECONOMY = Unit.ADVENTURER_ECONOMY if on else Unit.CLASSIC_ECONOMY


static func adventurer() -> bool:
	return Unit.ECONOMY == Unit.ADVENTURER_ECONOMY


static func index_of(id: StringName) -> int:
	for n in Unit.ECONOMY.items.size():
		if Unit.ECONOMY.items[n].id == id:
			return n + 1
	return 0


## The champion's buy order for the catalog in use.
static func build_for(unit: Unit) -> Array[StringName]:
	return unit.def.adventurer_build if adventurer() else unit.def.item_build


## The next shop number along the champion's build (0: the build is done).
## A finished item comes whole when its parts are owned or the gold covers
## the rest; otherwise its first missing part comes next. It never skips
## ahead to a later, cheaper item.
static func next_step(unit: Unit) -> int:
	for id in build_for(unit):
		var idx := index_of(id)
		if idx == 0:
			continue
		var it: ItemDef = Unit.ECONOMY.items[idx - 1]
		if it.kind != ItemDef.Kind.COMPONENT and unit.items.has(it):
			continue
		var plan := unit.purchase_plan(idx)
		var consume: Array = plan.consume
		if consume.size() == it.recipe.size() or unit.gold >= plan.price:
			return idx
		var owned: Array = consume.map(func(n: int) -> ItemDef: return unit.items[n])
		for part: ItemDef in it.recipe:
			if part in owned:
				owned.erase(part)
			else:
				return index_of(part.id)
		return idx
	return 0


## Gold the next step costs, INF when there is none or no slot for it.
static func next_step_price(unit: Unit) -> float:
	var idx := next_step(unit)
	if idx == 0:
		return INF
	var plan := unit.purchase_plan(idx)
	if unit.items.size() - (plan.consume as Array).size() >= Unit.ECONOMY.slots:
		return INF
	return plan.price
