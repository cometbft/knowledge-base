# Reactors: `Switch` and `Peer` APIs

This document derives from discussions on [CometBFT's PR #851][pr-851].

PR #851 documents the API that the p2p layer offers to the protocol layer,
namely to reactors.
This API is split into two interfaces: the methods provided the `Switch`
instance and the methods provided by multiple `Peer` instances, one per
connected peer.

This document discusses why the [p2p API for reactors][p2p-api] is provided
both by the `Switch` and a number of `Peer` instances.


## `Switch` instance

The main point of discussion in the case of the `Switch` is that several of its
most used methods include a `Peer` instance.

This is the case of the methods to disconnect from a peer (`StopPeerForError`
and `StopPeerGracefully`) and mark a peer as good (`MarkPeerAsGood`).
Those methods could instead be offered by the `Peer` interface.
The problem is that their implementation requires information and logic
belonging to the `Switch` instance and would therefore require some processing
by the `Switch`.

There are also `Switch` methods that use the list of connected peers:
`Peers()`, `NumPeers()`, and `Broadcast()`.
Those methods could be implemented by reactors themselves, as they are aware of
the list of connected peers.
This approach, however, has two disadvantages.

The first is the possible repetition of code in every reactor to retrieve the
information or to implement the broadcast action; there is also no indication
that the reactor's implementation would be easier to read or more efficient.
The second problem is the fact that the set of connected peers known by a
reactor and the actual set of connected peers maintained by the `Switch` are
not always the same.
While most of the time they should be identical, during the procedure to add or
remove a peer, the state at some reactors might differ from the state at the
`Switch`.
Reactors' implementation of such methods would therefore keep that possibility
in mind.


## `Peer` instances

The [`Peer`][peer-iface] interface has a standard implementation `peer`,
used by the p2p layer, which instances essentially encapsulate a multiplex
connection ([`MConnection`][mconn-type]) instance.
For instance, the sending `Send()` and `TrySend()` methods offered by the
`Peer` interface are wrappers for the same methods provided by the multiplex
connection.

The most likely reason for the sending methods being offered by `Peer`
instances, instead of by the `Switch`, is to enable sending operation to
distinct peers to be independent, implemented fully in parallel.
In fact, similar `Switch` methods would have to access the synchronized list of
connected peers to then invoke the sending methods of the corresponding
multiplex connections.

### Receive callback

A multiplex connection is configured with a receive callback `onReceive` which
is invoked each time a message is fully received.
As detailed in the reactors [documentation][reactors-doc], it is up to the
registered reactor to process incoming message using via their
`Receive(Envelope)` method.
The receive callback thus must be able to map the channel ID of each receive
message to the reactor registered to process messages from this channel.
This is conceptually a `Switch` role.

The receive callback for multiplex connections, however, is implemented in the
constructor of the `peer` type, which implements the `Peer` interface.
This constructor receives the map of channel IDs to reactor, so that the
callback is able to deliver the message to the right reactor.
There is no synchronization involved in this step as the mapping of channel IDs
to reactors is static: it is performed at the reactor's registration phase,
that is, before the `Switch` and all reactors are started.

While this solution works, it renders the code hard to follow, to adapt, and
also has some drawbacks.
In particular, any error on the receive callback produces a `panic()`
call, which is caught by a `recover()` call in the multiplex connection.

### Error callback

A multiplex connection is configured with an error callback `onError` which
is invoked when any (irrecoverable) error is observed.

The error callback for every multiplex connection is the same
`Switch.StopPeerForError()` method.
In other words, is the `Switch` that handles errors produced by the multiplex
connection encapsulated by any `Peer`.
This include errors produced by the receive callback, as above described.

### Message marshalling

In previous versions of the code, it was up to reactors to serialize messages
before invoking the `Peer` sending methods and to de-serialize messages
received via the `Receive()` method.
Errors were then processed by the reactors.

In more recent versions of the code, message marshalling has been transferred
to the `Peer` implementation.
The multiplex connection still operates on marshalled bytes.
Thus, before sending messages via the multiplex connection, the `peer` instance
serializes the message into bytes.
And before delivering a received message to the destination reactor, the
`onReceive` callback de-serializes the received bytes into a message.

A problem of this approach is, again, error handling.
The sending methods return a boolean; marshalling errors cause the methods to
return `false`, while the actual error is logged but not provided to the
calling reactor.
The receive callback, as previously mentioned, panics; the actual error is
recovered by the multiplex connection, which both logs and passes it on to the
error callback; the error callback, as above mentioned, is the
`Switch.StopPeerForError` method, which at the end provides the error to all
reactors via the `RemovePeer()` method.

Another problem of this new approach is to render the `Switch.Broadcast()`
method pretty inefficient.
In the original implementation, the message was serialized by the sending
reactor, and the broadcast consisted in multiple `Peer.Send()` calls passing a
serialized message (bytes).
In the current implementation, every `Peer.Send()` call receives a message,
serializes it to (the same) bytes, to then send them using the multiplex
connection.
Notice that the problem is not with the particular implementation of the
`Switch.Broadcast()` method: if the reactors implemented the same, the message
would be serialized multiple times in the same way.

[pr-851]: https://github.com/cometbft/cometbft/pull/851
[p2p-api]: https://github.com/cometbft/cometbft/blob/main/spec/p2p/reactor/p2p-api.md
[reactors-doc]: https://github.com/cometbft/cometbft/blob/main/spec/p2p/reactor/reactor.md

[peer-iface]: https://github.com/cometbft/cometbft/blob/main/p2p/peer.go
[mconn-type]: https://github.com/cometbft/cometbft/blob/main/p2p/conn/connection.go
