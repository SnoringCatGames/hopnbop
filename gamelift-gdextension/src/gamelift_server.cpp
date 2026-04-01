#include "gamelift_server.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <ctime>

using namespace godot;

// ============================================================================
// GameLiftOutcome Implementation
// ============================================================================

void GameLiftOutcome::_bind_methods() {
    ClassDB::bind_method(D_METHOD("is_success"), &GameLiftOutcome::is_success);
    ClassDB::bind_method(D_METHOD("get_error_message"), &GameLiftOutcome::get_error_message);
    ClassDB::bind_method(D_METHOD("get_error_type"), &GameLiftOutcome::get_error_type);

    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "success"), "", "is_success");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "error_message"), "", "get_error_message");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "error_type"), "", "get_error_type");
}

GameLiftOutcome::GameLiftOutcome() : m_success(false), m_error_type(0) {}
GameLiftOutcome::~GameLiftOutcome() {}

void GameLiftOutcome::set_success(bool success) { m_success = success; }
bool GameLiftOutcome::is_success() const { return m_success; }

void GameLiftOutcome::set_error_message(const String &message) { m_error_message = message; }
String GameLiftOutcome::get_error_message() const { return m_error_message; }

void GameLiftOutcome::set_error_type(int type) { m_error_type = type; }
int GameLiftOutcome::get_error_type() const { return m_error_type; }

// ============================================================================
// GameLiftGameSession Implementation
// ============================================================================

void GameLiftGameSession::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_game_session_id"), &GameLiftGameSession::get_game_session_id);
    ClassDB::bind_method(D_METHOD("get_name"), &GameLiftGameSession::get_name);
    ClassDB::bind_method(D_METHOD("get_fleet_id"), &GameLiftGameSession::get_fleet_id);
    ClassDB::bind_method(D_METHOD("get_ip_address"), &GameLiftGameSession::get_ip_address);
    ClassDB::bind_method(D_METHOD("get_port"), &GameLiftGameSession::get_port);
    ClassDB::bind_method(D_METHOD("get_maximum_player_session_count"), &GameLiftGameSession::get_maximum_player_session_count);
    ClassDB::bind_method(D_METHOD("get_current_player_session_count"), &GameLiftGameSession::get_current_player_session_count);
    ClassDB::bind_method(D_METHOD("get_game_session_data"), &GameLiftGameSession::get_game_session_data);
    ClassDB::bind_method(D_METHOD("get_matchmaker_data"), &GameLiftGameSession::get_matchmaker_data);
    ClassDB::bind_method(D_METHOD("get_dns_name"), &GameLiftGameSession::get_dns_name);
    ClassDB::bind_method(D_METHOD("get_game_properties"), &GameLiftGameSession::get_game_properties);

    ADD_PROPERTY(PropertyInfo(Variant::STRING, "game_session_id"), "", "get_game_session_id");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "name"), "", "get_name");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "fleet_id"), "", "get_fleet_id");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "ip_address"), "", "get_ip_address");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "port"), "", "get_port");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "maximum_player_session_count"), "", "get_maximum_player_session_count");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "current_player_session_count"), "", "get_current_player_session_count");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "game_session_data"), "", "get_game_session_data");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "matchmaker_data"), "", "get_matchmaker_data");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "dns_name"), "", "get_dns_name");
    ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "game_properties"), "", "get_game_properties");
}

GameLiftGameSession::GameLiftGameSession() : m_port(0), m_maximum_player_session_count(0), m_current_player_session_count(0) {}
GameLiftGameSession::~GameLiftGameSession() {}

void GameLiftGameSession::set_game_session_id(const String &id) { m_game_session_id = id; }
void GameLiftGameSession::set_name(const String &name) { m_name = name; }
void GameLiftGameSession::set_fleet_id(const String &id) { m_fleet_id = id; }
void GameLiftGameSession::set_ip_address(const String &ip) { m_ip_address = ip; }
void GameLiftGameSession::set_port(int port) { m_port = port; }
void GameLiftGameSession::set_maximum_player_session_count(int count) { m_maximum_player_session_count = count; }
void GameLiftGameSession::set_current_player_session_count(int count) { m_current_player_session_count = count; }
void GameLiftGameSession::set_game_session_data(const String &data) { m_game_session_data = data; }
void GameLiftGameSession::set_matchmaker_data(const String &data) { m_matchmaker_data = data; }
void GameLiftGameSession::set_dns_name(const String &name) { m_dns_name = name; }
void GameLiftGameSession::set_game_properties(const Dictionary &props) { m_game_properties = props; }

String GameLiftGameSession::get_game_session_id() const { return m_game_session_id; }
String GameLiftGameSession::get_name() const { return m_name; }
String GameLiftGameSession::get_fleet_id() const { return m_fleet_id; }
String GameLiftGameSession::get_ip_address() const { return m_ip_address; }
int GameLiftGameSession::get_port() const { return m_port; }
int GameLiftGameSession::get_maximum_player_session_count() const { return m_maximum_player_session_count; }
int GameLiftGameSession::get_current_player_session_count() const { return m_current_player_session_count; }
String GameLiftGameSession::get_game_session_data() const { return m_game_session_data; }
String GameLiftGameSession::get_matchmaker_data() const { return m_matchmaker_data; }
String GameLiftGameSession::get_dns_name() const { return m_dns_name; }
Dictionary GameLiftGameSession::get_game_properties() const { return m_game_properties; }

// ============================================================================
// GameLiftPlayerSession Implementation
// ============================================================================

void GameLiftPlayerSession::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_player_session_id"), &GameLiftPlayerSession::get_player_session_id);
    ClassDB::bind_method(D_METHOD("get_player_id"), &GameLiftPlayerSession::get_player_id);
    ClassDB::bind_method(D_METHOD("get_game_session_id"), &GameLiftPlayerSession::get_game_session_id);
    ClassDB::bind_method(D_METHOD("get_fleet_id"), &GameLiftPlayerSession::get_fleet_id);
    ClassDB::bind_method(D_METHOD("get_ip_address"), &GameLiftPlayerSession::get_ip_address);
    ClassDB::bind_method(D_METHOD("get_dns_name"), &GameLiftPlayerSession::get_dns_name);
    ClassDB::bind_method(D_METHOD("get_port"), &GameLiftPlayerSession::get_port);
    ClassDB::bind_method(D_METHOD("get_player_data"), &GameLiftPlayerSession::get_player_data);
    ClassDB::bind_method(D_METHOD("get_status"), &GameLiftPlayerSession::get_status);
    ClassDB::bind_method(D_METHOD("get_creation_time"), &GameLiftPlayerSession::get_creation_time);
    ClassDB::bind_method(D_METHOD("get_termination_time"), &GameLiftPlayerSession::get_termination_time);

    ADD_PROPERTY(PropertyInfo(Variant::STRING, "player_session_id"), "", "get_player_session_id");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "player_id"), "", "get_player_id");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "game_session_id"), "", "get_game_session_id");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "fleet_id"), "", "get_fleet_id");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "ip_address"), "", "get_ip_address");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "dns_name"), "", "get_dns_name");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "port"), "", "get_port");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "player_data"), "", "get_player_data");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "status"), "", "get_status");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "creation_time"), "", "get_creation_time");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "termination_time"), "", "get_termination_time");
}

GameLiftPlayerSession::GameLiftPlayerSession() 
    : m_port(0), m_status(0), m_creation_time(0), m_termination_time(0) {}
GameLiftPlayerSession::~GameLiftPlayerSession() {}

void GameLiftPlayerSession::set_player_session_id(const String &id) { m_player_session_id = id; }
void GameLiftPlayerSession::set_player_id(const String &id) { m_player_id = id; }
void GameLiftPlayerSession::set_game_session_id(const String &id) { m_game_session_id = id; }
void GameLiftPlayerSession::set_fleet_id(const String &id) { m_fleet_id = id; }
void GameLiftPlayerSession::set_ip_address(const String &ip) { m_ip_address = ip; }
void GameLiftPlayerSession::set_dns_name(const String &name) { m_dns_name = name; }
void GameLiftPlayerSession::set_port(int port) { m_port = port; }
void GameLiftPlayerSession::set_player_data(const String &data) { m_player_data = data; }
void GameLiftPlayerSession::set_status(int status) { m_status = status; }
void GameLiftPlayerSession::set_creation_time(int64_t time) { m_creation_time = time; }
void GameLiftPlayerSession::set_termination_time(int64_t time) { m_termination_time = time; }

String GameLiftPlayerSession::get_player_session_id() const { return m_player_session_id; }
String GameLiftPlayerSession::get_player_id() const { return m_player_id; }
String GameLiftPlayerSession::get_game_session_id() const { return m_game_session_id; }
String GameLiftPlayerSession::get_fleet_id() const { return m_fleet_id; }
String GameLiftPlayerSession::get_ip_address() const { return m_ip_address; }
String GameLiftPlayerSession::get_dns_name() const { return m_dns_name; }
int GameLiftPlayerSession::get_port() const { return m_port; }
String GameLiftPlayerSession::get_player_data() const { return m_player_data; }
int GameLiftPlayerSession::get_status() const { return m_status; }
int64_t GameLiftPlayerSession::get_creation_time() const { return m_creation_time; }
int64_t GameLiftPlayerSession::get_termination_time() const { return m_termination_time; }

// ============================================================================
// GameLiftServer Implementation
// ============================================================================

GameLiftServer *GameLiftServer::singleton = nullptr;

void GameLiftServer::_bind_methods() {
    // Core SDK methods
    ClassDB::bind_method(D_METHOD("init_sdk"), &GameLiftServer::init_sdk);
    ClassDB::bind_method(D_METHOD("init_sdk_anywhere", "websocket_url", "auth_token", "fleet_id", "host_id", "process_id"), &GameLiftServer::init_sdk_anywhere);
    ClassDB::bind_method(D_METHOD("process_ready", "port", "log_paths"), &GameLiftServer::process_ready);
    ClassDB::bind_method(D_METHOD("process_ending"), &GameLiftServer::process_ending);
    ClassDB::bind_method(D_METHOD("activate_game_session"), &GameLiftServer::activate_game_session);
    ClassDB::bind_method(D_METHOD("destroy"), &GameLiftServer::destroy);

    // Player session management
    ClassDB::bind_method(D_METHOD("accept_player_session", "player_session_id"), &GameLiftServer::accept_player_session);
    ClassDB::bind_method(D_METHOD("remove_player_session", "player_session_id"), &GameLiftServer::remove_player_session);
    ClassDB::bind_method(D_METHOD("describe_player_sessions", "game_session_id", "player_id", "player_session_id", "player_session_status_filter", "limit"), &GameLiftServer::describe_player_sessions);

    // Game session management
    ClassDB::bind_method(D_METHOD("get_game_session_id"), &GameLiftServer::get_game_session_id);
    ClassDB::bind_method(D_METHOD("get_termination_time"), &GameLiftServer::get_termination_time);
    ClassDB::bind_method(D_METHOD("update_player_session_creation_policy", "policy"), &GameLiftServer::update_player_session_creation_policy);

    // Matchmaking backfill
    ClassDB::bind_method(D_METHOD("start_match_backfill", "ticket_id", "matchmaking_configuration_arn", "players"), &GameLiftServer::start_match_backfill);
    ClassDB::bind_method(D_METHOD("stop_match_backfill", "ticket_id", "matchmaking_configuration_arn", "game_session_arn"), &GameLiftServer::stop_match_backfill);

    // Utility methods
    ClassDB::bind_method(D_METHOD("get_sdk_version"), &GameLiftServer::get_sdk_version);
    ClassDB::bind_method(D_METHOD("is_initialized"), &GameLiftServer::is_initialized);
    ClassDB::bind_method(D_METHOD("is_process_ready"), &GameLiftServer::is_process_ready);
    ClassDB::bind_method(D_METHOD("get_current_game_session"), &GameLiftServer::get_current_game_session);
    ClassDB::bind_method(D_METHOD("get_compute_certificate"), &GameLiftServer::get_compute_certificate);
    ClassDB::bind_method(D_METHOD("get_fleet_role_credentials", "role_arn"), &GameLiftServer::get_fleet_role_credentials);

    // Signals - these are emitted when GameLift callbacks are triggered
    ADD_SIGNAL(MethodInfo("game_session_started", PropertyInfo(Variant::OBJECT, "game_session", PROPERTY_HINT_RESOURCE_TYPE, "GameLiftGameSession")));
    ADD_SIGNAL(MethodInfo("game_session_updated", PropertyInfo(Variant::OBJECT, "game_session", PROPERTY_HINT_RESOURCE_TYPE, "GameLiftGameSession"), PropertyInfo(Variant::STRING, "backfill_ticket_id"), PropertyInfo(Variant::INT, "update_reason")));
    ADD_SIGNAL(MethodInfo("process_terminate_requested"));
    ADD_SIGNAL(MethodInfo("health_check_requested"));

    // Enums
    BIND_ENUM_CONSTANT(PLAYER_SESSION_RESERVED);
    BIND_ENUM_CONSTANT(PLAYER_SESSION_ACTIVE);
    BIND_ENUM_CONSTANT(PLAYER_SESSION_COMPLETED);
    BIND_ENUM_CONSTANT(PLAYER_SESSION_TIMEDOUT);

    BIND_ENUM_CONSTANT(ACCEPT_ALL);
    BIND_ENUM_CONSTANT(DENY_ALL);
}

