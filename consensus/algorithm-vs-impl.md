# Consensus: algorithm _vs_ implementation

This document aims to collect the major differences and discuss the main
divergences between
the BFT consensus algorithm adopted by CometBFT
and its actual implementation as part of CometBFT's codebase.

The reference for the BFT consensus algorithm is the paper
[The latest gossip on BFT consensus](https://arxiv.org/abs/1807.04938),
which describes the Tendermint consensus algorithm. 

The reference for the implementation of the consensus algorithm is the
[CometBFT repository](https://github.com/cometbft/cometbft/tree/main/consensus),
primarily the `consensus` package.

**This is a work in progress.**

## Summary

A non-comprehensive and evolving list of divergences between the algorithm and the implementation:

- [Gossip protocol](#gossip-protocol): not specified in the algorithm, a
  complex protocol in the implementation
- [Block propagation](#block-propagation): the implemented `PROPOSAL` message
  does not carry the full proposed value.
  The proposed block is transmitted using a variable number of `BlockPart` messages.
- [Round steps](#round-steps): the implementation considers more than the three
  round steps (`propose, prevote, precommit`) considered in the algorithm.
- [Timeout commit](#timeout-commit): the implementation includes an additional
  timeout, associated with the transition from a height to the subsequent,
  intended to collect as many votes for the committed block as possible.
- [Round skipping](#round-skipping): the conditions for skipping to a higher
  round in the implementation are more restrictive than in the algorithm.
  In short, $f + 1$ messages from a future round are enough in the algorithm,
  while the implementation requires $2f + 1$  vote messages from a future round.
  Moreover, in practice a node at round $r$ can only skip to round $r+1$, from
  the method for keeping track of votes.
- [Empty blocks](#empty-blocks): nodes may wait for new transactions before
  proposing a new block, so that it is not empty.
 
Potential divergences and specificities to be considered: 

- Locked value as proposed value
- Validity check and ABCI++
