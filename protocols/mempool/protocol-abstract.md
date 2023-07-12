# Transaction dissemination protocol [WIP]

This document describes in high level the mempool protocol, responsible for
disseminating transactions in a CometBFT network.

## Network model

The network is composed by a set $\Pi$ of nodes.
The set is dynamic, as nodes may join or leave (possibly by crashing) the
network at any time.

*Partial knowledge.*
Nodes are not expected to known the fully extent of $\Pi$,
i.e. the identity and address of every node in the network.
Nodes are instead assumed to be part of a peer discovery protocol,
from which they learn the identity and address of a subset of nodes in $\Pi$.

*Partial connectivity.*
No node is expected to be directly connected to every other node in $\Pi$.
Instead, each node $p$ is assumed to be directly connected to a subset of other
nodes, also called its $peers$.
We denote by $peers[p] \subset \Pi$ the set of nodes directly connected to $p$
and require $p \notin peers[p]$.
Connections are bi-directional, i.e. if $q \in peers[p]$ then $p \in peers[q]$.
As happens to $\Pi$, the set of peers directly connected to each node is also dynamic.
A node may, at any time, establish connections with new peers,
or lose its connection with any of its current peers.

*Network overlay.*
The communication among nodes takes places in the network overlay defined by
the $peers$  relation.
More precisely, the network overlay is a dynamic undirected graph composed by
the set $\Pi$ of nodes and a set of edges $(p, q) \subset \Pi x \Pi$
connecting every $p \in \Pi$ to all its peers $q \in peers[p]$.
We assume the network overlay to be connected, meaning that there is path
between every pair of correct nodes in $\Pi$.
Since the network overlay is dynamic, some paths between correct nodes may be
disrupted, but we assume that they are eventually repaired or replaced by an
underlying peer-to-peer overlay management service.

*Links.*
We assume that links between correct nodes are reliable within a connection.
More precisely, if a node sends a message to a peer, either the message is
delivered to the peer or the node disconnects from the peer.
We assume that links do not duplicate, corrupt, or reorder messages, which are
delivered in FIFO order.  Links, however, are asynchronous and may arbitrarily
delay the delivery of messages.


## Transaction flooding algorithm

The dissemination of transactions happens by flooding transactions in the
overlay network, as represented in the algorithm below.

The algorithm relies on a `peers` variable that stores the list of peer to
which the node is directly connected to in the overlay network.
The `peers` list is dynamic, being updated by the underlying peer-to-peer
communication layer when new connections are established or existing
connections are dropped.

Transactions are disseminated by flooding, as the node sends every transaction
it knows about to every connected peer.
The only exception is the peer from which the node receives a transaction from
for the first time, to which it does not send the same transaction back.

The algorithm maintains a map `seen` that allows determining when a transaction
is seen for the first time.
It prevents transactions from being indefinitely forwarded to the peers and
provides a simple mechanism to cease the propagation of transactions when they
are received by every node in the network.

The algorithm also uses the `seen` map to mark transactions that have been
committed to the blockchain, and therefore do not need to be further
propagated.

```
var peers // other nodes to which we are directly connected
var seen  // map of transactions already seen

upon brodcast(tx):
    if not seen[tx] and valid(tx)
        seen[tx] = true
        for all p in peers
            send(<TX, tx>) to p

upon receive <TX, tx> from p:
    if not seen[tx] and valid(tx)
        seen[tx] = true
        for all q in peers; q != p
            send(<TX, tx>) to q

upon commit(txs):
    for all tx in txs
        seen[tx] = true
```

While representing in high level the operation of the transaction propagation
protocol, algorithm above has some practical limitations.
Interestingly, although not stated as requirements for transaction propagation,
they ended up defined some additional (weak) properties that the mempool
protocol is expected to address:

1. New peers: the algorithm does not send transactions whose dissemination is
   ongoing to newly connected peers.
In other words, a node joining the network should only expected to receive
transactions whose dissemination has started after it has joined the network.
2. Ordering: the algorithm may not send transactions that are concurrently
   being disseminated in the same order to  peers.
In fact, in case of concurrent invocations of the upon broadcast or receive
clauses of the algorithm, peers are likely to receive the relayed transactions
in different orders.

It is worth noting that the mempool does not (and cannot) provide any guarantee
of transaction ordering when sending transactions to peers (either existing or new).
However, users of the protocol expect the mempool protocol to address the above
two limitations, which can be attested by the only document specifically
addressing the mempool in CometBFT documentation:
https://github.com/cometbft/cometbft/blob/main/docs/core/mempool.md

