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

State machine `Height(h)` representing the operation of a height `h` of consensus.

The considered set of states are:

- Unstarted
- Round(r), where `r` is a natural number
- Decided

The table below summarizes the state transitions in the `Height(h)` state machine.
The `Ref` column refers to the line of the pseudo-code where the events can be found.

| From | To | Event | Action | Ref |
|-------|-----------|-----------|--------|-----|
| Unstarted | Round(0) | `start` | send `start` to `Round(0)` | L10, L54 |
| Round(r) | Decided | `decide(v)` | send `kill` to every `Round(r)` <br> send `start` to `Height(h+1)` | L49 |
| Round(r) | Round(r+1) | `next_round(r+1)` | send `start` to `Round(r+1)` | L65 |
| Round(r) | Round(r') | `next_round(r')` | send `start` to `Round(r')` | L55 |

A height `h` consists of multiple rounds of consensus, always starting from
round `0`.
The `Unstarted` state is intented to store events and messages regarding height `h`
before its execution is actually started.

Each round `r` of consensus is represented by a state machine `Round(r)`.
There is a single round _in progress_ at a time, which is always the last
`Round(r)` state machine to receive the `start` command.

The height is concluded when a decision is reached in _any_ of its rounds.
The `Decided` state is intented to represent that a decision has been reached,
while it also allows storing the summary of a decided height.

Once the node moves to the `Decided` state of a height, the operation of
_every_ round `Round(r)` should be concluded.
The representation of this transition needs to be improved, for now it is
considered that the corresponding `Round(r)` state machines are killed.

A round `r` may not succeed on reaching a decision.
In this case, the successive round `r+1` is started.
The uncessful `Round(r)` state machine is not killed at this point, as messages
referring to that round can still be required for the operation of future rounds.

While in a round `r`, a node may realize that several nodes are already in a
future round `r' > r`.
When this happens, the node switches to round `r'`, skipping both the current
and the possible intermediate rounds.

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

- Unstarted
- InProgress
  - propose
  - prevote
  - precommit
- Stalled
- Decided

The table below summarizes the state transitions within `Round(r)`, considering the substates within `InProgress` state.
The `Ref` column refers to the line of the pseudo-code where the events can be found.

| From | To | Event | Action | Ref |
|-------|-----------|-----------|--------|-----|
| Unstarted | propose | `start` with `proposer(h, r) = p` | `proposal = getValue()` <br>  **broadcast** `⟨PROPOSAL, h, r, proposal, validRound⟩` | L19 |
| Unstarted | propose | `start` with `proposer(h, r) != p` (optional restriction) | schedule `TimeoutPropose(h, r)` | L21 |
| propose | prevote | `⟨PROPOSAL, h, r, v, −1⟩` | broadcast `⟨PREVOTE, h, r, {id(v), nil}⟩` | L22 |
| propose | prevote | `⟨PROPOSAL, h, r, v, vr⟩` <br> `2f + 1 ⟨PREVOTE, h, vr, id(v)⟩` with `vr < r` | broadcast `⟨PREVOTE, h, r, {id(v), nil}⟩` | L28 |
| propose | prevote | `TimeoutPropose(h, r)` | broadcast `⟨PREVOTE, h, r, nil⟩` | L57 |
| prevote  | prevote   | `2f + 1 ⟨PREVOTE, h, r, *⟩` <br> for the first time | schedule `TimeoutPrevote(h, r)⟩` | L34  |
| prevote  | precommit | `⟨PROPOSAL, h, r, v, ∗⟩` <br> `2f + 1 ⟨PREVOTE, h, r, id(v)⟩` <br> for the first time | broadcast `⟨PRECOMMIT, h, r, id(v)⟩` <br> update `lockedValue, lockedRound` <br> update `validValue, validRound` | L36 |
| prevote  | precommit | `2f + 1 ⟨PREVOTE, h, r, nil⟩` | broadcast `⟨PRECOMMIT, h, r, nil⟩` | L44 |
| prevote  | precommit | `TimeoutPrevote(h, r)` | broadcast `⟨PRECOMMIT, h, r, nil⟩` | L61 |
| precommit  | precommit | `⟨PROPOSAL, h, r, v, ∗⟩` <br>  `2f + 1 ⟨PREVOTE, h, r, id(v)⟩` <br> for the first time | update `validValue, validRound` | L36 |

The table below summarizes the state transitions within the major states of `Round(r)`.
The `Ref` column refers to the line of the pseudo-code where the events can be found.

| From | To | Event | Action | Ref |
|-------|-----------|-----------|--------|-----|
| InProgress | InProgress | `2f + 1 ⟨PRECOMMIT, h, r, *⟩` <br> for the first time | schedule `TimeoutPrecommit(h, r)` | L47 |
| InProgress | Stalled | `TimeoutPrecommit(h, r)` | emit `next_round(r+1)` | L65 |
| InProgress | Stalled | `2f + 1 ⟨PREVOTE, h, r', *, *⟩` with `r' > r` | emit `next_round(r')` | L55 |
| InProgress | Stalled | `2f + 1 ⟨PRECOMMIT, h, r', *, *⟩` with `r' > r` | emit `next_round(r')` | L55 |
| InProgress | Decided | `⟨PROPOSAL, h, r, v, *⟩` <br> `2f + 1 ⟨PRECOMMIT, h, r, id(v)⟩` | emit `decide(v)`  | L49 |
| Stalled | Decided | `⟨PROPOSAL, h, r, v, *⟩` <br> `2f + 1 ⟨PRECOMMIT, h, r, id(v)⟩` | emit `decide(v)`  | L49 |
