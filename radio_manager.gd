class_name RadioManager
extends Node

signal dispatch_received(text: String, duration: float)
signal static_burst_triggered(intensity: float, decay_speed: float)

static var instance: RadioManager = null

@export_group("Contextual Narrative Settings")
## Enables atmospheric narrative broadcasts and lore dispatches.
@export var enable_narrative_dispatches: bool = true

# Message queue state
var _message_queue: Array[Dictionary] = []
var _is_displaying: bool = false
var _display_timer: float = 0.0
var _current_duration: float = 0.0

# Contextual milestone progression tracking
var _milestones_fired: Dictionary = {
	85: false,
	83: false,
	81: false,
	78: false,
	778: false,
	77: false
}

var _doppelganger_dispatch_index: int = 0

const DOPPELGANGER_DISPATCHES: Array[String] = [
	"[CENTRAL 10-33] ATENCIÓN UNIDAD 77: Carroza fúnebre sin patente avanza en contra por tu misma pista. NO HAY CONDUCTOR AL VOLANTE. ¡Baja las luces [F/H] y no te detengas!",
	"[ESTÁTICA / 10-33] ...anomalía en la ruta... el radar detecta tu mismo número de chasis viniendo de frente... ¡APAGA LAS LUCES ALTAS o te arrastrará fuera del camino!",
	"[FRECUENCIA 1989] ...es el Cortejo de la Parroquia... no lo mires a los faros... mantén luces bajas al cruzar..."
]


func _init() -> void:
	instance = self

func _ready() -> void:
	instance = self
	_connect_to_player()
	# Broadcast initial game start dispatch after brief startup pause
	get_tree().create_timer(1.2).timeout.connect(func():
		if enable_narrative_dispatches:
			broadcast_dispatch(
				"[CENTRAL FORENSE] Unidad 77, confirme recepción... Lleva el séptimo féretro sellado del derrumbe de 1989. Entréguelo pasando el Arco del Km 77. No se detenga en la niebla.",
				7.5
			)
	)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if instance == self:
			instance = null

func _process(delta: float) -> void:
	if _is_displaying:
		_display_timer += delta
		if _display_timer >= _current_duration:
			_is_displaying = false
			_display_timer = 0.0
			_show_next_in_queue()
	elif not _message_queue.is_empty():
		_show_next_in_queue()

## Resets all narrative milestones and timers for seamless loop recurrence.
func reset_milestones() -> void:
	for k in _milestones_fired.keys():
		_milestones_fired[k] = false

## Broadcasts a dispatch message to the HUD subtitle overlay.
func broadcast_dispatch(text: String, duration: float = 6.0, priority: bool = false, static_glitch_intensity: float = 0.0) -> void:
	var msg := {
		"text": text,
		"duration": duration
	}

	if static_glitch_intensity > 0.01:
		static_burst_triggered.emit(static_glitch_intensity, 2.2)

	if priority:
		# Urgent events interrupt and take immediate precedence
		_message_queue.insert(0, msg)
		_show_next_in_queue()
	else:
		_message_queue.append(msg)
		if not _is_displaying:
			_show_next_in_queue()

func _show_next_in_queue() -> void:
	if _message_queue.is_empty():
		return
	var msg: Dictionary = _message_queue.pop_front()
	_is_displaying = true
	_display_timer = 0.0
	_current_duration = msg["duration"]
	dispatch_received.emit(msg["text"], msg["duration"])

## Called when the Doppelgänger oncoming funeral hearse enters proximity.
func report_doppelganger_encounter() -> void:
	if not enable_narrative_dispatches:
		return
	var text: String = DOPPELGANGER_DISPATCHES[_doppelganger_dispatch_index % DOPPELGANGER_DISPATCHES.size()]
	_doppelganger_dispatch_index += 1
	broadcast_dispatch(text, 7.5, true, 0.85)