The next algorithm is refinement of the above presented algorithm so that to
address those limitations.
This first algorithm, however, is relevant because it is easier to analyze
and allows a simplified representation of the 
[propagation mechanism](./protocol-abstract.md#analysis-of-the-propagation).

## Mempool flooding algorithm

The following algorithm is obtained by refining the previous algorithm as follows.

The first step is to replace the blocking **send** invocations by non-blocking
equivalents which _schedule_ the sending of a transaction to a peer.
The scheduled send calls have to preserve order, in the sense that the sending
of two transactions to the same peer must be performed in the same order at
which they were scheduled.

This first step enables making the sending blocks, in the _for all_ excerpts of
the code, atomic, thus preserving the order which which transactions are relayed.
While making these blocks atomic in the original algorithm would have the same
effect, it would have impact on performance, as the sending calls are blocking.
Moreover, the handling of the situation in which a peer is removed from
`peers`, causing the send call to fail or last for a long period would be more
complex.

The practical effect of scheduling the send of transactions to peers, while
preserving a per-peer ordering, is to produce multiple _queues_, one per peer,
of transactions to be sent to that peer.
The second refining steps comes from the observation that those multiple queues
would be mostly _identical_, containing the same transactions, with the only
exception that the queue associated to the peer from which a transaction was
received for the first time will not include that transaction.
The multiple queues can then be replaced by a single queue, contain all the
transactions the node has to relay to peers.

The algorithm below thus include a `mempool` variable, a list of transactions
that have to be relayed to peers.
And, for each peer, a `send_routine` is created in order to iterate through the
`mempool` and send all stored transactions to that peer.
To handle exceptions of the algorithm, this refined version also includes a
`senders` map that stores, for every transaction, the set of peers, if any, to
which that transaction should not be sent.
This set is initialized to the peer from which a transaction is received for
the first time, if it was a peer and not an external component.

By keeping all the transactions that should be sent to peers in a list, the
refined algorithm also addresses the addition of new peers to the `peers` set.
In fact, all transactions in the `mempool` list are sent to that peer, until
eventually it catches up with the already connected peers.
From this point, the refined and the original algorithm essentially operates in
the same way. 

Another advantage of keeping all transactions to relay in a single list is the
possibility of removing from the `mempool` transactions that have been committed.
While this operation is not really simple to implement in practice, it prevents
sending committed transactions whose send was originally scheduled, either to
existing and new peers.
Note, however, that only adding the transaction to the `seen` map should be
enough for correctness, in particular because a second check to the `seen` map
could be performed before actually sending the transaction to a peer.


```
var peers   // other nodes to which we are directly connected
var seen    // map of transactions already seen
var mempool // list of transactions
var senders // map of processes from which transactions were received

upon brodcast(tx):
    if not seen[tx] and valid(tx)
        seen[tx] = true
        mempool = append(mempool, tx)

upon receive <TX, tx> from p:
    if not seen[tx] and valid(tx)
        seen[tx] = true
        senders[tx] = p
        mempool = append(mempool, tx)
    else if seen[tx] // Optional improvement
        senders[tx] = append(senders[tx], q)

upon commit(txs):
    for all tx in txs
        seen[tx] = true
        mempool = remove(mempool, tx) // Optional improvement

func send_routine(p):
    while p in peers
        tx = mempool.next() // blocks while there is no next
        if p not in senders[tx]
            send(<TX, tx>) to p

upon add_peer(p):
    spawn send_routine(p)

```

A last possibility added by this refinement is the use of the `senders` map to
store not only the peer from which the node receives the transaction at first,
but also the peers from which it receives copies of that transaction.
If the duplicated transaction is received from a peer _before_ the sending of
that transaction to it takes place, the node can avoid sending a transaction
that the peer for sure has already received.

This optimization is considered in the implementation of the mempool protocol,
but it remains to be defined what actual benefits it provides in terms of
saving send calls.
For defining this it is relevant to analyse how the propagation of a
transaction works in different situations, which is the topic of the next section.


## Analysis of the propagation


Illustration of propagation: https://lucid.app/lucidchart/2a1f309d-6dd7-4466-853d-9efa964e5c1d/edit?viewport_loc=1%2C-11%2C3067%2C1476%2C0_0&invitationId=inv_c4bbad76-ccc4-4803-8040-fd15c5fd94eb

