extends Node

const CONFIG_PATH = "res://game_stats.cfg"
const STATE_PATH = "user://game_stats_state.cfg"
const RETRY_DELAY_SECONDS = 30.0

var enabled = false
var endpoint_url = ""
var headers = PackedStringArray()
var version_name = ""
var player_username = ""
var unlocked_achievements = []
var pending_events = []
var request_in_flight = false
var http_request


func _ready():
	var config = ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		push_warning("Game Stats AI is disabled: %s is missing." % CONFIG_PATH)
		return

	var base_url = config.get_value("game_stats", "base_url", "https://gamestats.ai")
	var account_id = config.get_value("game_stats", "account_id")
	var api_token = config.get_value("game_stats", "api_token")
	endpoint_url = "%s/api/v1/accounts/%s/achievement_events" % [base_url, account_id]
	headers = PackedStringArray([
		"Authorization: Bearer %s" % api_token,
		"Content-Type: application/json",
	])
	version_name = ProjectSettings.get_setting("application/config/version")

	load_state()

	http_request = HTTPRequest.new()
	http_request.timeout = 10.0
	http_request.request_completed.connect(_on_request_completed)
	add_child(http_request)

	enabled = true
	send_next_event()


func unlock(achievement_name):
	if not enabled or achievement_name in unlocked_achievements:
		return

	unlocked_achievements.append(achievement_name)
	pending_events.append({
		"version_name": version_name,
		"player_username": player_username,
		"achievement_name": achievement_name,
		"occurred_at": Time.get_datetime_string_from_system(true) + "Z",
	})
	save_state()
	send_next_event()


func send_next_event():
	if request_in_flight or pending_events.is_empty():
		return

	var body = JSON.stringify(pending_events[0])
	if http_request.request(endpoint_url, headers, HTTPClient.METHOD_POST, body) == OK:
		request_in_flight = true
	else:
		retry_later()


func _on_request_completed(result, response_code, _headers, body):
	request_in_flight = false

	if result == HTTPRequest.RESULT_SUCCESS and response_code == 201:
		pending_events.pop_front()
	elif result == HTTPRequest.RESULT_SUCCESS and response_code == 422:
		push_warning("Game Stats AI rejected an event: %s" % body.get_string_from_utf8())
		pending_events.pop_front()
	else:
		retry_later()
		return

	save_state()
	send_next_event()


func retry_later():
	get_tree().create_timer(RETRY_DELAY_SECONDS).timeout.connect(send_next_event)


func load_state():
	var state = ConfigFile.new()
	state.load(STATE_PATH)
	player_username = state.get_value("player", "username", "")
	if player_username.is_empty():
		player_username = "player_" + Crypto.new().generate_random_bytes(6).hex_encode()
	unlocked_achievements = state.get_value("achievements", "unlocked", [])
	pending_events = state.get_value("achievements", "pending", [])
	save_state()


func save_state():
	var state = ConfigFile.new()
	state.set_value("player", "username", player_username)
	state.set_value("achievements", "unlocked", unlocked_achievements)
	state.set_value("achievements", "pending", pending_events)
	state.save(STATE_PATH)
