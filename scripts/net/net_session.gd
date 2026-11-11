class_name NetSession
extends Node
## Gate 1 network proof. A dedicated server owns the CombatAuthority; clients
## only send UnitCommands and draw what the server tells them.
##
## Server -> client: compact snapshots of every unit at 20 Hz (unreliable,
## ordered, SnapshotCodec) carrying the receiver's ack, plus reliable events
## (spawn, despawn, projectiles, areas, damage, deaths).
## Client -> server: one packet per physics tick holding the last few
## commands (unreliable, ordered); the server applies one per tick in order.
##
## The client predicts its own champion's movement (Unit.predict_step) and
## reconciles on every snapshot: back to the server's state at the ack, then
## replay the commands the server has not applied yet. A remaining visual
## error is blended out instead of snapping. Other units are interpolated.
##
## Not done yet (see docs/NETWORK.md): lag compensation for hits, predicted
## projectiles, delta snapshots and interest management, security beyond
## input sanitising.

signal local_unit_ready(u: Unit)
signal status_changed(text: String)

enum Mode { SERVER, CLIENT }

const DEFAULT_PORT := 24680
const SNAPSHOT_EVERY := 3        # physics ticks per snapshot (20 Hz)
const INTERP_DELAY := 0.1        # seconds the client renders behind the server
const RECONNECT_GRACE := 20.0    # seconds a dropped player's champion is held
const RETRY_EVERY := 2.0
## Commands repeated in each client packet (covers this many lost packets).
const COMMAND_REDUNDANCY := 4
## Client commands kept for replay (2 s at 60 Hz).
const HISTORY := 120
## A prediction error larger than this is a teleport (respawn): snap.
const SNAP_DISTANCE := 2.5
## How fast a visual prediction error is blended out (1/s).
const ERROR_DECAY := 12.0

var mode: Mode = Mode.CLIENT
var authority: CombatAuthority
var world: Node3D                # parent for units
var make_view: Callable          # client: func(u: Unit) -> void, adds visuals
var spawn_points: Array[Transform3D] = []
var champion_def: ChampionDef

## Simulated network conditions, applied to everything this process sends.
var lag_ms: float = 0.0
var jitter_ms: float = 0.0
var loss: float = 0.0            # 0..1, unreliable messages only
var log_enabled: bool = false

var _outbox: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _clock: float = 0.0

# --- server state
var _seats := {}        # token -> {unit, peer}
var _peer_token := {}   # peer id -> token
var _grace := {}        # token -> seconds left

# --- client state
var token: String = ""
var host: String = "127.0.0.1"
var port: int = DEFAULT_PORT
var local_controller: UnitController
var local_unit: Unit
var connected: bool = false
var _client_tick: int = 0
var _retry: float = 0.0
var _snapshots: Array[Dictionary] = []   # {t: server seconds, units: {id: Array}}
var _offset: float = 0.0                 # server time - local clock
var _have_offset: bool = false
var _fx := {}                            # fx id -> SimProjectile / SimArea
var bytes_last_snapshot: int = 0
## Client prediction (local champion only).
var prediction_enabled: bool = true
var _history := {}                       # client tick -> UnitCommand
var _pred_pos := Vector3.ZERO            # predicted position after the last tick
var _pred_prev := Vector3.ZERO           # ... and before it (render blend)
var _visual_error := Vector3.ZERO        # shown offset, decays to zero
var _have_pred: bool = false
var _last_ack: int = 0
var _pending: Array = []                 # [state, ack] waiting for the next physics tick
var corrections: PackedFloat32Array = PackedFloat32Array()  # metres, per snapshot


func _ready() -> void:
	_rng.seed = hash(token) + Time.get_ticks_usec()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func log_line(s: String) -> void:
	if log_enabled:
		print("NETLOG %.3f %s %s" % [_clock, "server" if mode == Mode.SERVER else token, s])


# ---------------------------------------------------------------- sending

## Every outgoing call goes through here so lag, jitter and loss can be
## simulated on top of ENet.
func _send(c: Callable, unreliable: bool) -> void:
	if unreliable and loss > 0.0 and _rng.randf() < loss:
		return
	if lag_ms <= 0.0 and jitter_ms <= 0.0:
		c.call()
		return
	var delay := (lag_ms + _rng.randf_range(-jitter_ms, jitter_ms)) / 1000.0
	_outbox.append({"at": _clock + maxf(delay, 0.0), "c": c})


