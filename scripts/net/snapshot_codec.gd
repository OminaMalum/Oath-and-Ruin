class_name SnapshotCodec
extends RefCounted
## Compact binary snapshots (server -> client), so a full 3v3 match fits in
## one network packet. The old format (var_to_bytes of a Dictionary of
## Arrays) measured about 150 bytes per unit and 3.9 KB at the 26-unit peak of
## a bot match, which ENet splits into three fragments: losing any one of them
## loses the whole snapshot. This one quantizes every value and leaves out
## blocks that are empty (no cast, no slow, alive), about 15 to 40 bytes a unit.
##
## Layout (little endian):
##   header  u8 version, u32 server tick, u32 ack (last client tick the
##           server applied for the receiving player; 0 for none), u16 count
##   unit    u16 id, u8 flags, u8 blocks, s16 x3 position (cm), u16 yaw,
##           u16 health, then each block present in `blocks`, in bit order.
## Decoding gives the same per-unit Array the client used before (see FIELDS).

const VERSION := 3
## Packet budget: ENet's default MTU in Godot 4.7.2 (thirdparty/enet/enet.h,
## ENET_HOST_DEFAULT_MTU). Godot warns above it for unreliable sends.
const MTU := 1392

## Indices of the decoded per-unit Array.
enum { POS, YAW, HEALTH, ALIVE, PHASE, SLOT, CAST_TIMER, CAST_TARGET, COOLDOWNS, SLOW, SLOW_TIMER,
	RESPAWN, STUN, DASH_TIMER, DASH_VEL, LEVEL, UPGRADE, MAX_HEALTH, GOLD, ITEMS, RECALL, FIELD_COUNT }

const F_ALIVE := 1
## Bits 1-2: cast phase. Bits 3-4: upgrade option picked for slot 1 (0 none).

const B_CAST := 1        # s8 slot, u16 timer, s16 x3 target cm
const B_COOLDOWNS := 2   # u8 n, u16 timer x n
const B_SLOW := 4        # u8 amount /255, u16 timer
const B_RESPAWN := 8     # u16 timer
const B_STUN := 16       # u16 timer
const B_DASH := 32       # u16 timer, s16 x2 velocity cm/s
const B_PROGRESS := 64   # u8 level, u16 max health, u16 gold, u8 item bits
const B_RECALL := 128    # u16 timer

## Timers are u16 in 1/600 s, rounded up: ten steps per 60 Hz tick, so a
## timer ends on the same tick on both sides, and up to 109 s.
const TIMER_SCALE := 600.0
const POS_SCALE := 100.0     # 1 cm, range +-327 m (the lane map is about +-70 m)
const YAW_SCALE := 65535.0 / TAU


static func _s16(v: float) -> int:
	return clampi(roundi(v), -32768, 32767)


static func _u16(v: float) -> int:
	return clampi(roundi(v), 0, 65535)


static func _timer(seconds: float) -> int:
	return clampi(ceili(seconds * TIMER_SCALE - 0.01), 0, 65535)


static func _put_vec(b: StreamPeerBuffer, v: Vector3) -> void:
	b.put_16(_s16(v.x * POS_SCALE))
	b.put_16(_s16(v.y * POS_SCALE))
	b.put_16(_s16(v.z * POS_SCALE))


static func _get_vec(b: StreamPeerBuffer) -> Vector3:
	var x := b.get_16() / POS_SCALE
	var y := b.get_16() / POS_SCALE
	return Vector3(x, y, b.get_16() / POS_SCALE)


## The upgrade option (1 or 2) a unit picked for slot 1, 0 for none.
static func upgrade_index(u: Unit) -> int:
	var a: Variant = u.slot_overrides.get(1)
	if a == null:
		return 0
	return u.upgrade_options().find(a) + 1


