class_name PlayerStats
extends Node


# FIXME: LEFT OFF HERE: ACTUALLY: !!!!!!!!!! Attach stats to scene tree.
# - Make a separate scene for this PlayerStats script to attach to.
# - Add a MultiplayerSynchronizer node in that scene.
# - Document that this is needed in order to support efficiently networking match state.
# - Add player stats as node children of MultiplayerSpawner.


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
