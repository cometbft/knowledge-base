# Peer's key-value store for state sharing

This document derives from discussions on [CometBFT's PR #851][pr-851].

The [`Peer`][peer-iface] interface offers to reactors a [key-value store][peer-get-set]
that can be used to exchange state between reactors.
As documented in the [API to Reactors][p2p-api], this key-value store is used by
the Consensus, Mempool, and Evidence reactors.

The Consensus reactor stores in the key-value store a `PeerState` instance that
is accessed and updated by the multiple routines interacting with each peer.
The Evidence and Mempool reactors, in their turn, periodically query the
key-value store of each peer for reading part of the information there stored
by the Consensus reactor.

In the following, we detail the use of this shared key-value store by the three
reactors.


## Consensus reactor

The consensus reactor maintains, for each connected peer, a `PeerState`
instance which stores a summary of the state of the peer in the consensus
protocol.

The `PeerState` object associated with a given `Peer` is create as part of the
`InitPeer(Peer)` method from the Reactor API.
A new `PeerState` instance is created, encapsulating the `Peer` handler,
it is stored in the `Peer`'s key-value store using the hard-coded
`types.PeerStateKey` key, and the updated `Peer` handler is returned to the switch:

    // InitPeer implements Reactor by creating a state for the peer.
    func (conR *Reactor) InitPeer(peer p2p.Peer) p2p.Peer {
            peerState := NewPeerState(peer).SetLogger(conR.Logger)
            peer.Set(types.PeerStateKey, peerState)
            return peer             
    } 

The `PeerState` type is part of the consensus reactor implementation.
It is worth noting that it does not only store a summary of the last known
state of the peer in the consensus protocol, but also acts as a helper for the
consensus reactor implementation.
For instance, the [`PeerState.PickSendVote`](https://github.com/cometbft/cometbft/blob/main/consensus/reactor.go#L1142)
public method _sends_ a message to the peer.

The `PeerState` instance created upon `InitPeer(Peer)` and stored in the `Peer`
key-value store is then retrieved from the store when `AddPeer(Peer)` is
invoked for the same peer.
This shared state object is then passed to the three routines the consensus
reactor maintains for every connected peer:

    peerState, ok := peer.Get(types.PeerStateKey).(*PeerState)
    // Panics if the state does not exist
    go conR.gossipDataRoutine(peer, peerState)
    go conR.gossipVotesRoutine(peer, peerState)
    go conR.queryMaj23Routine(peer, peerState)

These routines periodically compare the local state of the consensus protocol
with the state of the consensus protocol at the peers, summarized by the
associated `PeerState` instance, so that to select which consensus messages
should be sent to the peer.
The selected message is then sent to the peer and, if the send operation
succeeds, the `PeerState` instance is so that to reflect the assumption that
the peer has received the selected message, updating its state in the consensus
protocol accordingly.

In addition, `PeerState` instances are also employed by the `Receive(e Envelope)`
method of the consensus reactor.
In fact, for every received message, the summary of the state of the peer that
has sent the message (`e.Src`) is retrieved from the associated `Peer`'s
key-value store:

    ps, ok := e.Src.Get(types.PeerStateKey).(*PeerState)

Also in the case, the `PeerState` instance associated to the message's sender
is updated so that to reflect the fact that the peer has the message that it
has sent to the node.
The summary of the peer's state in the consensus protocol is then updated,
which may enable the sending of certain messages to the peer by the previously
mentioned three routines handling this specific peer.

In summary, the consensus reactor relies on the `PeerState` instances for
implementing the transport (gossiping) of consensus messages.
This state is in fact queried and updated by the main routines of the consensus
reactor, both when processing incoming messages, and when sending messages to
peers.

In fact, it is possible to say that the `PeerState` instances are not only used
to share state between the consensus reactor and other reactors, as detailed in
the following sections, but also to share state between the multiple routines
running within the consensus reactor.


## Mempool reactor

The mempool reactor queries the `Peer`'s key-value store as part of its
[`broadcastTxRoutine`](https://github.com/cometbft/cometbft/blob/main/mempool/reactor.go#L132).
Once a new `Peer` is added to the mempool reactor, an instance of this routine
is started for the new peer.
The routine is responsible for forwarding transactions stored in the local
mempool to the peer.


    peerState, ok := peer.Get(types.PeerStateKey).(PeerState)
    // Some checks, then
    if peerState.GetHeight() < memTx.Height()-1 {
        time.Sleep(PeerCatchupSleepIntervalMS * time.Millisecond)
        continue
    }

The rationale of the code is to prevent sending transactions to a peer that is
lagging behind in the consensus protocol.
So, if the peer's height in the consensus protocol differs by more than one
unit of the node's height in the consensus protocol, no transactions are sent
to the peer.
A reason for this behaviour is the fact that every transaction received by a
node in the mempool protocol is verified against the state of the application,
via the `CheckTx` ABCI call.
In case of stateful verification, a peer lagging behind might reject a
transaction that was accepted by the node, which is undesirable.

For the sake of the topic of this document, the information queried by the
mempool protocol is the peer's height learned by the consensus protocol.
No other data referring to the peer or stored in the shared `PeerState` object
is accessed.
    

## Evidence reactor

The evidence reactor queries the `Peer`'s key-value store as part of its
[`broadcastEvidenceRoutine`](https://github.com/cometbft/cometbft/blob/main/evidence/reactor.go#L107).
Once a new `Peer` is added to the evidence reactor, an instance of this routine
is started for the new peer.
The routine is responsible for forwarding evidences of misbehavior to the peer.

Before an evidence of misbehavior is sent to a peer, the evidence reactor
verifies whether it is relevant for that peer.
This verification is performed by the `prepareEvidenceMessage` method, which
includes the following code excerpt:

    peerState, ok := peer.Get(types.PeerStateKey).(PeerState)
    // Some checks, then
    peerHeight = peerState.GetHeight()
    ageNumBlocks = peerHeight - evHeight
    if peerHeight <= evHeight { // peer is behind. sleep while he catches up
        return nil
    } else if ageNumBlocks > params.MaxAgeNumBlocks { // evidence is too old relative to the peer, skip
        // Log that the evidence is not being sent to the peer
        return nil
    }

When this method returns `nil`, the locally stored evidence of misbehaviour is
not sent to the peer.
The rationale of the first check is to prevent sending an evidence of
misbehavior to a peer that is lagging behind in the consensus protocol.
Whenever a evidence of misbehavior is received by the evidence reactor, the
reactor checks whether the evidence if valid.
Verifying the validity of an evidence of misbehavior requires querying the
blockchain state.
Node at different blockchain height's will likely be at different heights at
the consensus protocol as well.
Thus, not sending an evidence of misbehavior to a peer that is at at different
height at the consensus protocol prevents the peer from rejecting the evidence
as invalid because it does not have the information to validate it.

The second check refers to the temporal validity of an evidence of misbehavior.
There are configuration parameters defining for how long an evidence is valid
and can be included in a proposed block.
The validity is defined both in terms of physical time (timestamps) and of
logical time (blockchain heights).
The evidence reactor thus doesn't send to a peer an evidence of misbehavior
from a height that the peer will reject because, at its height, it is already
deemed invalid.

For the sake of the topic of this document, the information queried by the
evidence protocol is the peer's height learned by the consensus protocol.
No other data referring to the peer or stored in the shared `PeerState` object
is accessed.


## Synchronization

The key-value store provided by a `Peer` instance should enable state sharing
among multiple readers and writes located in different reactors.
The access to the key-value store is synchronized, as its implementation relies
on a `CMap`, which is a generic synchronized map.

However, as can be observed from the previous sections, the use of this
key-value store does not really follow the semantics for a synchronized
key-value store.
In fact, the value stored under the `types.PeerStateKey` key is only written
once, by the consensus reactor upon `InitPeer(Peer)`.
At this point, a new `PeerState` instance is created and initialized, then
written to the store.

The created `PeerState` instance is then read and _updated_ by multiple
routines of the consensus reactor.
After updating the content of the `PeerState` instance, however, the new
content is not written (put) again to the key-value store.
The key-value store thus in fact only stores a reference (pointer) to a
`PeerState` instance.

In order to really synchronize the access to the `PeerState` instance, the
type includes a own
[lock](https://github.com/cometbft/cometbft/blob/main/consensus/reactor.go#L1025).
This lock is acquired by every public method of the `PeerState` type, thus
guarding the state stored by that instance.

For all effects, the existence of this second lock renders the first lock,
embebbed at the `Peer` instance, only relevant until the initialization (and
write operation) of a `PeerState` instance.
From this point, there is no reason for guarding the access to the _reference_
to a `PeerState` instance, as while the content of such instance is very often
updated, the reference itself is not.

Finally, it is worth noting that the `PeerState` stored in the key-value store
of a `Peer` is not explicitly deleted.
In fact, the API for this key-value store does not include a `Remove(key)`
method.
Moreover, the `RemovePeer(Peer)` method of the above mentioned reactors do not
access, update, or replace the associated `PeerState`.
Thus, once the `Peer` is removed (disconnected) and no more accesses are
performed to the associated `PeerState` instance, the garbage collector should
be responsible for clearing the memory used by it.

[pr-851]: https://github.com/cometbft/cometbft/pull/851
[p2p-api]: https://github.com/cometbft/cometbft/blob/main/spec/p2p/reactor/p2p-api.md

[peer-get-set]: https://github.com/cometbft/cometbft/blob/cason/758-reactors/spec/p2p/reactor/p2p-api.md#key-value-store
[peer-iface]: https://github.com/cometbft/cometbft/blob/main/p2p/peer.go