GameLiftServer::GameLiftServer() : m_initialized(false), m_process_ready(false) {
    if (singleton == nullptr) {
        singleton = this;
    }
}

GameLiftServer::~GameLiftServer() {
    if (m_initialized) {
        destroy();
    }
    if (singleton == this) {
        singleton = nullptr;
    }
}

GameLiftServer *GameLiftServer::get_singleton() {
    return singleton;
}

// ============================================================================
// Helper Methods
// ============================================================================

String GameLiftServer::aws_string_to_godot(const std::string &str) {
    return String(str.c_str());
}

std::string GameLiftServer::godot_string_to_aws(const String &str) {
    return std::string(str.utf8().get_data());
}

Ref<GameLiftGameSession> GameLiftServer::convert_game_session(const Aws::GameLift::Server::Model::GameSession &session) {
    Ref<GameLiftGameSession> gs;
    gs.instantiate();

    gs->set_game_session_id(aws_string_to_godot(session.GetGameSessionId()));
    gs->set_name(aws_string_to_godot(session.GetName()));
    gs->set_fleet_id(aws_string_to_godot(session.GetFleetId()));
    gs->set_ip_address(aws_string_to_godot(session.GetIpAddress()));
    gs->set_port(session.GetPort());
    gs->set_maximum_player_session_count(session.GetMaximumPlayerSessionCount());
    gs->set_game_session_data(aws_string_to_godot(session.GetGameSessionData()));
    gs->set_matchmaker_data(aws_string_to_godot(session.GetMatchmakerData()));
    gs->set_dns_name(aws_string_to_godot(session.GetDnsName()));

    // Convert game properties
    Dictionary props;
    for (const auto &prop : session.GetGameProperties()) {
        props[aws_string_to_godot(prop.GetKey())] = aws_string_to_godot(prop.GetValue());
    }
    gs->set_game_properties(props);

    return gs;
}

Ref<GameLiftPlayerSession> GameLiftServer::convert_player_session(const Aws::GameLift::Server::Model::PlayerSession &session) {
    Ref<GameLiftPlayerSession> ps;
    ps.instantiate();

    ps->set_player_session_id(aws_string_to_godot(session.GetPlayerSessionId()));
    ps->set_player_id(aws_string_to_godot(session.GetPlayerId()));
    ps->set_game_session_id(aws_string_to_godot(session.GetGameSessionId()));
    ps->set_fleet_id(aws_string_to_godot(session.GetFleetId()));
    ps->set_ip_address(aws_string_to_godot(session.GetIpAddress()));
    ps->set_dns_name(aws_string_to_godot(session.GetDnsName()));
    ps->set_port(session.GetPort());
    ps->set_player_data(aws_string_to_godot(session.GetPlayerData()));
    ps->set_status(static_cast<int>(session.GetStatus()));
    ps->set_creation_time(session.GetCreationTime());
    ps->set_termination_time(session.GetTerminationTime());

    return ps;
}

// ============================================================================
// SDK Callbacks (Static)
// ============================================================================

void GameLiftServer::on_start_game_session_callback(Aws::GameLift::Server::Model::GameSession gameSession) {
    if (singleton) {
        singleton->m_current_game_session = singleton->convert_game_session(gameSession);
        singleton->emit_signal("game_session_started", singleton->m_current_game_session);
    }
}