func _flush_outbox() -> void:
	if _outbox.is_empty():
		return
	var due: Array[Dictionary] = []
	var keep: Array[Dictionary] = []
	for o in _outbox:
		(due if o.at <= _clock else keep).append(o)
	_outbox = keep
	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.at < b.at)
	for o in due:
		if (mode == Mode.SERVER or connected) and multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			(o.c as Callable).call()


# ---------------------------------------------------------------- server

func start_server(p: int) -> Error:
	mode = Mode.SERVER
	port = p
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(p, 8)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	authority.projectile_spawned.connect(func(pr: CombatAuthority.SimProjectile) -> void:
		_broadcast(ev_projectile.bind(pr.id, pr.source.net_id, pr.ability.resource_path, pr.position, pr.direction)))
	authority.projectile_ended.connect(func(pr: CombatAuthority.SimProjectile, at: Vector3) -> void:
		_broadcast(ev_projectile_end.bind(pr.id, at)))
	authority.area_spawned.connect(func(ar: CombatAuthority.SimArea) -> void:
		var from := ar.source.global_position
		log_line("area source=%d dist=%.2f" % [ar.source.net_id, Vector2(ar.center.x - from.x, ar.center.z - from.z).length()])
		_broadcast(ev_area.bind(ar.id, ar.source.net_id, ar.ability.resource_path, ar.center, ar.dir)))
	authority.area_detonated.connect(func(ar: CombatAuthority.SimArea) -> void:
		_broadcast(ev_area_end.bind(ar.id)))
	authority.unit_damaged.connect(func(t: Unit, amount: float, src: Unit) -> void:
		log_line("damage target=%d amount=%.0f source=%d health=%.0f" % [t.net_id, amount, src.net_id, t.health])
		_broadcast(ev_damage.bind(t.net_id, amount, src.net_id)))
	authority.unit_died.connect(func(t: Unit, k: Unit) -> void:
		log_line("death target=%d killer=%d" % [t.net_id, k.net_id])
		_broadcast(ev_death.bind(t.net_id, k.net_id)))
	authority.unit_respawned.connect(func(t: Unit) -> void:
		log_line("respawn target=%d" % t.net_id)
		_broadcast(ev_respawn.bind(t.net_id)))
	log_line("listening port=%d lag=%.0f jitter=%.0f loss=%.2f" % [p, lag_ms, jitter_ms, loss])
	return OK


func _broadcast(c: Callable, unreliable := false) -> void:
	for peer_id: int in _peer_token:
		_send(_bound_rpc_id(c, peer_id), unreliable)


## Turns method.bind(args) into a call of rpc_id(peer, method, args...).
func _bound_rpc_id(c: Callable, peer_id: int) -> Callable:
	var args := [peer_id, c.get_method()]
	args.append_array(c.get_bound_arguments())
	return func() -> void:
		if peer_id in multiplayer.get_peers():  # it may have left while the message waited
			callv("rpc_id", args)


func _on_peer_connected(id: int) -> void:
	if mode == Mode.SERVER:
		log_line("peer connected id=%d" % id)


func _on_peer_disconnected(id: int) -> void:
	if mode != Mode.SERVER or not _peer_token.has(id):
		return
	var tok: String = _peer_token[id]
	_peer_token.erase(id)
	var seat: Dictionary = _seats[tok]
	seat.peer = 0
	(seat.unit.controller as NetInputController).reset()
	_grace[tok] = RECONNECT_GRACE
	log_line("peer left id=%d token=%s unit=%d held for %.0fs" % [id, tok, seat.unit.net_id, RECONNECT_GRACE])


