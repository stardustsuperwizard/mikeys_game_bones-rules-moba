## Authored configuration for a match's series length.
##
## Holds the only number that decides how long a match runs, so no round
## count, series length, or win threshold is written in GDScript. Authored as
## .tres resources under rules/data/match/ and assigned to MobaMatchState.
class_name MobaMatchRules
extends Resource

## Number of rounds in the series. A best-of-N match ends as soon as one team
## has won more than half of N, so an odd N cannot end in a tied series.
@export var best_of: int = 3


## Round wins one team needs to win the match: a majority of best_of.
## Integer division floors, so best_of 3 gives 2 and best_of 5 gives 3.
func rounds_to_win() -> int:
	return (best_of / 2) + 1
