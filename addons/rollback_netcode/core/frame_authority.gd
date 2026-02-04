class_name FrameAuthority
## Frame authority enumeration for rollback netcode.
##
## Indicates whether a frame's state is authoritative (confirmed by server) or
## predicted (client-side prediction pending server confirmation).

enum Type {
	## Authority is unknown or uninitialized.
	UNKNOWN,

	## Frame state is authoritative (confirmed by server).
	AUTHORITATIVE,

	## Frame state is predicted (client-side prediction, not yet confirmed).
	PREDICTED,
}
