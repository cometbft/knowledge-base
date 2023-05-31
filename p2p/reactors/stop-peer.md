# Stop peer for error

This document derives from discussions on [CometBFT's PR #851][pr-851].

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

As mentioned in the documentation of the [p2p API for reactors][stop-peer],
the above method for disconnecting from a peer has a _caveat_:
if the peer is configured as a _persistent peer_, the switch will attempt
reconnecting to that same peer.

While this behavior may make sense when the method is invoked by multiplex
connections due to [communication errors](#use-by-multiplex-connections),
it does not make much sense when it is invoked by a reactor.


## Use by multiplex connections

A [multiplex connection][mconn-type] is configured with an error callback
`onError` which is invoked when any (irrecoverable) error is observed.

The switch configures the above method to be invoked by the error callback,
providing the original communication error as a `reason`.


## Role of the `reason` field

There was some discussion, starting from [CometBFT's PR #714][pr-714], with
respect to the generic `reason` field of the peer disconnecting methods.

This field is originally received by the above switch method from its caller,
then passed on to every registered reactor via the `RemovePeer()` method.
This way, ideally, reactors could respond in different ways to different
reasons for which a peer was stopped.
For example, a peer can be stopped due to a communication error, which is a
benign fault, or due to a misbehaviour observed at protocol (reactor) level,
which is a Byzantine behavior. 

The current implementation, however, does not support this form of distinction.
In fact, the `reason` is from `interface{}` type, which in Golang can literally
be anything.

It should be interesting to define a generic reason type or interface that
allows callers of the `StopPeerForError` method to provide details regarding
the reason for which a peer is being disconnected.

[pr-851]: https://github.com/cometbft/cometbft/pull/851
[pr-714]: https://github.com/cometbft/cometbft/pull/714
[switch-type]: https://github.com/cometbft/cometbft/blob/main/p2p/switch.go
[stop-peer]: https://github.com/cometbft/cometbft/blob/main/spec/p2p/reactor/p2p-api.md#stopping-peers
[reactor-remove]: https://github.com/cometbft/cometbft/blob/main/spec/p2p/reactor/reactor.md#stop-peer
[mconn-type]: https://github.com/cometbft/cometbft/blob/main/p2p/conn/connection.go
