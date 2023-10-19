# Messages to Events

The consensus state-machine operates on complex `Event`s that reflect the
reception of one or multiple `Message`s, combined with state elements and the
interaction with other modules.

This document overviews how messages should be handled at different stages of
the protocol.

It is assume that a process is at round `r` of height `h` of consensus, or in
short, at round `(h, r)`.

## Pending

- [ ] How to handle messages from [different heights](#different-heights) in general
- [ ] Definitions and details regarding the [round skipping](#round-skipping) mechanism
- [ ] How to limit the amount of messages from [future rounds](#future-rounds) stored
- [ ] Full mapping between messages of the [current round](#current-round) and the produced events

## Different heights

Messages with heights `h'` with either `h' < h` (past) or `h' > h` (future).

The pseudo-code description of the algorithm ignores messages from different
heights.
If we take the same approach in this specification, we have to specified
separatedly modules responsible to handle those messages.


- Past heights (`h' < h`): the consensus state machine is not affected by such
  messages. However, their reception might indicate that a peer is lagging
  behind in the protocol, and need to be synchronized.
  - In CometBFT's implementation we handle message from the previous height
    (`h' = h - 1`) for the `LastCommit` vote set. This only happens during the
    first step of the first round (`r = 0`) of a height.
- Future heights (`h' > h`): the consensus state machine is not able to process
  message from future heights in a proper way, as the validator set for them is
  not known. However, once the process reaches this height `h'`, those messages
  are _required_ for proper operation. There are two options here:
  1. Buffer a limited amount of such messages
  2. Assume that the communication subsystem (p2p) is able to retrieve (ask for
     retransmission) of them when the process reaches height `h'`.
     Notice that this option implies that processs keeps a minimal set of
     consensus messages that enables peers lagging behind to decide a past height. 

## Previous rounds

Messages from rounds `(h, r')` with `r' < r`: same height `h` but previous round `r'`.

The consensus state machine requires receiving and processing messages from
previous rounds:

- `PREVOTE` messages can produce a Proof of Lock (POL) `2f + 1 ⟨PREVOTE, h, vr, id(v)⟩`
  needed for accepting `PROPOSAL(h, r, v, vr)` message from the current round,
  where `vr == r' < r` (L28).
- `PRECOMMIT` messages can produce a Precommit quorum `2f + 1 ⟨PRECOMMIT, h, r', id(v)⟩`
  that leads to the decision of `v` at round `r'` (L49).
- `PROPOSAL` messages can be required to match a produced Precommit quorum (L49).
  - Associated full value messages are required to produce the `⟨PROPOSAL, h, r', v, *⟩` event

The production of the enumerated events from previous rounds should be
identitical to the production of events from messages from the [current round](#current-round).

## Future rounds

Messages from rounds `(h, r')` with `r' > r`: same height `h` but future round `r'`.

### Round skipping

The consensus state machine requires receiving and processing messages from
future rounds for enabling the _round skipping_ mechanism, defined as follows
in the pseudo-code:

```
55: upon f + 1 ⟨∗, hp, round, ∗, ∗⟩ with round > roundp do
56:   StartRound(round)
```

The current interpretation of this rule is that messages from a round `r' > r`
are received from `f + 1` voting-power equivalent distint senders.
This means, that at least `1` correct process is at round `r'`.

While this threshould does not need to be adopted (it can be configurable),
messages from a future round should initially have their unique senders counted.
Once the round skip treshould of processs is reached, the corresponding event
should be produced.

### Limits

The same reasoning applied for messages from [future heights](#different-heights)
applies for messages from future rounds.

Messages from future rounds are _required_ for the proper operation of the
consensus state machine once the process reaches their round `r'`.
There are two options, which can in particular be combined:

1. Buffer a limited amount of such messages, or messages from a limited amount
   of future rounds `r'`
   - In CometBFT's implementation, only messages from round `r' = r + 1` are tracked.
2. Assume that the communication subsystem (p2p) is able to retrieve (ask for
   retransmission) of messages from future rounds when the process reaches round `r'`.
   Since messages from [previous rounds](#previous-rounds) are stored by
   default, peers that have reached the future round `r'` should be able to
   retransmit them.

## Current round

Messages matching the current round `(h, r)` of a process produce most of the
relevants events for the consensus state machine.

TODO:
