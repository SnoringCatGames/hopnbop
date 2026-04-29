// Snoring Cat platform Nakama runtime modules.
//
// Built into a Go plugin via the heroiclabs/nakama-pluginbuilder
// image and mounted at /nakama/data/modules/snoringcat.so.
// Nakama loads the plugin at startup and calls InitModule.
//
// Hooks registered:
//   - MatchmakerMatched: allocates an Edgegap deployment for the
//     matched players and notifies them with connection info.
//
// RPCs registered:
//   - register_server: game server checks in after boot.
//   - match_end: game server posts match results.
package main

import (
	"context"
	"database/sql"
	"errors"

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
	if edgegapToken == "" {
		return errors.New("EDGEGAP_TOKEN not set in runtime.env")
	}
	appName := env["EDGEGAP_APP_NAME"]
	if appName == "" {
		appName = "hopnbop-server"
	}
	appVersion := env["EDGEGAP_APP_VERSION"]
	if appVersion == "" {
		appVersion = "v1"
	}

	alloc := &fleetAllocator{
		edgegap: &edgegapClient{
			token: edgegapToken,
		},
		appName:    appName,
		appVersion: appVersion,
	}

	if err := initializer.RegisterMatchmakerMatched(alloc.OnMatchmakerMatched); err != nil {
		return err
	}

	lifecycle := &matchLifecycle{}
	if err := initializer.RegisterRpc("register_server", lifecycle.RegisterServerRpc); err != nil {
		return err
	}
	if err := initializer.RegisterRpc("match_end", lifecycle.MatchEndRpc); err != nil {
		return err
	}

	logger.Info("snoringcat-platform runtime loaded (app=%s version=%s)", appName, appVersion)
	return nil
}