void GameLiftServer::on_update_game_session_callback(Aws::GameLift::Server::Model::UpdateGameSession updateGameSession) {
    if (singleton) {
        Ref<GameLiftGameSession> gs = singleton->convert_game_session(updateGameSession.GetGameSession());
        singleton->m_current_game_session = gs;

        String backfill_ticket_id = aws_string_to_godot(updateGameSession.GetBackfillTicketId());
        int update_reason = static_cast<int>(updateGameSession.GetUpdateReason());

        singleton->emit_signal("game_session_updated", gs, backfill_ticket_id, update_reason);
    }
}

void GameLiftServer::on_process_terminate_callback() {
    if (singleton) {
        singleton->emit_signal("process_terminate_requested");
    }
}

bool GameLiftServer::on_health_check_callback() {
    if (singleton) {
        singleton->emit_signal("health_check_requested");
    }
    // Return true to indicate healthy. In a real implementation, you might
    // want to make this configurable or check actual health status.
    return true;
}

// ============================================================================
// Core SDK Methods
// ============================================================================

Ref<GameLiftOutcome> GameLiftServer::init_sdk() {
    Ref<GameLiftOutcome> outcome;
    outcome.instantiate();

    auto result = Aws::GameLift::Server::InitSDK();

    if (result.IsSuccess()) {
        outcome->set_success(true);
        m_initialized = true;
        UtilityFunctions::print("[GameLift] SDK initialized successfully for managed EC2 fleet");
    } else {
        outcome->set_success(false);
        outcome->set_error_message(aws_string_to_godot(result.GetError().GetErrorMessage()));
        outcome->set_error_type(static_cast<int>(result.GetError().GetErrorType()));
        UtilityFunctions::printerr("[GameLift] Failed to initialize SDK: ", outcome->get_error_message());
    }

    return outcome;
}

Ref<GameLiftOutcome> GameLiftServer::init_sdk_anywhere(
    const String &websocket_url,
    const String &auth_token,
    const String &fleet_id,
    const String &host_id,
    const String &process_id
) {
    Ref<GameLiftOutcome> outcome;
    outcome.instantiate();

    Aws::GameLift::Server::Model::ServerParameters serverParameters(
        godot_string_to_aws(websocket_url),
        godot_string_to_aws(auth_token),
        godot_string_to_aws(fleet_id),
        godot_string_to_aws(host_id),
        godot_string_to_aws(process_id)
    );

    auto result = Aws::GameLift::Server::InitSDK(serverParameters);

    if (result.IsSuccess()) {
        outcome->set_success(true);
        m_initialized = true;
        UtilityFunctions::print("[GameLift] SDK initialized successfully for Anywhere fleet");
    } else {
        outcome->set_success(false);
        outcome->set_error_message(aws_string_to_godot(result.GetError().GetErrorMessage()));
        outcome->set_error_type(static_cast<int>(result.GetError().GetErrorType()));
        UtilityFunctions::printerr("[GameLift] Failed to initialize SDK for Anywhere: ", outcome->get_error_message());
    }

    return outcome;
}

Ref<GameLiftOutcome> GameLiftServer::process_ready(int port, const PackedStringArray &log_paths) {
    Ref<GameLiftOutcome> outcome;
    outcome.instantiate();

    if (!m_initialized) {
        outcome->set_success(false);
        outcome->set_error_message("SDK not initialized. Call init_sdk() first.");
        return outcome;
    }

    // Convert log paths
    std::vector<std::string> aws_log_paths;
    for (int i = 0; i < log_paths.size(); i++) {
        aws_log_paths.push_back(godot_string_to_aws(log_paths[i]));
    }

    // Set up process parameters with callbacks
    Aws::GameLift::Server::ProcessParameters processParams(
        on_start_game_session_callback,
        on_update_game_session_callback,
        on_process_terminate_callback,
        on_health_check_callback,
        port,
        Aws::GameLift::Server::LogParameters(aws_log_paths)
    );

    auto result = Aws::GameLift::Server::ProcessReady(processParams);

    if (result.IsSuccess()) {
        outcome->set_success(true);
        m_process_ready = true;
        UtilityFunctions::print("[GameLift] Process ready on port ", port);
    } else {
        outcome->set_success(false);
        outcome->set_error_message(aws_string_to_godot(result.GetError().GetErrorMessage()));
        outcome->set_error_type(static_cast<int>(result.GetError().GetErrorType()));
        UtilityFunctions::printerr("[GameLift] ProcessReady failed: ", outcome->get_error_message());
    }

    return outcome;
}

Ref<GameLiftOutcome> GameLiftServer::process_ending() {
    Ref<GameLiftOutcome> outcome;
    outcome.instantiate();

    auto result = Aws::GameLift::Server::ProcessEnding();

    if (result.IsSuccess()) {
        outcome->set_success(true);
        m_process_ready = false;
        UtilityFunctions::print("[GameLift] Process ending signaled");
    } else {
        outcome->set_success(false);
        outcome->set_error_message(aws_string_to_godot(result.GetError().GetErrorMessage()));
        outcome->set_error_type(static_cast<int>(result.GetError().GetErrorType()));
    }

    return outcome;
}

Ref<GameLiftOutcome> GameLiftServer::activate_game_session() {
    Ref<GameLiftOutcome> outcome;
    outcome.instantiate();

    auto result = Aws::GameLift::Server::ActivateGameSession();

    if (result.IsSuccess()) {
        outcome->set_success(true);
        UtilityFunctions::print("[GameLift] Game session activated");
    } else {
        outcome->set_success(false);
        outcome->set_error_message(aws_string_to_godot(result.GetError().GetErrorMessage()));
        outcome->set_error_type(static_cast<int>(result.GetError().GetErrorType()));
    }

    return outcome;
}

void GameLiftServer::destroy() {
    if (m_initialized) {
        Aws::GameLift::Server::Destroy();
        m_initialized = false;
        m_process_ready = false;
        UtilityFunctions::print("[GameLift] SDK destroyed");
    }
}

// ============================================================================
// Player Session Management
// ============================================================================

Ref<GameLiftOutcome> GameLiftServer::accept_player_session(const String &player_session_id) {
    Ref<GameLiftOutcome> outcome;
    outcome.instantiate();

    auto result = Aws::GameLift::Server::AcceptPlayerSession(godot_string_to_aws(player_session_id).c_str());

    if (result.IsSuccess()) {
        outcome->set_success(true);
        UtilityFunctions::print("[GameLift] Accepted player session: ", player_session_id);
    } else {
        outcome->set_success(false);
        outcome->set_error_message(aws_string_to_godot(result.GetError().GetErrorMessage()));
        outcome->set_error_type(static_cast<int>(result.GetError().GetErrorType()));
    }

    return outcome;
}

Ref<GameLiftOutcome> GameLiftServer::remove_player_session(const String &player_session_id) {
    Ref<GameLiftOutcome> outcome;
    outcome.instantiate();

    auto result = Aws::GameLift::Server::RemovePlayerSession(godot_string_to_aws(player_session_id).c_str());

    if (result.IsSuccess()) {
        outcome->set_success(true);
        UtilityFunctions::print("[GameLift] Removed player session: ", player_session_id);
    } else {
        outcome->set_success(false);
        outcome->set_error_message(aws_string_to_godot(result.GetError().GetErrorMessage()));
        outcome->set_error_type(static_cast<int>(result.GetError().GetErrorType()));
    }

    return outcome;
}

Array GameLiftServer::describe_player_sessions(
    const String &game_session_id,
    const String &player_id,
    const String &player_session_id,
    const String &player_session_status_filter,
    int limit
) {
    Array sessions;

    Aws::GameLift::Server::Model::DescribePlayerSessionsRequest request;

    if (!game_session_id.is_empty()) {
        request.SetGameSessionId(godot_string_to_aws(game_session_id));
    }
    if (!player_id.is_empty()) {
        request.SetPlayerId(godot_string_to_aws(player_id));
    }
    if (!player_session_id.is_empty()) {
        request.SetPlayerSessionId(godot_string_to_aws(player_session_id));
    }
    if (!player_session_status_filter.is_empty()) {
        request.SetPlayerSessionStatusFilter(godot_string_to_aws(player_session_status_filter));
    }
    if (limit > 0) {
        request.SetLimit(limit);
    }

    auto result = Aws::GameLift::Server::DescribePlayerSessions(request);

    if (result.IsSuccess()) {
        for (const auto &session : result.GetResult().GetPlayerSessions()) {
            sessions.append(convert_player_session(session));
        }
    } else {
        UtilityFunctions::printerr("[GameLift] DescribePlayerSessions failed: ", 
            aws_string_to_godot(result.GetError().GetErrorMessage()));
    }

    return sessions;
}

// ============================================================================
// Game Session Management
// ============================================================================

String GameLiftServer::get_game_session_id() {
    auto result = Aws::GameLift::Server::GetGameSessionId();
    if (result.IsSuccess()) {
        return aws_string_to_godot(result.GetResult());
    }
    return "";
}

int64_t GameLiftServer::get_termination_time() {
    auto result = Aws::GameLift::Server::GetTerminationTime();
    if (result.IsSuccess()) {
        return result.GetResult();
    }
    return -1;
}

Ref<GameLiftOutcome> GameLiftServer::update_player_session_creation_policy(PlayerSessionCreationPolicy policy) {
    Ref<GameLiftOutcome> outcome;
    outcome.instantiate();

    Aws::GameLift::Server::Model::PlayerSessionCreationPolicy aws_policy;
    switch (policy) {
        case ACCEPT_ALL:
            aws_policy = Aws::GameLift::Server::Model::PlayerSessionCreationPolicy::ACCEPT_ALL;
            break;
        case DENY_ALL:
            aws_policy = Aws::GameLift::Server::Model::PlayerSessionCreationPolicy::DENY_ALL;
            break;
        default:
            aws_policy = Aws::GameLift::Server::Model::PlayerSessionCreationPolicy::ACCEPT_ALL;
    }

    auto result = Aws::GameLift::Server::UpdatePlayerSessionCreationPolicy(aws_policy);

    if (result.IsSuccess()) {
        outcome->set_success(true);
    } else {
        outcome->set_success(false);
        outcome->set_error_message(aws_string_to_godot(result.GetError().GetErrorMessage()));
        outcome->set_error_type(static_cast<int>(result.GetError().GetErrorType()));
    }

    return outcome;
}

// ============================================================================
// Matchmaking Backfill
// ============================================================================

Ref<GameLiftOutcome> GameLiftServer::start_match_backfill(
    const String &ticket_id,
    const String &matchmaking_configuration_arn,
    const Array &players
) {
    Ref<GameLiftOutcome> outcome;
    outcome.instantiate();

    Aws::GameLift::Server::Model::StartMatchBackfillRequest request;
    request.SetTicketId(godot_string_to_aws(ticket_id));
    request.SetMatchmakingConfigurationArn(godot_string_to_aws(matchmaking_configuration_arn));

    // Get game session ARN from current session
    auto gsIdResult = Aws::GameLift::Server::GetGameSessionId();
    if (gsIdResult.IsSuccess()) {
        request.SetGameSessionArn(gsIdResult.GetResult());
    }

    // Convert players array to SDK format
    std::vector<Aws::GameLift::Server::Model::Player> aws_players;
    for (int i = 0; i < players.size(); i++) {
        Dictionary player_dict = players[i];
        Aws::GameLift::Server::Model::Player aws_player;

        if (player_dict.has("player_id")) {
            aws_player.SetPlayerId(godot_string_to_aws(player_dict["player_id"]));
        }
        if (player_dict.has("team")) {
            aws_player.SetTeam(godot_string_to_aws(player_dict["team"]));
        }

        // Handle player attributes
        if (player_dict.has("attributes")) {
            Dictionary attrs = player_dict["attributes"];
            std::map<std::string, Aws::GameLift::Server::Model::AttributeValue> aws_attrs;

            Array keys = attrs.keys();
            for (int j = 0; j < keys.size(); j++) {
                String key = keys[j];
                Variant value = attrs[key];

                Aws::GameLift::Server::Model::AttributeValue attr_value;

                // Handle different attribute types
                switch (value.get_type()) {
                    case Variant::FLOAT:
                    case Variant::INT:
                        attr_value = Aws::GameLift::Server::Model::AttributeValue(static_cast<double>(value));
                        break;
                    case Variant::STRING:
                        attr_value = Aws::GameLift::Server::Model::AttributeValue(godot_string_to_aws(value));
                        break;
                    default:
                        attr_value = Aws::GameLift::Server::Model::AttributeValue(godot_string_to_aws(String(value)));
                        break;
                }

                aws_attrs[godot_string_to_aws(key)] = attr_value;
            }
            aws_player.SetPlayerAttributes(aws_attrs);
        }

        // Handle latency in ms
        if (player_dict.has("latency_ms")) {
            Dictionary latency_dict = player_dict["latency_ms"];
            std::map<std::string, int> latency_map;
            Array latency_keys = latency_dict.keys();
            for (int j = 0; j < latency_keys.size(); j++) {
                String region = latency_keys[j];
                latency_map[godot_string_to_aws(region)] = latency_dict[region];
            }
            aws_player.SetLatencyInMs(latency_map);
        }

        aws_players.push_back(aws_player);
    }
    request.SetPlayers(aws_players);

    auto result = Aws::GameLift::Server::StartMatchBackfill(request);

    if (result.IsSuccess()) {
        outcome->set_success(true);
        UtilityFunctions::print("[GameLift] Match backfill started with ticket: ", ticket_id);
    } else {
        outcome->set_success(false);
        outcome->set_error_message(aws_string_to_godot(result.GetError().GetErrorMessage()));
        outcome->set_error_type(static_cast<int>(result.GetError().GetErrorType()));
    }

    return outcome;
}

Ref<GameLiftOutcome> GameLiftServer::stop_match_backfill(
    const String &ticket_id,
    const String &matchmaking_configuration_arn,
    const String &game_session_arn
) {
    Ref<GameLiftOutcome> outcome;
    outcome.instantiate();

    Aws::GameLift::Server::Model::StopMatchBackfillRequest request;
    request.SetTicketId(godot_string_to_aws(ticket_id));
    request.SetMatchmakingConfigurationArn(godot_string_to_aws(matchmaking_configuration_arn));
    request.SetGameSessionArn(godot_string_to_aws(game_session_arn));

    auto result = Aws::GameLift::Server::StopMatchBackfill(request);

    if (result.IsSuccess()) {
        outcome->set_success(true);
        UtilityFunctions::print("[GameLift] Match backfill stopped for ticket: ", ticket_id);
    } else {
        outcome->set_success(false);
        outcome->set_error_message(aws_string_to_godot(result.GetError().GetErrorMessage()));
        outcome->set_error_type(static_cast<int>(result.GetError().GetErrorType()));
    }

    return outcome;
}

// ============================================================================
// Utility Methods
// ============================================================================

String GameLiftServer::get_sdk_version() {
    auto result = Aws::GameLift::Server::GetSdkVersion();
    if (result.IsSuccess()) {
        return aws_string_to_godot(result.GetResult());
    }
    return "unknown";
}

bool GameLiftServer::is_initialized() const {
    return m_initialized;
}

bool GameLiftServer::is_process_ready() const {
    return m_process_ready;
}

Ref<GameLiftGameSession> GameLiftServer::get_current_game_session() const {
    return m_current_game_session;
}

Dictionary GameLiftServer::get_compute_certificate() {
    Dictionary result_dict;

    auto result = Aws::GameLift::Server::GetComputeCertificate();

    if (result.IsSuccess()) {
        result_dict["success"] = true;
        result_dict["certificate_path"] = aws_string_to_godot(result.GetResult().GetCertificatePath());
        result_dict["compute_name"] = aws_string_to_godot(result.GetResult().GetComputeName());
    } else {
        result_dict["success"] = false;
        result_dict["error"] = aws_string_to_godot(result.GetError().GetErrorMessage());
    }

    return result_dict;
}

Dictionary GameLiftServer::get_fleet_role_credentials(const String &role_arn) {
    Dictionary result_dict;

    Aws::GameLift::Server::Model::GetFleetRoleCredentialsRequest request;
    request.SetRoleArn(godot_string_to_aws(role_arn));

    auto result = Aws::GameLift::Server::GetFleetRoleCredentials(request);

    if (result.IsSuccess()) {
        result_dict["success"] = true;
        result_dict["access_key_id"] = aws_string_to_godot(result.GetResult().GetAccessKeyId());
        result_dict["secret_access_key"] = aws_string_to_godot(result.GetResult().GetSecretAccessKey());
        result_dict["session_token"] = aws_string_to_godot(result.GetResult().GetSessionToken());

        // Convert tm struct to Unix timestamp.
        tm expiration_tm = result.GetResult().GetExpiration();
        time_t expiration_time = mktime(&expiration_tm);
        result_dict["expiration"] = static_cast<int64_t>(expiration_time);
    } else {
        result_dict["success"] = false;
        result_dict["error"] = aws_string_to_godot(result.GetError().GetErrorMessage());
    }

    return result_dict;
}