## Unit records, shared by every receiver; prepend a header per receiver.
static func encode_units(units: Array[Unit]) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	for u in units:
		b.put_u16(u.net_id)
		var champion := u.def.kind == ChampionDef.Kind.CHAMPION
		var flags := (F_ALIVE if u.alive else 0) | (int(u.cast_phase) << 1) | (upgrade_index(u) << 3)
		var blocks := 0
		if u.cast_phase != Unit.CastPhase.NONE:
			blocks |= B_CAST
		if champion and not u.cooldowns.is_empty():
			blocks |= B_COOLDOWNS
		if u.slow_timer > 0.0:
			blocks |= B_SLOW
		if not u.alive and u.respawn_timer > 0.0:
			blocks |= B_RESPAWN
		if u.stun_timer > 0.0:
			blocks |= B_STUN
		if u.dash_timer > 0.0:
			blocks |= B_DASH
		if champion or not is_equal_approx(u.max_health, u.def.max_health):
			blocks |= B_PROGRESS
		if u.recall_timer > 0.0:
			blocks |= B_RECALL
		b.put_u8(flags)
		b.put_u8(blocks)
		_put_vec(b, u.global_position)
		b.put_u16(_u16(wrapf(u.aim_yaw, 0.0, TAU) * YAW_SCALE))
		# Never round a living unit down to 0 health on the wire.
		b.put_u16(maxi(_u16(u.health), 1 if u.alive else 0))
		if blocks & B_CAST:
			b.put_8(clampi(u.cast_slot, -1, 127))
			b.put_u16(_timer(u.cast_timer))
			_put_vec(b, u.cast_target)
		if blocks & B_COOLDOWNS:
			b.put_u8(mini(u.cooldowns.size(), 255))
			for i in mini(u.cooldowns.size(), 255):
				b.put_u16(_timer(u.cooldowns[i]))
		if blocks & B_SLOW:
			b.put_u8(clampi(roundi(u.slow_amount * 255.0), 0, 255))
			b.put_u16(_timer(u.slow_timer))
		if blocks & B_RESPAWN:
			b.put_u16(_timer(u.respawn_timer))
		if blocks & B_STUN:
			b.put_u16(_timer(u.stun_timer))
		if blocks & B_DASH:
			b.put_u16(_timer(u.dash_timer))
			b.put_16(_s16(u.dash_velocity.x * POS_SCALE))
			b.put_16(_s16(u.dash_velocity.z * POS_SCALE))
		if blocks & B_PROGRESS:
			b.put_u8(clampi(u.level, 0, 255))
			b.put_u16(_u16(u.max_health))
			b.put_u16(clampi(floori(u.gold), 0, 65535))
			b.put_u8(u.item_mask() & 255)
		if blocks & B_RECALL:
			b.put_u16(_timer(u.recall_timer))
	return b.data_array


static func encode(tick: int, ack: int, count: int, unit_bytes: PackedByteArray) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(VERSION)
	b.put_u32(tick)
	b.put_u32(maxi(ack, 0))
	b.put_u16(count)
	b.put_data(unit_bytes)
	return b.data_array


