class_name Authority
extends RefCounted

# 0 means unowned/AI-controlled -- only ever reachable via a local (not RPC)
# call on the server, so any requester is fine. Otherwise the requester must
# be the actor's own owning peer.
static func can_perform(action: Action, requester_id: int) -> bool:
	return action.actor.owner_id == 0 or action.actor.owner_id == requester_id
