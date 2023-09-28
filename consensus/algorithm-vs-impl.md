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
 
Potential divergences and specificities to be considered: 

- Locked value as proposed value (i.e., deciding without a `PROPOSAL` message)
- Empty blocks handling (except if it can be encapused on the `getValue()` logic)

## Block propagation

TODO:

## Equivocating proposals

TODO:

## Round skpping

In short, $f + 1$ messages from a future round are enough in the algorithm,
while the implementation requires $2f + 1$  vote messages from a future round.
Moreover, in practice a node at round $r$ can only skip to round $r+1$, from
the method for keeping track of votes.

## Commit phase

TODO:

## Last commit

TODO:
