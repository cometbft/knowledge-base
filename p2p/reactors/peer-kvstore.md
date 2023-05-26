# Peer's key-value store for state sharing

The [`Peer`][peer-iface] interface offers to reactors a [key-value store][peer-get-set]
that can be used to exchange state between reactors.

As documented in the [API to Reactors][pr-851], this key-value store is used by
the Consensus, Mempool, and Evidence reactors.
The Consensus reactor stores in the key-value store a `PeerState` instance that
is accessed and updated by the multiple routines interacting with each peer.
The Evidence and Mempool reactors, in their turn, periodically query the
key-value store of each peer for reading part of the information there stored
by the Consensus reactor.

This document addresses the following comment from @Josef in [CometBFT's RP 851][pr-851]:

> As far as I understand, this then is used within mempool and evidence to do
> some consensus-specific checks.
> As a consequence, right now, if we would swap out consensus for a different
> consensus algorithm, we would need to change the code on the mempool and
> evidence.
> I think we can come up with a cleaner interface for this information flow,
> ideally having all consensus-specific logic within consensus. I think we should
> look into this more closely.

In the following, we detail the use of this shared key-value store by the three
reactors:

## Consensus reactor

## Mempool reactor

## Evidence reactor


[pr-851]: https://github.com/cometbft/cometbft/pull/851

[peer-get-set]: https://github.com/cometbft/cometbft/blob/cason/758-reactors/spec/p2p/reactor/p2p-api.md#key-value-store
[peer-iface]: https://github.com/cometbft/cometbft/blob/main/p2p/peer.go