## Returns {tick, ack, units: {id: Array}}, or {} for a malformed packet.
static func decode(bytes: PackedByteArray) -> Dictionary:
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	if bytes.size() < 11 or b.get_u8() != VERSION:
		return {}
	var tick := b.get_u32()
	var ack := b.get_u32()
	var count := b.get_u16()
	var units := {}
	for n in count:
		if b.get_available_bytes() < 14:
			return {}
		var id := b.get_u16()
		var flags := b.get_u8()
		var blocks := b.get_u8()
		var s := []
		s.resize(FIELD_COUNT)
		s[POS] = _get_vec(b)
		s[YAW] = wrapf(b.get_u16() / YAW_SCALE, -PI, PI)
		s[HEALTH] = float(b.get_u16())
		s[ALIVE] = flags & F_ALIVE != 0
		s[PHASE] = (flags >> 1) & 3
		s[UPGRADE] = (flags >> 3) & 3
		s[SLOT] = -1
		s[CAST_TIMER] = 0.0
		s[CAST_TARGET] = s[POS]
		s[COOLDOWNS] = PackedFloat32Array()
		s[SLOW] = 0.0
		s[SLOW_TIMER] = 0.0
		s[RESPAWN] = 0.0
		s[STUN] = 0.0
		s[DASH_TIMER] = 0.0
		s[DASH_VEL] = Vector3.ZERO
		s[LEVEL] = -1
		s[MAX_HEALTH] = -1.0
		s[GOLD] = -1.0
		s[ITEMS] = -1
		s[RECALL] = 0.0
		if b.get_available_bytes() < _blocks_size(blocks):
			return {}
		if blocks & B_CAST:
			s[SLOT] = b.get_8()
			s[CAST_TIMER] = b.get_u16() / TIMER_SCALE
			s[CAST_TARGET] = _get_vec(b)
		if blocks & B_COOLDOWNS:
			var cd := PackedFloat32Array()
			cd.resize(b.get_u8())
			if b.get_available_bytes() < cd.size() * 2 + _blocks_size(blocks & ~(B_CAST | B_COOLDOWNS)):
				return {}
			for i in cd.size():
				cd[i] = b.get_u16() / TIMER_SCALE
			s[COOLDOWNS] = cd
		if blocks & B_SLOW:
			s[SLOW] = b.get_u8() / 255.0
			s[SLOW_TIMER] = b.get_u16() / TIMER_SCALE
		if blocks & B_RESPAWN:
			s[RESPAWN] = b.get_u16() / TIMER_SCALE
		if blocks & B_STUN:
			s[STUN] = b.get_u16() / TIMER_SCALE
		if blocks & B_DASH:
			s[DASH_TIMER] = b.get_u16() / TIMER_SCALE
			var vx := b.get_16() / POS_SCALE
			s[DASH_VEL] = Vector3(vx, 0.0, b.get_16() / POS_SCALE)
		if blocks & B_PROGRESS:
			s[LEVEL] = b.get_u8()
			s[MAX_HEALTH] = float(b.get_u16())
			s[GOLD] = float(b.get_u16())
			s[ITEMS] = b.get_u8()
		if blocks & B_RECALL:
			s[RECALL] = b.get_u16() / TIMER_SCALE
		units[id] = s
	return {"tick": tick, "ack": ack, "units": units}


## Bytes the fixed-size blocks in a mask need (cooldowns: only the count).
static func _blocks_size(blocks: int) -> int:
	var n := 0
	n += 9 if blocks & B_CAST else 0
	n += 1 if blocks & B_COOLDOWNS else 0
	n += 3 if blocks & B_SLOW else 0
	n += 2 if blocks & B_RESPAWN else 0
	n += 2 if blocks & B_STUN else 0
	n += 6 if blocks & B_DASH else 0
	n += 6 if blocks & B_PROGRESS else 0
	n += 2 if blocks & B_RECALL else 0
	return n


## Writes a decoded record into a client-side unit (everything but position
## and yaw, which the client interpolates or predicts).
static func apply(u: Unit, s: Array) -> void:
	u.health = s[HEALTH]
	u.alive = s[ALIVE]
	u.cast_phase = s[PHASE]
	u.cast_slot = s[SLOT]
	u.cast_timer = s[CAST_TIMER]
	u.cast_target = s[CAST_TARGET]
	var cd: PackedFloat32Array = s[COOLDOWNS]
	if cd.size() == u.cooldowns.size():
		u.cooldowns = cd
	u.slow_amount = s[SLOW]
	u.slow_timer = s[SLOW_TIMER]
	u.respawn_timer = s[RESPAWN]
	u.stun_timer = s[STUN]
	u.dash_timer = s[DASH_TIMER]
	u.dash_velocity = s[DASH_VEL]
	u.recall_timer = s[RECALL]
	if s[LEVEL] >= 0:
		u.level = s[LEVEL]
		if s[ITEMS] >= 0:
			u.set_item_mask(s[ITEMS])
		u.gold = maxf(s[GOLD], 0.0)
		u.recompute_stats(false)  # damage, cooldown and speed; max health comes next
	if s[MAX_HEALTH] > 0.0:
		u.max_health = s[MAX_HEALTH]
	var opts := u.upgrade_options()
	var pick: int = s[UPGRADE]
	if pick >= 1 and pick <= opts.size():
		u.slot_overrides[1] = opts[pick - 1]
		u.upgrade_pending = false
