# Consensus protocol: state-machine

The consensus protocol consists of a sequence of **heights**,
identified by natural numbers `h`.

Each height of consensus consists of a number of **rounds**,
identified by natural numbers `r`.

Each round consists of essentially three **round steps**:
`propose`, `prevote`, and `precommit`.

<!---

## Multi-Height state-machine

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

-->

## Height state machine

State machine `Height(r)` representing the operation of a height `h` of consensus.

The considered set of states are:

- NewHeight
  - Initial state
- Round `r`, with `r` being a natural number

The table below summarizes the state transitions between the multiple `Round(r)` state machines.
The `Ref` column refers to the line of the pseudo-code where the events can be found.

| State | NextState | Condition | Action | Ref |
|-------|-----------|-----------|--------|-----|
| NewHeight | Round(0) | | | L10, L54 |
| Round(r) | Decided | `⟨PROPOSAL, h, r, v, *⟩` and `2f + 1 ⟨PRECOMMIT, h, r, id(v)⟩` | decide `v`  | L49 |
| Round(r) | Round(r) | `2f + 1 ⟨PRECOMMIT, h, r, *⟩` for the first time | schedule `TimeoutPrecommit(h, r)` | L47 |
| Round(r) | Round(r+1) | `TimeoutPrecommit(h, r)` | failed round | L65 |
| Round(r) | Round(r') | `2f + 1 ⟨PREVOTE, h, r', *, *⟩` with `r' > r` | round skipping | L55 |
| Round(r) | Round(r') | `2f + 1 ⟨PRECOMMIT, h, r', *, *⟩` with `r' > r` | round skipping | L55 |

<!---

> This is not really implemented like that:
>  - We require 2f+1 PREVOTEs or PRECOMMITs, instead of f+1 messages
>  - We only skip to the next round `roundp + 1`


## Multi-Round state-machine

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

-->

## Round state-machine

State machine `Round(r)` representing the operation of a round `r` of consensus from height `h`.

The considered set of states are:

- `newRound` (not represented in the pseudo-code)
- `propose`
- `prevote`
- `precommit`

The table below summarizes the state transitions within `Round(r)`.
The `Ref` column refers to the line of the pseudo-code where the events can be found.

| State | NextState | Condition | Action | Ref |
|-------|-----------|-----------|--------|-----|
| newRound | propose | `proposer(h, r) = p` | broadcast `⟨PROPOSAL, h, r, proposal, validRound⟩` | L19 |
| newRound | propose | `proposer(h, r) != p` (optional) | schedule `TimeoutPropose(h, r)` | L21 |
| propose | prevote | `⟨PROPOSAL, h, r, v, −1⟩` | broadcast `⟨PREVOTE, h, r, {id(v), nil}⟩` | L22 |
| propose | prevote | `⟨PROPOSAL, h, r, v, vr⟩` and `2f + 1 ⟨PREVOTE, h, vr, id(v)⟩` | broadcast `⟨PREVOTE, h, r, {id(v), nil}⟩` | L28 |
| propose | prevote | `TimeoutPropose(h, r)` | broadcast `⟨PREVOTE, h, r, nil⟩` | L57 |
| prevote  | prevote   | `2f + 1 ⟨PREVOTE, h, r, *⟩` for the first time | schedule `TimeoutPrevote(h, r)⟩` | L34  |
| prevote  | precommit | `⟨PROPOSAL, h, r, v, ∗⟩` and  `2f + 1 ⟨PREVOTE, h, r, id(v)⟩` for the first time | broadcast `⟨PRECOMMIT, h, r, id(v)⟩` <br> update `lockedValue, lockedRound, validValue, validRound` | L36 |
| prevote  | precommit | `2f + 1 ⟨PREVOTE, h, r, nil⟩` | broadcast `⟨PRECOMMIT, h, r, nil⟩` | L44 |
| prevote  | precommit | `TimeoutPrevote(h, r)` | broadcast `⟨PRECOMMIT, h, r, nil⟩` | L61 |
| precommit  | precommit | `⟨PROPOSAL, h, r, v, ∗⟩` and  `2f + 1 ⟨PREVOTE, h, r, id(v)⟩` for the first time | update `validValue, validRound` | L36 |
