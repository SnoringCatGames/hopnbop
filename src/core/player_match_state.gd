class_name PlayerStats
extends Node
## Match state associated with an individual player.
## 
## - This should contain state that doesn't need to sync very often (every few
##   seconds at the most).
## - State that needs to sync every frame should instead be tracked in
##   [FIXME: Reference player networked state script].


# FIXME: LEFT OFF HERE: ACTUALLY, ACTUALLY !!!!!!!!!!!!!!!!!!!!!
# - nvm, ignore my notes for separate nodes for player state.
# - Instead, re-assign a new array instance everytime the relevant state changes.
# - AND, have two scripts for state that is synced, instead of one.
# - player_match_state
#   - name, adjective, join time
# - player_interactions_state
#   - kills, deaths, bumps


# FIXME: Set this.
var bunny_name := ""
var adjective := ""
var join_time_usec := 0
# FIXME: Track this.
var kills := 0
# FIXME: Track this.
var deaths := 0
# FIXME: Track this.
## A bump happens when two bunnies collide, but neither dies.
var bumps := 0