@rpc("any_peer", "call_remote", "reliable")
func hello(client_token: String) -> void:
	if mode != Mode.SERVER:
		return
	var id := multiplayer.get_remote_sender_id()
	var tok := client_token.substr(0, 32)
	if tok.is_empty():
		tok = "peer%d" % id
	var u: Unit
	if _seats.has(tok) and _seats[tok].peer == 0:
		u = _seats[tok].unit
		_grace.erase(tok)
		_seats[tok].peer = id
		log_line("reattached token=%s unit=%d peer=%d" % [tok, u.net_id, id])
	elif _seats.has(tok):
		log_line("rejected duplicate token=%s" % tok)
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	else:
		var slot := _seats.size()
		var xf: Transform3D = spawn_points[slot % spawn_points.size()]
		xf.origin += xf.basis.x * 2.0 * floorf(slot / float(spawn_points.size()))  # teammates side by side
		u = _spawn_unit(champion_def, slot % 2, xf, 0)
		u.controller = NetInputController.new()
		_seats[tok] = {"unit": u, "peer": id}
		log_line("joined token=%s unit=%d team=%d peer=%d" % [tok, u.net_id, u.team, id])
		for other: int in _peer_token:
			_send(_bound_rpc_id(spawn_unit.bind(_unit_header(u)), other), false)
	_peer_token[id] = tok
	var all: Array = []
	for x in authority.units:
		all.append(_unit_header(x))
	_send(_bound_rpc_id(welcome.bind(u.net_id, all), id), false)


func _unit_header(u: Unit) -> Dictionary:
	return {"id": u.net_id, "def": u.def.resource_path, "team": u.team, "xf": u.spawn_transform}


func _spawn_unit(def: ChampionDef, team: int, xf: Transform3D, net_id: int) -> Unit:
	var u := Unit.new()
	u.def = def
	u.team = team
	u.transform = xf
	u.name = "%s_%d" % [def.id, net_id if net_id > 0 else authority.units.size() + 1]
	world.add_child(u)
	authority.register_unit(u, net_id)
	if mode == Mode.CLIENT:
		u.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # positions come from snapshots
		u.global_transform = xf
		if make_view.is_valid():
			make_view.call(u)
	return u


## The newest command is for last_tick; the ones before it are repeats of
## earlier ticks, oldest first.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func client_commands(last_tick: int, cmds: Array) -> void:
	if mode != Mode.SERVER or not (last_tick is int):
		return
	var id := multiplayer.get_remote_sender_id()
	if not _peer_token.has(id):
		return
	var ctl := _seats[_peer_token[id]].unit.controller as NetInputController
	var n := mini(cmds.size(), COMMAND_REDUNDANCY)
	for i in n:
		var d: Variant = cmds[cmds.size() - n + i]
		if d is Dictionary:
			ctl.receive(last_tick - (n - 1 - i), UnitCommand.from_dict(d))


func _server_tick(dt: float) -> void:
	for tok: String in _grace.keys():
		_grace[tok] -= dt
		if _grace[tok] <= 0.0:
			var u: Unit = _seats[tok].unit
			_grace.erase(tok)
			_seats.erase(tok)
			log_line("released token=%s unit=%d" % [tok, u.net_id])
			_broadcast(despawn_unit.bind(u.net_id))
			authority.remove_unit(u)
	if authority.tick % SNAPSHOT_EVERY == 0 and not _peer_token.is_empty():
		var body := SnapshotCodec.encode_units(authority.units)
		for peer_id: int in _peer_token:
			var ctl := _seats[_peer_token[peer_id]].unit.controller as NetInputController
			var bytes := SnapshotCodec.encode(authority.tick, ctl.applied_tick, authority.units.size(), body)
			bytes_last_snapshot = bytes.size()
			_send(_bound_rpc_id(snapshot.bind(bytes), peer_id), true)


# ---------------------------------------------------------------- client

## Graceful leave: tell the server now instead of letting it time out.
func leave() -> void:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if mode == Mode.CLIENT and peer and connected:
		var server := peer.get_peer(1)
		if server:
			server.peer_disconnect_later()
		peer.host.flush()
		log_line("leaving")
	connected = false
	_outbox.clear()

func start_client(h: String, p: int) -> Error:
	mode = Mode.CLIENT
	host = h
	port = p
	return _dial()


func _dial() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port)
	if err == OK:
		multiplayer.multiplayer_peer = peer
		status_changed.emit("Connecting to %s:%d" % [host, port])
	return err


func _on_connected() -> void:
	connected = true
	log_line("connected")
	status_changed.emit("")
	_send(func() -> void: hello.rpc_id(1, token), false)


