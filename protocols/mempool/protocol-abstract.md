# Transaction dissemination protocol [WIP]

This document describes at a high level the mempool protocol, responsible for
disseminating transactions in a CometBFT network.

## Network model

The mempool protocol operates in a partially-connected network constructed by
the peer-to-peer (p2p) communication layer running in every participant node.

The network is composed by a set $\Pi$ of nodes running the mempool protocol.
The set $\Pi$ is dynamic, as nodes may join or leave (possibly by crashing) the
network at any time.
Nodes are not expected to know the full extent of $\Pi$, which is only used
for model purposes.

The network is partially connected.
This means that no node is expected to be (directly) connected to every other
node in the network.
Instead, each node is connected to a set of $peers$, a subset of other nodes
with which it can interact directly by exchanging messages.
The set of peers of a node is dynamic, as the node can establish connections
with new peers and connections with existing peers can be dropped.

The communication among nodes takes places in the network _overlay_ defined by
the $peers$ relation.
More precisely, the network overlay is a dynamic undirected graph composed by
the set $\Pi$ of nodes and a set of edges $(p, q)$ connecting every $p \in \Pi$
to all its peers $q \in peers[p]$.
The network overlay is assumed to be connected, meaning that there is a path in
the network overlay graph between every pair of nodes in $\Pi$.
Since both $\Pi$ and the $peers$ relation are dynamic, some paths between nodes
may be disrupted, but it is assumed that they are eventually repaired or
replaced by the underlying p2p communication layer.

Finally, the links connecting a node to its peers are assumed to be reliable
within a connection.
This means that if a node sends a message to one of its peers, either the message is
delivered to the peer or the node disconnects from the peer.
In addition, links do not duplicate, corrupt, or reorder messages, which are
delivered in FIFO order.
Links, however, are asynchronous and may arbitrarily delay the delivery of
messages.


## Transaction flooding algorithm

The dissemination of transactions happens by flooding transactions in the
overlay network, as captured by the algorithm below.

```
var peers // other nodes to which we are directly connected
var seen  // set of transactions already seen, initially empty

upon brodcast(tx):
    if tx not in seen and valid(tx)
        seen = append(seen, tx)
        for all p in peers
            send(<TX, tx>) to p

upon receive <TX, tx> from p:
    if tx not in seen and valid(tx)
        seen = append(seen, tx)
        for all q in peers; q != p
            send(<TX, tx>) to q

upon commit(txs):
    for all tx in txs
        seen = append(seen, tx)
```

The algorithm represents the operation of a node in the network.
The `peers` variable stores the list of peers of the node, that is the nodes to which it is
directly connected to in the overlay network.
The `peers` list is dynamic, being updated by the underlying p2p communication
layer when new connections are established or existing connections are dropped.

Transactions are disseminated by flooding, as the node sends every transaction
it receives for the first time to all its `peers`.
A transaction can be received from an external component, via the `brodcast`
method, or from a peer, via the `receive` method.
In the case a transaction is received from a peer, the node does not send the
same transaction back to that peer.

To determine whether a transaction is received for the first time, the algorithm
maintains a set `seen` containing every transaction ever received.
This map prevents transactions from being indefinitely forwarded to the peers
and provides a simple mechanism to cease the propagation of transactions when
they are received by every node in the network.

The algorithm also uses the `seen` set to mark transactions that have been
committed to the blockchain, and therefore do not need to be further
propagated.

### Limitations

While useful to represent the operation of the transaction propagation
protocol, the above algorithm has some practical limitations:

1. New peers: the algorithm does not send transactions whose dissemination is
   ongoing to newly connected peers.
In other words, a node joining the network should only expected to receive
transactions whose dissemination has started after it has joined the network.
2. Ordering: the algorithm may not send transactions that are concurrently
   being disseminated in the same order to  peers.
In fact, in case of concurrent invocations of the upon broadcast or receive
clauses of the algorithm, peers are likely to receive the relayed transactions
in different orders.

