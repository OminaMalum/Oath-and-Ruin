class_name EconomyDef
extends Resource
## Gold rules for a match: what pays, how much, and what the shop sells.
## The match controller pays out; the unit spends.

@export_group("Income")
@export var start_gold: float = 300.0
## Every champion, alive or dead.
@export var per_second: float = 2.0
## Split between the enemy champions near a dying minion.
@export var minion_share: float = 6.0
## On top, to the champion that lands the killing blow on a minion.
@export var last_hit: float = 18.0
@export var breaker_share: float = 20.0
@export var breaker_last_hit: float = 40.0
@export var kill: float = 200.0
## To each other champion of the killer's team near the kill.
@export var assist: float = 75.0
## To every champion of the team that destroys a structure.
@export var structure: float = 150.0
## To each champion of the capturing team near the beast.
@export var beast: float = 100.0
@export_group("Shop")
## Buy within this distance of the own fountain, or while dead.
@export var shop_radius: float = 6.0
@export var slots: int = 4
## Recall (T): stand still this long to return to the fountain. Moving, any
## cast, a hit or a stun cancels it.
@export var recall_time: float = 4.0
## Index in this list is the item's number on the shop panel and on the wire.
@export var items: Array[ItemDef] = []