func _on_connection_failed() -> void:
	connected = false
	log_line("connection failed")
	status_changed.emit("Could not reach the server. Retrying.")
	_retry = RETRY_EVERY


func _on_server_disconnected() -> void:
	connected = false
	log_line("server disconnected")
	status_changed.emit("Lost the server. Retrying.")
	_retry = RETRY_EVERY


@rpc("authority", "call_remote", "reliable")
func welcome(my_unit: int, units: Array) -> void:
	for h: Dictionary in units:
		if authority.find_unit(h.id) == null:
			_spawn_from_header(h)
	local_unit = authority.find_unit(my_unit)
	local_unit.controller = local_controller
	_client_tick = 0
	_history.clear()
	_have_pred = false
	_last_ack = 0
	_pending = []
	log_line("welcome unit=%d units=%d" % [my_unit, authority.units.size()])
	local_unit_ready.emit(local_unit)


func _spawn_from_header(h: Dictionary) -> void:
	var def := load(h.def) as ChampionDef
	_spawn_unit(def, h.team, h.xf, h.id)


@rpc("authority", "call_remote", "reliable")
func spawn_unit(h: Dictionary) -> void:
	if authority.find_unit(h.id) == null:
		_spawn_from_header(h)
		log_line("saw spawn unit=%d" % h.id)


@rpc("authority", "call_remote", "reliable")
func despawn_unit(id: int) -> void:
	var u := authority.find_unit(id)
	if u:
		authority.remove_unit(u)
		log_line("saw despawn unit=%d" % id)


@rpc("authority", "call_remote", "unreliable_ordered")
func snapshot(bytes: PackedByteArray) -> void:
	var snap := SnapshotCodec.decode(bytes)
	if snap.is_empty():
		return
	var data: Dictionary = snap.units
	var t: float = snap.tick / float(Engine.physics_ticks_per_second)
	var est := t - _clock
	# Smoothed clock offset so jitter does not shake the render time.
	_offset = est if not _have_offset else lerpf(_offset, est, 0.1)
	_have_offset = true
	_snapshots.append({"t": t, "units": data})
	while _snapshots.size() > 30:
		_snapshots.pop_front()
	for id: int in data:
		var u := authority.find_unit(id)
		if u == null:
			continue
		var s: Array = data[id]
		var was_alive := u.alive
		SnapshotCodec.apply(u, s)
		u.collision_layer = Unit.LAYER_UNITS if u.alive else 0
		if was_alive != u.alive:
			if u.alive:
				u.respawned.emit()
			else:
				u.died.emit(null)
	if local_unit and is_instance_valid(local_unit) and data.has(local_unit.net_id):
		# Replayed on the next physics tick: move_and_slide() outside a physics
		# frame uses the render delta instead (character_body_3d.cpp), which
		# made every replay come up short.
		_pending = [data[local_unit.net_id], snap.ack]


## Back to the server's state at the acknowledged command, then replay every
## newer command. Whatever the replay ends up disagreeing with the old
## prediction becomes a visual offset that fades out.
func _reconcile(s: Array, ack: int) -> void:
	_last_ack = ack
	for t: int in _history.keys():
		if t <= ack:
			_history.erase(t)
	if not prediction_enabled or not local_unit.alive:
		_have_pred = false
		return
	var server_pos: Vector3 = s[SnapshotCodec.POS]
	if not _have_pred:
		_pred_pos = server_pos
		_pred_prev = server_pos
		_visual_error = Vector3.ZERO
		_have_pred = true
	var shown := _pred_pos + _visual_error
	local_unit.global_position = server_pos
	local_unit.buffered_slot = -1
	var dt := 1.0 / Engine.physics_ticks_per_second
	var ticks: Array = _history.keys()
	ticks.sort()
	for t: int in ticks:
		local_unit.predict_step(_history[t], dt)
	var error := _pred_pos.distance_to(local_unit.global_position)
	corrections.append(error)
	_pred_pos = local_unit.global_position
	_pred_prev = _pred_pos
	_visual_error = Vector3.ZERO if error > SNAP_DISTANCE else shown - _pred_pos


