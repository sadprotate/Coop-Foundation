extends SceneTree

var Board: GDScript
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func run() -> void:
	await create_timer(0.2).timeout
	Board = load("res://scripts/scoreboard.gd")
	var room := {"zone": "town", "mode": "ffa", "players": [{"id": "a", "name": "A", "party": 0}, {"id": "b", "name": "B", "party": 1}, {"id": "c", "name": "C", "party": 0}], "match": {"round_wins": {"a": 1, "b": 2, "c": 2}, "round_scores": {"a": 4, "b": 1, "c": 3}}}
	var snapshot := {"players": [{"id": "a", "ping_ms": 42}, {"id": "b", "ping_ms": 83}, {"id": "c", "ping_ms": 20}]}
	var rows: Array[Dictionary] = Board.build_rows(room, snapshot, "b")
	check(rows.size() == 3 and rows[1].local and rows[1].ping == 83, "Town rows use synchronized players, ping and local identity")
	room.zone = "arena"
	rows = Board.build_rows(room, snapshot, "b")
	check(rows[0].id == "c" and rows[1].id == "b" and rows[2].id == "a", "Rank by round wins then current knockouts")
	room.match.round_wins.a = 3
	rows = Board.build_rows(room, snapshot, "b")
	check(rows[0].id == "a", "New highest score rises to the top")
	snapshot.players[0].ping_ms = 120
	rows = Board.build_rows(room, snapshot, "b")
	check(rows[0].ping == 120, "Ping changes update without a separate local score state")
	room.players.remove_at(0)
	rows = Board.build_rows(room, snapshot, "b")
	check(rows.size() == 2 and rows.all(func(row: Dictionary): return row.id != "a"), "Departed roster members disappear even before an older snapshot changes")
	room.players.append({"id": "d", "name": "D", "party": 0})
	rows = Board.build_rows(room, snapshot, "b")
	check(rows.size() == 3 and rows[2].ping == null, "New players appear immediately with unknown ping until measured")
	room.mode = "teams"
	room.match = {"round_wins": {"red": 2, "blue": 1}, "round_scores": {"red": 0, "blue": 3}}
	rows = Board.build_rows(room, snapshot, "b")
	check(rows[0].party == 0 and rows[1].party == 0 and rows[2].party == 1, "Team rankings use synchronized team wins, not fabricated individual kills")
	check(rows[0].wins == 2 and rows[2].knockouts == 3, "Existing team round scores are available per player")
	root.get_node("Sound").shutdown()
	await create_timer(0.2).timeout
	print("SCOREBOARD06 RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
