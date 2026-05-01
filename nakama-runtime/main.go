// Snoring Cat platform Nakama runtime modules.
//
// Built into a Go plugin via the heroiclabs/nakama-pluginbuilder
// image and mounted at /nakama/data/modules/snoringcat.so.
// Nakama loads the plugin at startup and calls InitModule.
//
// Hooks registered (when EDGEGAP_TOKEN is set):
//   - MatchmakerMatched: allocates an Edgegap deployment for the
//     matched players and notifies them with connection info.
//
// RPCs registered:
//   - register_server: game server checks in after boot.
//   - match_end: game server posts match results.
//   - bulk_import: Phase E migration RPC.
//   - runtime_status: read-only probe of build + config (always
//     registered, even when other init steps fall back).
package main

import (
	"context"
	"database/sql"

	"github.com/heroiclabs/nakama-common/runtime"
)

// InitModule is the entry point Nakama calls when loading the
// plugin.
func InitModule(
	ctx context.Context,
	logger runtime.Logger,
	db *sql.DB,
	nk runtime.NakamaModule,
	initializer runtime.Initializer,
) error {
	env, _ := ctx.Value(runtime.RUNTIME_CTX_ENV).(map[string]string)
	if env == nil {
		env = map[string]string{}
	}

	edgegapToken := env["EDGEGAP_TOKEN"]
	appName := env["EDGEGAP_APP_NAME"]
	if appName == "" {
		appName = "hopnbop-server"
	}
	appVersion := env["EDGEGAP_APP_VERSION"]
	if appVersion == "" {
		appVersion = "v1"
	}

	// Register the status probe first so the runtime is
	// diagnosable even if a downstream init step fails or is
	// skipped because of missing config.
	matchmakerHookEnabled := edgegapToken != ""
	statusFn := statusRpcFactory(runtimeStatusConfig{
		EdgegapAppName:       appName,
		EdgegapAppVersion:    appVersion,
		EdgegapTokenSet:      edgegapToken != "",
		MatchmakerHookActive: matchmakerHookEnabled,
	})
	if err := initializer.RegisterRpc("runtime_status", statusFn); err != nil {
		return err
	}

	if !matchmakerHookEnabled {
		logger.Warn(
			"EDGEGAP_TOKEN not set; matchmaker_matched hook is" +
				" not registered. Players will pair but never" +
				" receive match_ready notifications. Set the" +
				" env var on the Nakama host and restart the" +
				" container to recover.")
	} else {
		alloc := &fleetAllocator{
			edgegap: &edgegapClient{
				token: edgegapToken,
			},
			appName:    appName,
			appVersion: appVersion,
		}
		if err := initializer.RegisterMatchmakerMatched(
			alloc.OnMatchmakerMatched); err != nil {
			return err
		}
	}

	lifecycle := &matchLifecycle{}
	if err := initializer.RegisterRpc("register_server", lifecycle.RegisterServerRpc); err != nil {
		return err
	}
	if err := initializer.RegisterRpc("match_end", lifecycle.MatchEndRpc); err != nil {
		return err
	}
	// Phase E migration RPC.
	if err := initializer.RegisterRpc("bulk_import", bulkImportRpc); err != nil {
		return err
	}

	logger.Info(
		"snoringcat-platform runtime loaded (build=%s app=%s version=%s edgegap=%t)",
		BuildID, appName, appVersion, matchmakerHookEnabled)
	return nil
}
