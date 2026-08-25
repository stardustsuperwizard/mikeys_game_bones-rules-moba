extends Node

## Throwaway file for PR #203 / Issue #200. The next line is a comment over the
## gdlint max-line-length limit, which gdformat does not wrap, so the finding
## reaches the auto-fix session.

const DEMO_VALUE := 1


func _ready() -> void:
	print(DEMO_VALUE)