## Delivers a warning at the last moment before a pass.
func report_doppelganger_close_pass(high_beams_active: bool = false) -> void:
	if not enable_narrative_dispatches:
		return
	if high_beams_active:
		broadcast_dispatch(
			"[ALERTA CRÍTICA] ¡LO ALUMBRASTE CON LUCES ALTAS! ¡EL CORTEJO TE CIEGA Y TOMA EL VOLANTE! ¡CONTRAVOLANTEA!",
			5.0,
			true,
			1.0
		)
	else:
		broadcast_dispatch(
			"[CENTRAL 10-33] CARROZA FÚNEBRE A TU COSTADO. MANTÉN LUCES BAJAS. NO MIRES POR LA VENTANILLA.",
			4.5,
			true,
			0.45
		)

## Called when scavenging begins at a SupplyStop (Posta Parroquial).
func report_supply_stop_started() -> void:
	if not enable_narrative_dispatches:
		return
	broadcast_dispatch(
		"[ZONA MUERTA] ...señal cortada frente al refugio parroquial... solo se oyen las campanas sobre el surtidor...",
		4.5,
		true,
		0.2
	)

## Called when scavenging finishes at a SupplyStop.
func report_supply_stop_completed() -> void:
	if not enable_narrative_dispatches:
		return
	broadcast_dispatch(
		"[ESTÁTICA] ...portadora recuperada... tanque lleno y motor consagrado... sal de la posta antes de que se apaguen los cirios...",
		6.5,
		false,
		0.5
	)

## Called when the player collects one of the 3 Forbidden Relics from an abandoned vehicle.
func report_relic_collected(current_relics: int, required_relics: int) -> void:
	if not enable_narrative_dispatches:
		return
	if current_relics >= required_relics:
		broadcast_dispatch(
			"[SELLO ROTO // 3 DE 3 RELIQUIAS] ¡Has reunido las tres Actas del Derrumbe de 1989! El Gran Arco del Kilómetro 77 ahora se abrirá para liberarte del bucle.",
			8.0,
			true,
			0.85
		)
	else:
		broadcast_dispatch(
			"[ARCHIVO 1989 // RELIQUIA %d/%d] ...acta parroquial recuperada entre la ceniza... reúne %d más en los coches abandonados para romper la maldición del Km 77..." % [current_relics, required_relics, required_relics - current_relics],
			6.5,
			true,
			0.45
		)

## Called when the player disperses a raven omen flock using the horn [X].
func report_raven_flock_dispersed() -> void:
	if not enable_narrative_dispatches:
		return
	broadcast_dispatch(
		"[FRECUENCIA 142.8] El eco del claxon dispersó a los cuervos del camino. Vía despejada.",
		3.8,
		false,
		0.15
	)

func _connect_to_player() -> void:
	var nodes := get_tree().get_nodes_in_group("player")
	if not nodes.is_empty() and nodes[0] is Van:
		_on_player_found(nodes[0] as Van)
	else:
		get_tree().create_timer(0.2).timeout.connect(func():
			var retry_nodes := get_tree().get_nodes_in_group("player")
			if not retry_nodes.is_empty() and retry_nodes[0] is Van:
				_on_player_found(retry_nodes[0] as Van)
		)

func _on_player_found(van: Van) -> void:
	if not van.distance_updated.is_connected(_on_van_distance_updated):
		van.distance_updated.connect(_on_van_distance_updated)
	if not van.collision_impact.is_connected(_on_collision_impact):
		van.collision_impact.connect(_on_collision_impact)

func _on_collision_impact(trauma: float) -> void:
	if not enable_narrative_dispatches:
		return
	if trauma > 0.65:
		broadcast_dispatch(
			"[ALERTA 10-50] ...impacto severo en la Unidad 77... el féretro trasero golpeó las cadenas... vigile la condición del motor...",
			5.5,
			true,
			0.9
		)

