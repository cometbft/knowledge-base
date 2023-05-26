# Stop peer for error

The [`Switch`][switch-type] offers to reactors methods to disconnect
or [stop a peer][stop-peer].
This document focus on the version in which the peer is disconnected or stopped
due to an error, which is typically provided to the method as the `reason`:

    func (sw *Switch) StopPeerForError(peer Peer, reason interface{})

When this method is invoked for the first time, the `Switch`:
(i) stops the `Peer` instance,
(ii) removes it from every registered reactor,
using the [`RemovePeer(Peer, reason)` method][reactor-remove],
(iii) and removes it from the set of connected peers.

## Stopping persistent peers


## Use by multiplex connections


## Role of the `reason` field

[switch-type]: https://github.com/cometbft/cometbft/blob/main/p2p/switch.go
[stop-peer]: https://github.com/cometbft/cometbft/blob/cason/758-reactors/spec/p2p/reactor/p2p-api.md#stopping-peers
[reactor-remove]: https://github.com/cometbft/cometbft/blob/cason/758-reactors/spec/p2p/reactor/reactor.md#stop-peer