func _client_physics(dt: float) -> void:
	if _retry > 0.0:
		_retry -= dt
		if _retry <= 0.0:
			_dial()
	if not connected or local_unit == null or not is_instance_valid(local_unit):
		return
	if not _pending.is_empty():
		_reconcile(_pending[0], _pending[1])
		_pending = []
	_client_tick += 1
	var cmd := local_controller.get_command(local_unit)
	if _move_sent_at < 0.0 and cmd.move.length() > 0.1:
		_move_sent_at = _clock
		_start_pos = local_unit.global_position
	elif _move_sent_at >= 0.0 and _start_pos != Vector3.INF and local_unit.global_position.distance_to(_start_pos) > 0.05:
		log_line("input_to_visible_ms=%.0f" % ((_clock - _move_sent_at) * 1000.0))
		_start_pos = Vector3.INF
	_history[_client_tick] = cmd
	if _history.size() > HISTORY:
		_history.erase(_history.keys().min())
	var batch: Array = []
	for t in range(maxi(_client_tick - COMMAND_REDUNDANCY + 1, 1), _client_tick + 1):
		if _history.has(t):
			batch.append((_history[t] as UnitCommand).to_dict())
	var tick := _client_tick
	_send(func() -> void: client_commands.rpc_id(1, tick, batch), true)
	if prediction_enabled and _have_pred and local_unit.alive:
		local_unit.global_position = _pred_pos
		local_unit.predict_step(cmd, dt)
		_pred_prev = _pred_pos
		_pred_pos = local_unit.global_position
		_visual_error *= exp(-ERROR_DECAY * dt)
	# Visual-only projectile motion between events.
	for id: int in _fx:
		var fx: Variant = _fx[id]
		if fx is CombatAuthority.SimProjectile:
			var p: CombatAuthority.SimProjectile = fx
			p.position += p.direction * p.ability.projectile_speed * dt
		elif fx is CombatAuthority.SimArea:
			(fx as CombatAuthority.SimArea).timer -= dt


func _client_render() -> void:
	if not _have_offset or _snapshots.size() < 2:
		return
	var frame := Engine.get_physics_interpolation_fraction() / Engine.physics_ticks_per_second
	var rt := _clock + frame + _offset - INTERP_DELAY
	var a: Dictionary = _snapshots[0]
	var b: Dictionary = _snapshots[_snapshots.size() - 1]
	for i in range(_snapshots.size() - 1):
		if _snapshots[i].t <= rt and _snapshots[i + 1].t >= rt:
			a = _snapshots[i]
			b = _snapshots[i + 1]
			break
	if rt > b.t:
		a = b  # starved: hold the newest instead of extrapolating
	var k := 0.0 if b.t <= a.t else clampf((rt - a.t) / (b.t - a.t), 0.0, 1.0)
	for u in authority.units:
		if u == local_unit and prediction_enabled and _have_pred and u.alive:
			var f := Engine.get_physics_interpolation_fraction()
			u.global_position = _pred_prev.lerp(_pred_pos, f) + _visual_error
			continue
		if not (a.units.has(u.net_id) and b.units.has(u.net_id)):
			continue
		var sa: Array = a.units[u.net_id]
		var sb: Array = b.units[u.net_id]
		u.global_position = (sa[0] as Vector3).lerp(sb[0], k)
		u.aim_yaw = lerp_angle(sa[1], sb[1], k)
		u.rotation.y = u.aim_yaw


@rpc("authority", "call_remote", "reliable")
func ev_projectile(id: int, src: int, ability_path: String, pos: Vector3, dir: Vector3) -> void:
	var u := authority.find_unit(src)
	if u == null:
		return
	var p := CombatAuthority.SimProjectile.new()
	p.id = id
	p.source = u
	p.ability = load(ability_path)
	p.position = pos
	p.direction = dir
	_fx[id] = p
	authority.projectile_spawned.emit(p)


@rpc("authority", "call_remote", "reliable")
func ev_projectile_end(id: int, at: Vector3) -> void:
	var p: CombatAuthority.SimProjectile = _fx.get(id)
	if p:
		_fx.erase(id)
		authority.projectile_ended.emit(p, at)


