# Consensus protocol: state-machine

The consensus protocol consists of a sequence of **heights**,
identified by natural numbers `h`.

Each height of consensus consists of a number of **rounds**,
identified by natural numbers `r`.

Each round consists of essentially three **round steps**:
`propose`, `prevote`, and `precommit`.

## Height state-machine

Proposed states for the state machine for each height `h`:

- Unstarted: 
  - Initial state
  - Can be used to store messages for unstarted height `h`
  - In the algorithm when `hp < h` and `decisionp[h] == nil`
- Started
  - Actual consensus execution
  - In the algorithm when `hp == h` and `decisionp[h] == nil`
- Decided: 
  - Final state
  - May also include the commit/execution of decided value
  - In the algorithm when `hp >= h` and `decisionp[h] != nil`


### Transition: `Unstarted` -> `Started`

```
10: upon start do StartRound(0)

54:    StartRound(0)
```

The node has started this height `h == hp`.
This transaction should initialize the consensus variables.

### Transition: `Started` -> `Decided`

```
49: upon ⟨PROPOSAL, hp, r, v, ∗⟩ from proposer(hp, r) AND 2f + 1 ⟨PRECOMMIT, hp, r, id(v)⟩ while decisionp[hp] = nil do
```

The height of consensus is decided.
The node is ready to move to the next height.

## Current height state machine

The state machine for the `Started` state of a height `h`, which is the current's node height `hp`:

- NewHeight
  - Initial state
- Round `r`, with `r` being a natural number

### Transition `NewHeight` -> `Round(0)`

```
52:   hp ← hp+1
53:   reset lockedRoundp , lockedV aluep , validRoundp and validV aluep to initial values and empty message log
54:   StartRound(0)
```

### Transition `Round(r)` -> `Round(r+1)`: failed round

The current round of the node `roundp` has not succeeded,
so that it starts the next round `roundp + 1`:

```
65: Function OnTimeoutPrecommit(height, round):
66:   if height = hp ∧ round = roundp then
67:      StartRound(roundp + 1)
```

### Transition `Round(r)` -> `Round(r')`: round skipping

The node receives a number of messages from a future round `round > roundp`,
so that it skips to that round:

```
55: upon f + 1 ⟨∗, hp, round, ∗, ∗⟩ with round > roundp do
56:   StartRound(round)
```

> This is not really implemented like that:
>  - We require 2f+1 PREVOTEs or PRECOMMITs, instead of f+1 messages
>  - We only skip to the next round `roundp + 1`

## Round state-machine

Proposed states for the state machine for each rond `r` of a height `h`:

- Unstarted
  - Initial state
  - Can be used to store messages early receives for this round
  - In the algorithm when `roundp < r` or `hp < h`
- Started
  - Actual consensus single-round execution
  - In the algorithm when `roundp == r`
- Concluded
  - State must be preserved while `hp == h`
  - In the algorithm when `roundp > r` or `hp > h`

Those states are part of the `Started` state of `Round(r)`.

## Current Round state-machine

Proposed states for the state machine for the current round `roundp` of the current height `hp`:

- NewRound
- Propose
- Prevote
- Precommit

### Transition `NewRound` -> `Propose`

If the node is the round's proposer, it broadcasts a `PROPOSAL` message.

```
14:   if proposer(hp, roundp) = p then 
(...)
19:     broadcast ⟨PROPOSAL, hp, roundp, proposal, validRoundp⟩
20:   else
21:     schedule OnTimeoutPropose(hp,roundp) to be executed after timeoutPropose(roundp)
```

### Transition `Propose` -> `Prevote`

The node broadcasts a `PREVOTE` vote message for the current round.
If the `PROPOSAL` for the round is properly received, possibly accompanied by a
quorum of associated `PREVOTE` votes, it is valid and it can be accepted by the
node, it votes for the proposed value ID.
Otherwise, it votes for `nil`:

```
22: upon ⟨PROPOSAL, hp, roundp, v, −1⟩ from proposer(hp, roundp) while stepp = propose do

28: upon ⟨PROPOSAL, hp, roundp, v, vr⟩ from proposer(hp, roundp) AND 2f + 1 ⟨PREVOTE, hp, vr, id(v)⟩ while stepp = propose∧(vr ≥ 0∧vr < roundp) do

57: Function OnTimeoutPropose(height, round):
58:    if height = hp ∧ round = roundp ∧ stepp = propose
```

### Transition `prevote` -> `precommit`

The node broadcasts a `PRECOMMIT` vote message for the current round.
If the `PROPOSAL` for the round is received, accompanied by a quorum of
associated `PREVOTE` votes for the current round,
the node votes for the proposed value.
Otherwise, it votes for `nil`.

```
36: upon ⟨PROPOSAL, hp, roundp, v, ∗⟩ from proposer(hp, roundp) AND 2f + 1 ⟨PREVOTE, hp, roundp, id(v)⟩ while valid(v) ∧ stepp ≥ prevote for the first time do

61: Function OnTimeoutPrevote(height, round) :
62:   if height = hp ∧ round = roundp ∧ stepp = prevote then
```
