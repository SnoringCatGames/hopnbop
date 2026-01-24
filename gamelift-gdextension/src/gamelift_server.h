#ifndef GAMELIFT_SERVER_H
#define GAMELIFT_SERVER_H

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <aws/gamelift/server/GameLiftServerAPI.h>

#include <functional>
#include <string>
#include <vector>

namespace godot
{

    // Forward declarations
    class GameLiftGameSession;
    class GameLiftPlayerSession;

    // ============================================================================
    // GameLiftOutcome - Wrapper for SDK operation results
    // ============================================================================
    class GameLiftOutcome : public RefCounted
    {
        GDCLASS(GameLiftOutcome, RefCounted)

    private:
        bool m_success;
        String m_error_message;
        int m_error_type;

    protected:
        static void _bind_methods();

    public:
        GameLiftOutcome();
        ~GameLiftOutcome();

        void set_success(bool success);
        bool is_success() const;

        void set_error_message(const String &message);
        String get_error_message() const;

        void set_error_type(int type);
        int get_error_type() const;
    };

    // ============================================================================
    // GameLiftGameSession - Wrapper for game session data
    // ============================================================================
    class GameLiftGameSession : public RefCounted
    {
        GDCLASS(GameLiftGameSession, RefCounted)

    private:
        String m_game_session_id;
        String m_name;
        String m_fleet_id;
        String m_ip_address;
        int m_port;
        int m_maximum_player_session_count;
        int m_current_player_session_count;
        String m_game_session_data;
        String m_matchmaker_data;
        String m_dns_name;
        Dictionary m_game_properties;

    protected:
        static void _bind_methods();

    public:
        GameLiftGameSession();
        ~GameLiftGameSession();

        // Setters (used internally)
        void set_game_session_id(const String &id);
        void set_name(const String &name);
        void set_fleet_id(const String &id);
        void set_ip_address(const String &ip);
        void set_port(int port);
        void set_maximum_player_session_count(int count);
        void set_current_player_session_count(int count);
        void set_game_session_data(const String &data);
        void set_matchmaker_data(const String &data);
        void set_dns_name(const String &name);
        void set_game_properties(const Dictionary &props);

        // Getters (exposed to GDScript)
        String get_game_session_id() const;
        String get_name() const;
        String get_fleet_id() const;
        String get_ip_address() const;
        int get_port() const;
        int get_maximum_player_session_count() const;
        int get_current_player_session_count() const;
        String get_game_session_data() const;
        String get_matchmaker_data() const;
        String get_dns_name() const;
        Dictionary get_game_properties() const;
    };

    // ============================================================================
    // GameLiftPlayerSession - Wrapper for player session data
    // ============================================================================
    class GameLiftPlayerSession : public RefCounted
    {
        GDCLASS(GameLiftPlayerSession, RefCounted)

    private:
        String m_player_session_id;
        String m_player_id;
        String m_game_session_id;
        String m_fleet_id;
        String m_ip_address;
        String m_dns_name;
        int m_port;
        String m_player_data;
        int m_status;
        int64_t m_creation_time;
        int64_t m_termination_time;

    protected:
        static void _bind_methods();

    public:
        GameLiftPlayerSession();
        ~GameLiftPlayerSession();

        void set_player_session_id(const String &id);
        void set_player_id(const String &id);
        void set_game_session_id(const String &id);
        void set_fleet_id(const String &id);
        void set_ip_address(const String &ip);
        void set_dns_name(const String &name);
        void set_port(int port);
        void set_player_data(const String &data);
        void set_status(int status);
        void set_creation_time(int64_t time);
        void set_termination_time(int64_t time);

        String get_player_session_id() const;
        String get_player_id() const;
        String get_game_session_id() const;
        String get_fleet_id() const;
        String get_ip_address() const;
        String get_dns_name() const;
        int get_port() const;
        String get_player_data() const;
        int get_status() const;
        int64_t get_creation_time() const;
        int64_t get_termination_time() const;
    };

    // ============================================================================
    // GameLiftServer - Main singleton for GameLift Server SDK integration
    // ============================================================================
    class GameLiftServer : public Node
    {
        GDCLASS(GameLiftServer, Node)

    private:
        static GameLiftServer *singleton;
        bool m_initialized;
        bool m_process_ready;

        // Store current game session for callbacks
        Ref<GameLiftGameSession> m_current_game_session;