@rpc("authority", "call_remote", "reliable")
func ev_area(id: int, src: int, ability_path: String, center: Vector3, dir: Vector3) -> void:
	var u := authority.find_unit(src)
	if u == null:
		return
	var ar := CombatAuthority.SimArea.new()
	ar.id = id
	ar.source = u
	ar.ability = load(ability_path)
	ar.center = center
	ar.dir = dir
	ar.timer = CombatAuthority.area_lifetime(ar.ability)
	_fx[id] = ar
	authority.area_spawned.emit(ar)


@rpc("authority", "call_remote", "reliable")
func ev_area_end(id: int) -> void:
	var ar: CombatAuthority.SimArea = _fx.get(id)
	if ar:
		_fx.erase(id)
		authority.area_detonated.emit(ar)


@rpc("authority", "call_remote", "reliable")
func ev_damage(target: int, amount: float, src: int) -> void:
	var t := authority.find_unit(target)
	var s := authority.find_unit(src)
	if t:
		log_line("saw damage target=%d amount=%.0f" % [target, amount])
		t.damaged.emit(amount, s)
		authority.unit_damaged.emit(t, amount, s)


@rpc("authority", "call_remote", "reliable")
func ev_death(target: int, killer: int) -> void:
	log_line("saw death target=%d killer=%d" % [target, killer])


@rpc("authority", "call_remote", "reliable")
func ev_respawn(target: int) -> void:
	log_line("saw respawn target=%d" % target)


# ---------------------------------------------------------------- loop

func _physics_process(dt: float) -> void:
	_clock += dt
	if mode == Mode.SERVER:
		_server_tick(dt)
	else:
		_client_physics(dt)
	_flush_outbox()
	_log_states()


var _log_every: int = 30
var _phys_count: int = 0
var _move_sent_at: float = -1.0
var _start_pos := Vector3.INF
var _last_pos := {}
var max_speed_seen := {}  # server: unit id -> fastest horizontal speed observed


func _log_states() -> void:
	_phys_count += 1
	if mode == Mode.SERVER:
		# Measured from actual displacement per tick, skipping respawn teleports.
		for u in authority.units:
			var prev: Array = _last_pos.get(u.net_id, [])
			if not prev.is_empty() and prev[1] and u.alive:
				var p: Vector3 = prev[0]
				var v := Vector2(u.global_position.x - p.x, u.global_position.z - p.z).length() * Engine.physics_ticks_per_second
				max_speed_seen[u.net_id] = maxf(max_speed_seen.get(u.net_id, 0.0), v)
			_last_pos[u.net_id] = [u.global_position, u.alive]
	if not log_enabled or _phys_count % _log_every != 0:
		return
	var parts: PackedStringArray = []
	for u in authority.units:
		if u.def.look == ChampionDef.Look.SPELLCASTER:
			parts.append("%d:%.2f,%.2f,%.0f,%s" % [u.net_id, u.global_position.x, u.global_position.z, u.health, "A" if u.alive else "D"])
	var extra := ""
	if mode == Mode.SERVER:
		var starved := {}
		for tok: String in _seats:
			var ctl := _seats[tok].unit.controller as NetInputController
			starved[_seats[tok].unit.net_id] = [ctl.starved_ticks, ctl.skipped_ticks]
		extra = " snapshot_bytes=%d maxspeed=%s starved=%s" % [bytes_last_snapshot, JSON.stringify(max_speed_seen), JSON.stringify(starved)]
	elif not corrections.is_empty():
		# Prediction error found at each reconcile since the last line (metres).
		var mx := 0.0
		var sum := 0.0
		var big := 0
		for c in corrections:
			mx = maxf(mx, c)
			sum += c
			big += 1 if c > 0.25 else 0
		extra = " pred_corrections=%d pred_err_mean=%.3f pred_err_max=%.3f pred_big=%d ack=%d" % [corrections.size(), sum / corrections.size(), mx, big, _last_ack]
		corrections.clear()
	log_line("state tick=%d %s%s" % [authority.tick, " ".join(parts), extra])


func _process(_dt: float) -> void:
	if mode == Mode.CLIENT:
		_client_render()


func snapshot_state(id: int) -> Array:
	## Latest received state for a unit (tests and logging).
	if _snapshots.is_empty() or not _snapshots[-1].units.has(id):
		return []
	return _snapshots[-1].units[id]