The next algorithm refines the above algorithm by addressing those limitations.
address those limitations.
This first algorithm, however, is relevant because it is easier to analyze
and allows a simplified representation of the 
[propagation mechanism](./protocol-abstract.md#analysis-of-the-propagation).

> It is worth noting that the mempool does not (and cannot) provide any guarantee
> of transaction ordering when sending transactions to peers (either existing or new).
> However, users of the protocol expect the mempool protocol to address the above
> two limitations, which can be attested by the only document specifically
> addressing the mempool in CometBFT documentation:
> https://github.com/cometbft/cometbft/blob/main/docs/core/mempool.md


## Mempool flooding algorithm

The following algorithm is obtained by refining the previous algorithm as follows.

The first step is to replace the blocking **send** invocations by non-blocking
equivalents which _schedule_ the sending of a transaction to a peer.
The scheduled sending actions have to preserve order, in the sense that the sending
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
This set is initialized to the peer from which a transaction is received via
the newtork for the first time.

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
Note, however, that only adding the transaction to the `seen` set should be
enough for correctness, in particular because a second check to the `seen` set
could be performed before actually sending the transaction to a peer.


```
var peers   // other nodes to which we are directly connected
var seen    // set of transactions already seen, initially empty
var mempool // list of transactions
var senders // map of processes from which transactions were received

upon brodcast(tx):
    if tx not in seen and valid(tx)
        seen = append(seen, tx)
        mempool = append(mempool, tx)

upon receive <TX, tx> from p:
    if tx not in seen and valid(tx)
        seen = append(seen, tx)
        senders[tx] = p
        mempool = append(mempool, tx)
    else if seen[tx] // Optional improvement
        senders[tx] = append(senders[tx], q)

upon commit(txs):
    for all tx in txs
        seen = append(seen, tx)
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


## Representing the propagation of transactions

This section proposes a graph representation for the propagation of
transactions via the mempool protocol.
The reference is the simplified transaction flooding mechanism presented
[here](./protocol-abstract.md#transaction-flooding-algorithm).

The propagation of a transaction `tx` is represented by a directed tree graph.
The vertices of the propagation graph represent steps of the transaction
flooding algorithm taken by nodes when propagating transaction `tx`.
And links in the propagation graph represent the sending of a `TX` message
carrying the transaction `tx` between two nodes.

More formally, a vertex of the propagation graph is a tuple $(p, s, t)$ which
represents the step $s$ of the algorithm taken by node $p$ at a reference time $t$.
Two vertices of the graph are connected when there is a causal relation between
the steps of the algorithm represented by them.
More precisely, a link connects vertices $(s, p, t)$ to $(s', q, t')$ if the
execution of step $s$ of the algorithm by process $p$ at time $t$ leads to the
execution of step $s'$ at process $q$ at a time $t' > t$.

When considering the transaction flooding algorithm, the source of links in the
propagation graph are vertices $(s, p, t)$ representing either the upon
`broadcast` or `receive` clauses of the algorithm at a process $p$.
There are outbound links from such vertices if, as a result of performing step
$s$ at time $t$, process $p$ sends a `TX` message to a subset of its peers.
The destinations of links, in they turn, can only be vertices $(s', q, t')$
where $s'$ is the upon `receive` clause of the algorithm and $q$ is a process
that belongs to the set of peers of process $p$.

The inclusion of the reference time $t$ to label a vertex of the propagation
graph has two goals.
The first is to render vertices unique, since the same process $p$ can perform
the same step $s$ (e.g., the `receive` step) multiple times for the same
transaction `tx`.
The second reason is to enable the representation of the _first_  time at which
a step of the algorithm is performed at a given process for a transaction `tx`.
This is relevant because a process only take actions regarding a transaction
the first time it is received.

### Analysis

The figure below is an example of a graph representing the propagation of a
transaction in a network with five nodes.
The left side of the figure represents the network overlay.
Notice that the overlay is partially connected, with every node having two or
three peers.
The right side of the figure represents two possible propagation graphs for
that network.
For simplicity, the vertices are only labeled with the processes identifier;
the actions taken are described in the following, while it is considered a
graphical representation of the reference time, where a vertex depicted below
another vertex is associated with a greater reference time.
In other words, the reference time increases from top to bottom.

> TODO: check this illustration and transfer it to this repository: https://lucid.app/lucidchart/2a1f309d-6dd7-4466-853d-9efa964e5c1d/edit?viewport_loc=1%2C-11%2C3067%2C1476%2C0_0&invitationId=inv_c4bbad76-ccc4-4803-8040-fd15c5fd94eb

In both propagation graphs depicted, process `A` is the only process to process
a `broadcast` event for the considered transaction.
It is therefore the only root of the propagation trees.
All the other nodes of the propagation trees represent `receive` steps
performed by multiple processes.
What differs between the two trees is the order at which each `receive` step is
performed at different nodes.
Vertices representing the _first time_ that a node processes the transaction
are highlighted.
Notice that only the highlighted vertices have outbound links.
This happens because in other vertices from the same process, the transaction
is already on the `seen` set and therefore no action is taken.
The non-highlighted vertices also represent the redundancy of the transaction
propagation mechanism, namely the steps (and the messages triggering those
steps) that could be avoided because they are redundant.

In both cases, in a network with five nodes and six connections between nodes,
the propagation algorithm requires eight communication steps.
Notice that are two more communication steps than links in the overlay graph,
meaning that two pairs of nodes exchange the transaction among themselves in
both directions of the same link (`C` to `B` and `D` to `E` in the first
example, and `A` to `C` and `B` to `E` in the second example).
This two scenarios are highlighted by using a dashed line to connect the two
vertices for the latter (greater timestamped) vertices.
These are also communication steps that might be prevented by the algorithm, in
particular in the refined mempool flooding algorithm, by keeping track of the
multiple known senders of a transaction.
The other redundant steps essentially cannot be avoided, as they result from
concurrent and unrelated paths in the propagation graph.
