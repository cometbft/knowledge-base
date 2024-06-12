# Consensus: algorithm _vs_ implementation

This document aims to collect the major differences and discuss the main
divergences between
the BFT consensus algorithm adopted by CometBFT
and its actual implementation as part of CometBFT's codebase.

**This is a work in progress.**

## Context

The reference for the BFT consensus algorithm is the paper
[The latest gossip on BFT consensus](https://arxiv.org/abs/1807.04938),
which describes the Tendermint consensus algorithm.

The reference for the implementation of the consensus protocol is the
[CometBFT repository](https://github.com/cometbft/cometbft/tree/main/consensus),
primarily the `consensus` package.
This includes the
[specification](https://github.com/cometbft/cometbft/blob/main/spec/consensus/consensus.md)
of the consensus implementation, although the content of this document needs to
be properly validated and updated.

This investigation should, as far as possible, be restricted to highlight
differences between the BFT consensus algorithm and the corresponding
implementation of the core consensus protocol.
Are _not_ considered as part of the core consensus protocol, and therefore are
not expected to be covered by this document:

- The consensus gossip protocol: not specified in the algorithm, a
  complex protocol in the implementation
- The Application-Blockchain interface (ABCI) and the interactions with the
  replicated application in general
- The proposer election algorithm, which is assumed to be an external module

## Summary

A non-comprehensive and evolving list of divergences between the algorithm and the implementation:

- [Block propagation](#block-propagation): the implemented `PROPOSAL` message
  does not carry the full proposed value.
  The proposed block is transmitted using a variable number of `BlockPart` messages.
- [Equivocating proposals](#equivocating-proposals): the algorithm considers
  that multiple valid `PROPOSAL` messages can be received in a round of consensus.
  The implementation only considers the _first_ valid `Proposal` received.
- [Round skipping](#round-skipping): the conditions for skipping to a higher
  round in the implementation are more restrictive than in the algorithm.
  The limited tracking of votes from future rounds is included in this discussion.
- [Commit phase](#commit-phase): the actions taken when a block is
  decided are more complex in the implementation, while the algorithm
  essentially sets the decision value and moves to the next height.
- [Last commit](#last-commit): the consensus protocol collects as much
  `PRECOMMIT` votes as possible for a decided block.
  This operation includes the `timeout_commit` logic and of the `NewHeight`
  round step.
- [Validators set](#validators-set): the algorithm assumes a fixed number of
  processes with uniform voting power. In the implementation, the set of voting
  processes (validators) and their voting power are dynamic.

Potential divergences and specificities to be considered:

- Locked value as proposed value (i.e., deciding without a `PROPOSAL` message)
- Empty blocks handling (except if it can be encapsulated on the `getValue()` logic)

## Block propagation

The algorithm considers three message types:

- A `PROPOSAL` message carries the proposed value `v`, a _full_ value
- `PREVOTE` and `PRECOMMIT` messages carry a reference `id(v)` to the
  voted (full) value `v`

In the implementation, a proposed value is a block to be appended to the
blockchain, more specifically:

- The proposed value `v` is always a `Block`
- The reference for a proposed value `id(v)` is a `BlockID`

The implementation considers a different set of message types:

- `Proposal` message: similar to the algorithm's `PROPOSAL` message, with the
  difference that it carries a `BlockID` (equivalent to `id(v)`), not the full
  proposed value (equivalent to `v`)
- `BlockPart` messages: carry the full proposed value (equivalent to `v`),
  split into multiple `Part`s of a `Block`. Together with the `Proposal`
  message, plays the role of the algorithm's `PROPOSAL` message.
- `Vote` messages: corresponds to the algorithm's `PREVOTE` and
  `PRECOMMIT` messages, carries a `BlockID`

In other words, the full proposed `Block` is not carried by the `Proposal`
message.
The `Proposal` message carries a `BlockID` while a variable number of
`BlockPart` messages are responsible for transporting the full proposed
`Block`, uniquely identified by the `BlockID` carried by the `Proposal`
message.

The `BlockID` type has two roles in the consensus implementation:

- It uniquely identifies a `Block`, by storing its hash (effectively `id(v)`)
- It carries the root of a Merkle tree used to propagate the `Block` using
  multiple `BlockPart` messages

The consensus implementation thus implements the `propose` step as follows:

1. A `Proposal` message is received and a Merkle tree is initialized from the proposed `BlockID`
1. A number of `BlockPart` messages are received, and the corresponding block
   `Part`s are added to the initialized Merkle Tree; the full proposed block is
   being progressively computed.
1. Once all `Part`s of a `Block` are received, and validated against the Merkle
   tree root, the `ProposalBlock` field is computed so that to store the
   proposed `Block`.

As a result, the combination of the `Proposal` and `ProposalBlock` block
implementation fields corresponds to receiving of a `PROPOSAL` message in the
algorithm, proposing a value `v == ProposalBlock`.

References:

- [tendermint/tendermint#7946](https://github.com/tendermint/tendermint/issues/7946)
  Treat proposal and block parts explicitly in the spec
- [tendermint/tendermint#9504](https://github.com/tendermint/tendermint/issues/9504)
  consensus: Proposal should not include block ID
- [tendermint/tendermint#7922](https://github.com/tendermint/tendermint/issues/7922)
  Proposal to Reform BlockID and Block Propagation

## Equivocating proposals

A correct node that is the proposer of a round is assumed to produce a value
`v` and broadcast a `PROPOSAL` carrying the proposed value `v`.
Byzantine proposers, however, may produce multiple proposed values and
broadcast distinct `PROPOSAL` messages in the same round.
This constitutes an _equivocation_.

A correct node should act upon the _first_ valid `PROPOSAL` message received in
a round.
The action taken is the broadcast of a `PREVOTE` message, either for the
proposed value `id(v)` or for `nil`.
From this point, if further `PROPOSAL` messages are received, a correct node
should not take any action, as might entail broadcasting a different `PREVOTE`
message in the same round, which would configure an equivocation.

However, a correct node that acted upon a `PROPOSAL` message proposing `v` can
still broadcast a `PRECOMMIT` message for, or decide a different value `v'`,
provided it receives a `PROPOSAL` message proposing `v'` and the required
number of `PREVOTE` (line 36) or `PRECOMMIT` (line 49) messages for `id(v')`.
In other words, while only the first valid `PROPOSAL` message received enables
the upon clauses of lines 22 and 28, any `PROPOSAL` message should be
considered when evaluating the conditions of lines 36 and 49.

In practical terms, this means that a process should store and consider any
valid `PROPOSAL` message received in a round, even though only the first one
enables the transition from the `propose` to the `prevote` steps.

In the consensus implementation, the `PROPOSAL` message considered by the
algorithm is a combination of a `Proposal` message with a number of
`BlockPart` messages, as discussed in [block propagation](#block-propagation).

In the implementation, a node only considers and stores a _single_ `Proposal`
message per round, the first valid one received, rejecting any additional
`Proposal` message it receives.
The `Proposal` message has the role of defining which `BlockPart` messages the
node should accept, therefore which `Block` it is expected to build.
This means that once accepting a `Proposal` message, the node will also reject
`BlockPart` messages that do not match that `Proposal`, therefore it will not
build possible other `Block`s proposed in the same round.

> There are exceptions for this role: under some conditions, to be discussed in
> the following, a node starts accepting `BlockPart` messages for a `Block` that
> does not matching the accepted `Proposal`.

## Round skipping

In short, $f + 1$ messages from a future round are enough in the algorithm,
while the implementation requires $2f + 1$  vote messages from a future round.
Moreover, in practice a node at round $r$ can only skip to round $r+1$, from
the method for keeping track of votes.

## Commit phase

TODO:

## Last commit

TODO:

## Validators set

TODO:
