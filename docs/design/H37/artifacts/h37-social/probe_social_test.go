package main

// H37 social probe (not part of the platform repo). Exercises the
// BeforeAddFriends hook with a fake Nakama module: does a caller at
// the 50-pending-outgoing cap get refused for an ids-only add, which
// is exactly what the SDK's accept_request sends?

import (
	"context"
	"database/sql"
	"testing"

	"github.com/heroiclabs/nakama-common/api"
	"github.com/heroiclabs/nakama-common/runtime"
)

type probeSocialInit struct {
	runtime.Initializer
	hook func(context.Context, runtime.Logger, *sql.DB,
		runtime.NakamaModule, *api.AddFriendsRequest,
	) (*api.AddFriendsRequest, error)
}

func (p *probeSocialInit) RegisterBeforeAddFriends(fn func(
	context.Context, runtime.Logger, *sql.DB, runtime.NakamaModule,
	*api.AddFriendsRequest) (*api.AddFriendsRequest, error)) error {
	p.hook = fn
	return nil
}

type probeSocialNk struct {
	runtime.NakamaModule
	outgoing int
}

func (f *probeSocialNk) FriendsList(_ context.Context, _ string,
	limit int, state *int, _ string,
) ([]*api.Friend, string, error) {
	out := []*api.Friend{}
	if state != nil && *state == 1 {
		for i := 0; i < f.outgoing && i < limit; i++ {
			out = append(out, &api.Friend{})
		}
	}
	return out, "", nil
}

func probeSocialHook(t *testing.T) *probeSocialInit {
	init := &probeSocialInit{}
	if err := registerFriendsLimitHook(init, newFriendsLimiter()); err != nil {
		t.Fatal(err)
	}
	return init
}

func probeSocialCtx() context.Context {
	return context.WithValue(context.Background(),
		runtime.RUNTIME_CTX_USER_ID, "caller")
}

// An accept is AddFriends{Ids:[sender]} (SDK accept_request). At 50
// outgoing pending, the hook refuses it.
func TestProbeSocialAcceptRefusedAtPendingCap(t *testing.T) {
	init := probeSocialHook(t)
	nk := &probeSocialNk{outgoing: 50}
	_, err := init.hook(probeSocialCtx(), nil, nil, nk,
		&api.AddFriendsRequest{Ids: []string{"incoming-sender"}})
	if err == nil {
		t.Fatal("expected the ids-only add (an accept) to be refused at the cap")
	}
	t.Logf("refused: %v", err)
	nk.outgoing = 49
	if _, err := init.hook(probeSocialCtx(), nil, nil, nk,
		&api.AddFriendsRequest{Ids: []string{"incoming-sender"}}); err != nil {
		t.Fatalf("49 pending should pass: %v", err)
	}
}

// Ids-only adds are not rate limited: 30 in a row all pass.
func TestProbeSocialIdsOnlyAddsNotRateLimited(t *testing.T) {
	init := probeSocialHook(t)
	nk := &probeSocialNk{outgoing: 0}
	for i := 0; i < 30; i++ {
		if _, err := init.hook(probeSocialCtx(), nil, nil, nk,
			&api.AddFriendsRequest{Ids: []string{"target"}}); err != nil {
			t.Fatalf("add %d refused: %v", i, err)
		}
	}
	// Username adds are limited at 10 per minute.
	refused := 0
	for i := 0; i < 12; i++ {
		if _, err := init.hook(probeSocialCtx(), nil, nil, nk,
			&api.AddFriendsRequest{Usernames: []string{"u"}}); err != nil {
			refused++
		}
	}
	if refused != 2 {
		t.Fatalf("expected 2 of 12 username adds refused, got %d", refused)
	}
}