## Progressive narrative escalation as distance counts down toward Kilómetro 77, evolving across loops.
func _on_van_distance_updated(_distance_meters: float, current_km: float) -> void:
	if not enable_narrative_dispatches:
		return

	var loop_count: int = 0
	var relics: int = 0
	var nodes := get_tree().get_nodes_in_group("player") if get_tree() else []
	if not nodes.is_empty() and nodes[0] is Van:
		var v := nodes[0] as Van
		loop_count = v.km77_breach_count
		relics = v.relics_collected

	if current_km <= 77.2 and not _milestones_fired.get(77, false):
		_milestones_fired[77] = true
		if relics >= 3:
			broadcast_dispatch(
				"[CAMPANAS DE LA ABADÍA] << EL ARCO SE ABRE >> Las tres reliquias brillan en el tablero... ¡Cruza el Kilómetro 77 y sal de octubre de 1989!",
				8.5,
				true,
				0.6
			)
		elif loop_count == 0:
			broadcast_dispatch(
				"[CENTRAL 10-0] << COLAPSO TEMPORAL >> ...Hito 77 alcanzado... las agujas del reloj se detuvieron a las 03:33... ¡¿DÓNDE ESTÁS, UNIDAD 77?! ¡FALTAN LAS RELIQUIAS!--",
				8.5,
				true,
				0.95
			)
		else:
			broadcast_dispatch(
				"[VOZ DE 1989] << BUCLE #%d >> Sin las 3 Reliquias de los autos abandonados, el Arco del Km 77 nos devolverá al Hito 85..." % (loop_count + 1),
				8.5,
				true,
				0.95
			)
	elif current_km <= 77.9 and not _milestones_fired.get(778, false):
		_milestones_fired[778] = true
		broadcast_dispatch(
			"[PROCESIÓN DE CENIZA] << KM 78.0 >> La niebla se tiñe de sangre... las carrozas fúnebres en las bermas están encendiendo sus faros a tu paso...",
			8.0,
			true,
			0.75
		)
	elif current_km <= 78.6 and not _milestones_fired.get(78, false):
		_milestones_fired[78] = true
		if loop_count == 0:
			broadcast_dispatch(
				"[ALERTA 10-33] Unidad 77, los planos viales muestran que la Ruta 77 fue sepultada por el aluvión hace treinta años... ¡¿sobre qué asfalto está conduciendo?!",
				7.5,
				true,
				0.6
			)
		else:
			broadcast_dispatch(
				"[MEMORIA DEL BUCLE] Ya estuviste en esta curva en 1989. Recuerda usar [ESPACIO] para derrapar y [X] para dispersar a los cuervos.",
				7.5,
				true,
				0.6
			)
	elif current_km <= 81.2 and not _milestones_fired.get(81, false):
		_milestones_fired[81] = true
		if relics < 3:
			broadcast_dispatch(
				"[FRECUENCIA OCULTA] ...busca los vehículos con luces interiores parpadeando en la berma... detente y mantén [E] para recuperar las 3 Reliquias (%d/3)... Usa el claxon [X] si ves cuervos en la vía." % relics,
				8.0,
				false,
				0.4
			)
		else:
			broadcast_dispatch(
				"[FRECUENCIA OCULTA] Tienes las 3 Reliquias consagradas. No dejes que el Cortejo Negro te destruya antes del Km 77.",
				7.0,
				false,
				0.3
			)
	elif current_km <= 83.2 and not _milestones_fired.get(83, false):
		_milestones_fired[83] = true
		if loop_count == 0:
			broadcast_dispatch(
				"[CENTRAL 10-4] Niebla sepulcral densa y curvas cerradas más adelante. Use luces altas [F/H] para ver de lejos y derrape con [ESPACIO].",
				7.0
			)
		else:
			broadcast_dispatch(
				"[ARCHIVO 1989 // CICLO #%d] 'La Unidad Forense 77 nunca salió de la montaña...' Inspecciona los coches abandonados [E] para romper el ciclo." % (loop_count + 1),
				7.5,
				false,
				0.35
			)
