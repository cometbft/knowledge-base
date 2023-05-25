# Reactors: `Switch` and `Peer` API

This document derives from discussions on CometBFT's [PR 851][pr-851].
The PR documents the API that the p2p layer offers to the protocol layer,
namely to reactors.
This API is split into two interfaces: the methods provided the `Switch`
instance and the methods provided by multiple `Peer` instances, one per
connected peer.

This document discusses why the p2p API for reactors is provided both by the
`Switch` and a number of `Peer` instances.

[pr-851]: https://github.com/cometbft/cometbft/pull/851