        // Helper methods
        static String aws_string_to_godot(const std::string &str);
        static std::string godot_string_to_aws(const String &str);
        Ref<GameLiftGameSession> convert_game_session(const Aws::GameLift::Server::Model::GameSession &session);
        Ref<GameLiftPlayerSession> convert_player_session(const Aws::GameLift::Server::Model::PlayerSession &session);

        // SDK Callbacks (static to work with C++ SDK)
        static void on_start_game_session_callback(Aws::GameLift::Server::Model::GameSession gameSession);
        static void on_update_game_session_callback(Aws::GameLift::Server::Model::UpdateGameSession updateGameSession);
        static void on_process_terminate_callback();
        static bool on_health_check_callback();

    protected:
        static void _bind_methods();

    public:
        // Player session status enum (mirrors SDK)
        enum PlayerSessionStatus
        {
            PLAYER_SESSION_RESERVED = 0,
            PLAYER_SESSION_ACTIVE = 1,
            PLAYER_SESSION_COMPLETED = 2,
            PLAYER_SESSION_TIMEDOUT = 3
        };

        // Player session creation policy enum
        enum PlayerSessionCreationPolicy
        {
            ACCEPT_ALL = 0,
            DENY_ALL = 1
        };

        GameLiftServer();
        ~GameLiftServer();

        static GameLiftServer *get_singleton();

        // ========================================================================
        // Core SDK Methods
        // ========================================================================

        // Initialize SDK for managed EC2 fleet (no parameters needed)
        Ref<GameLiftOutcome> init_sdk();

        // Initialize SDK for Anywhere fleet (requires parameters)
        Ref<GameLiftOutcome> init_sdk_anywhere(
            const String &websocket_url,
            const String &auth_token,
            const String &fleet_id,
            const String &host_id,
            const String &process_id);

        // Notify GameLift that server is ready to host game sessions
        Ref<GameLiftOutcome> process_ready(int port, const PackedStringArray &log_paths);

        // Notify GameLift that server process is ending
        Ref<GameLiftOutcome> process_ending();

        // Activate the game session (call from on_start_game_session after setup)
        Ref<GameLiftOutcome> activate_game_session();

        // Clean up and destroy SDK
        void destroy();

        // ========================================================================
        // Player Session Management
        // ========================================================================

        // Validate and accept a player session
        Ref<GameLiftOutcome> accept_player_session(const String &player_session_id);

        // Remove a player session (player disconnected)
        Ref<GameLiftOutcome> remove_player_session(const String &player_session_id);

        // Get information about player sessions
        Array describe_player_sessions(
            const String &game_session_id,
            const String &player_id,
            const String &player_session_id,
            const String &player_session_status_filter,
            int limit);

        // ========================================================================
        // Game Session Management
        // ========================================================================

        // Get the current game session ID
        String get_game_session_id();

        // Get the termination time (if process is being terminated)
        int64_t get_termination_time();

        // Update whether new players can join
        Ref<GameLiftOutcome> update_player_session_creation_policy(PlayerSessionCreationPolicy policy);

        // ========================================================================
        // Matchmaking Backfill
        // ========================================================================

        // Start a matchmaking backfill request
        Ref<GameLiftOutcome> start_match_backfill(
            const String &ticket_id,
            const String &matchmaking_configuration_arn,
            const Array &players // Array of Dictionaries with player data
        );

        // Stop a matchmaking backfill request
        Ref<GameLiftOutcome> stop_match_backfill(
            const String &ticket_id,
            const String &matchmaking_configuration_arn,
            const String &game_session_arn);

        // ========================================================================
        // Utility Methods
        // ========================================================================

        // Get SDK version
        String get_sdk_version();

        // Check if SDK is initialized
        bool is_initialized() const;

        // Check if process is ready
        bool is_process_ready() const;

        // Get current game session
        Ref<GameLiftGameSession> get_current_game_session() const;

        // Get compute certificate (for TLS)
        Dictionary get_compute_certificate();

        // Get fleet role credentials (for accessing other AWS services)
        Dictionary get_fleet_role_credentials(const String &role_arn);
    };

} // namespace godot

VARIANT_ENUM_CAST(godot::GameLiftServer::PlayerSessionStatus);
VARIANT_ENUM_CAST(godot::GameLiftServer::PlayerSessionCreationPolicy);

#endif // GAMELIFT_SERVER_H
