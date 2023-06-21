# Communication of CometBFT Reactors 

We survey the communication protocols within the reactors. These should inform the requirements of the p2p layer

## Consensus reactor

The consensus protocol is based on the "gossip" property: every message delivered by a correct process (after stabilization time) is received by every correct process within bounded time. In practice, this requirement is sufficient but not necessary. 


#### [CM-REQ-CONS-GOSSIP.0]
If there is a messages *m* emitted by a correct process, such that

- *m* has not been received by correct process *p*
- correct process *p* is in a state where *m* would help *p* "to make progress"

then eventually it MUST BE that
- *p* receives *m*, OR
- *p* transitions into a state where *m* is not needed anymore to make progress.



#### [CM-PROTOCOL-CR-COMM.0]
Gossiping is done by surveying the peers' states within the consensus protocol. The information of peer *p* tells us what consensus messages *p* is waiting for. We then send these messages to *p*.

> In the current information this information is coarse. Peer *p* informs us about consensus height and round, and we send all votes for that height and round to *p*.

TODO: proposal. block parts.

The question is under which conditions [[CM-REQ-CR-COMM.0]] is sufficient to implement [[CM-REQ-CONS-GOSSIP.0]]. These conditions translate into requirements for the p2p layer

### Requirements on the p2p layer

There are **local requirements** that express needs as connections to neighbors

#### [CM-REQ-CR+P2P-STABLE.0]
In order to make sure that we can help a peer to make progress, the p2p layer MUST ensure that we need to stay connected to that peer sufficiently long to get a good view of its state, and to act on it by sending messages.

#### [CM-REQ-CR+P2P-ENCRYPTED.0]
In order  to make sure that we can help a peer to make progress, we need to be sure that we can trust the messages from a correct peer (IOW no masquerading). This is done by end-to-end encrypted channels. 


> The previous properties can be used to solve a local version of [[CM-REQ-CONS-GOSSIP.0]], that is, between neighbors. However, [[CM-REQ-CONS-GOSSIP.0]] is global, that is, whoever emits *m*, potentially we require that *m* is received by all correct processes in a potentially dynamic distributed system:
> - nodes may join an leave physically (connection)
> - validators join and leave logically (the validator set)

> This translates into **global requirements** for the p2p layer.

#### [CM-REQ-CR+P2P-CONNECT.0]
A good underlying network ensures:
- all-to-all communication: For every validator and every full node: there exists a path consisting of correct full nodes that connects the validator to the full node.

> The above implies that proposers are not disconnected. 

#### [CM-REQ-CR+P2P-STABILITY.0]
We say a period is good if
1. message delays are bounded
1. the period is sufficiently long (TODO: might need to clarify; sufficiently long to achieve consensus depending on the message delays)
1. the network is good; cf. [CM-REQ-CR+P2P-CONNECT.0]  

For each consensus instance (each block) we need the occurence of one good period. 
> As p2p does not know about consensus instances

In other words, at each point in time, eventually there will be a good period. (infinitely many good periods)

> The previous requirement is not minimal for solving consensus (in terms of connectivity requirement during good periods), but it seems implemented by the current p2p system

> The requirement of eventually reaching a good period and the requirement for all-to-all communication implies that
#### [CM-REQ-CR+P2P-ROBUSTNESS.0] 
The p2p system ensures
  1. that system can autonomously recover from failure (self-healing)
  1. resistance to eclypse attack: at any time, the network must ensure sufficient path redundancy between any two full nodes. 

#### [CM-REQ-CR+P2P-OPENNESS.0]
The p2p system ensures that at any time, new nodes can join the network. (In other words, at all times, there must be nodes that accept new connections)

> This doesn't mean that all nodes must accept new onnections. It also doesn't mean that a node must accept new connections at all times. 
> The above property derives from the requirement that new validators can join consensus. In order to do so, they must first be connected.

> TODO: what do we need to say about new nodes joining and existing nodes resyncing. -> requirement to establish new connections needa to be captured.

Since the systems we are building are decentralized and distributed, the global requirements can only be ensured by local actions of the distributed nodes. For instance, openness has been ensured by distinguishing inbound and outbound connections, and making sure that there are always nodes with open inbound connections.

> The consensus properties and the consensus algorithm are clearly specified in the arXiv paper. In the this section we could thus start our discussions from the consensus gossip property that provides a clear abstraction. As this level of detail of specification is missing for the other reactors, we need to survey them a bit in the following in more detail

## Mempool

Considering the whole CometBFT system, intuitively, there should be end-to-end 
requirements regarding transaction processing, e.g., "every transaction submitted
should be eventually put into a block" or "every transaction should be put in
at most one block". Note that these are just simple examples that are neither ensured
by current implementation nor are actually required by the system (e.g., typically we 
do not care about "all" transaction but rather "all valid"). 
Which of such requirements are actually ensured by the 
system depends on the guarantees by the concerned parts of the system.

The mempool is a distributed pool of "pending" transactions.
A pending transaction is a "valid" transaction that has been submitted by a
client of the blockchain but has not yet been committed to the blockchain.
The mempool is thus fed with client transactions,
that a priori can be submitted to any node in the network.
And it is consumed by the consensus protocol, more specifically by validator nodes,
which retrieve from the mempool transactions to be included in proposed blocks.

> Note that in this document, we want to capture (an overapproximation of) the requirements the mempool puts on p2p. The notions of "pending" and "valid" seem mostly to be conditions that the mempool can use to drop transactions (and exempt them from beeing spread over the network). Thus for the purpose of this document we will largely ignore them (they should eventually be addressed [here](https://github.com/cometbft/cometbft/issues/223)). 

As 
- full nodes add transactions to the mempool following client requests, and
- validators read transactions from the mempool to compose proposed blocks,

the mentioned end-to-end requirements on transactions translate into requirements 
on the mempool, e.g., every transaction that is submitted to a full node should 
eventually be present at the mempool of a validator/proposer. 

For the purpose of this document (specifying what the mempool needs from p2p), 
we do not strive to precisely state the end-to-end requirements. Rather, we 
will show that the arguably strongest requirement on the mempool do translate roughly
into requirements on the p2p layer that are similar to those of the
consensus reactor.

- end-to-end requirement: "every transaction submitted should be eventually put into a block"
> leads to
- requirement for consensus: for every submitted transaction from some height on, 
the transaction is proposed by every correct proposer in every height until it is committed
into a block (assuming infinitely often correct proposers get their proposal through)  
> leads to
- current solution to address this requirement: 
    - the mempool of correct full nodes is organized as a list. 
    This list can be understood as a shared data structure with relaxed semantics, that is,
    not all nodes need to agree on the order of the elements, but we have a property that 
    approximately says "if at time *t* a transaction tx1 is in the list of **all** nodes, and a 
    client submits transaction tx2 after time t, then it is never the case the tx2 is before
    tx1 in a list of a correct validator.

    > We talk about "correct full nodes" here as it describes "the current solution", the
    way this solution contributed to solving the problem is that if we have a property on
    every correct full node, this implies that we have this property on every (potential) 
    validator, and consequently, every correct proposer.

    - to prepare a proposal,  a validator requests from the mempool a list of
pending transactions that respects certain limits, in terms of the number of
transactions returned, their total size in bytes, and their required gas.
The mempool then returns the longest **prefix** of its local list of pending
transactions that respects the limits established by the consensus protocol. 

  > As a result of these two properties, once a transaction is known to all validators (present and future), it 
cannot be overtaken by infinitely many transaction that arrived in the system later (there
is still some possible overtaking due to faulty proposers); cf. no starvation.


We arrive at the requirement on the mempool: 

#### [CM-REQ-MEMP-GOSSIP.0]

1. every transaction submitted to a correct full node must eventually be included in the mempool of a correct validator
2. if a transaction is included in the mempool of a correct validator eventually it is included in the mempool of all correct validators 

> Point 1. appears slightly stronger than the requirement of the consensus reactor, as here all full nodes are sources of transaction, while in consensus only validators are source of consensus messages.

> This seems quite important, as it might be harder to guarantee. Validators
> - have more stable neighborhoods (behind sentry nodes), and 
> - are substantially fewer
>
> In the resulting network, reliable communication for consensus messages seems easier to achieve than reliable communication for transactions.

> Point 2. has potential to be weakened in practice, as it might be sufficient for a transaction to reach **one** correct validator as in practice CometBFT decides in one round. 


#### [CM-PROTOCOL-MR-COMM.0]

Gossiping is done by remembering for each peer which was the last element in the local list of transaction that was sent to a peer (there are condition where the pointer to the last element is reset). We then send transactions after this last element to the peer. 

> TODO: seems best effort send, i.e., no ACKs, no reliable communication (e.g., full messages queues). We should clarify.

### Requirements on the p2p layer

Similar to the consensus reactor, the discussion above entails  **local requirements** that express needs as connections to neighbors.

#### [CM-REQ-CR+P2P-STABLE.0]
In order to make progress in sending the list of transactions to a peer, the p2p layer must ensure that we stay connected to a peer sufficiently long.

Similar to the consensus reactor, [CM-REQ-MEMP-GOSSIP.0] translates into global connectivity requirements. However, [CM-REQ-CR+P2P-STABILITY.0] postulates a stable connected overlay for a continuous interval of time (to ensure time-bounded communication in good periods). A priori, for the transactions, we just require that over time all transactions reach the validators (reliable communication; not-necessarily time bounded), which does not imply connectivity within such an interval.

> However, expectations from the users might be different. With MEV etc., we will have time expectations regarding transactions processing. This will impose stronger constraints again.

## Evidence reactor

All that we found for the mempool also applies for the evidence reactor. 
Evidence are specific transactions that are used by the application (e.g., the staking module) to punish misbehavior. Typical applications (CosmosSDK chains) thus would benefit from timeliness: due to proof-of-stake and unbonding periods, a specific evidence transaction has an expiration date after which the application cannot act upon it.

There are several crucial things that are outside of the control of the evidence reactor
1. (application level) unbonding period
1. BFT time (written into the blocks) is under control of consensus
1. when evidence is put into a block (similar to the mempool we may assume that correct proposers always put all the evidence they are aware of in a block, but CometBFT cannot enforce that)
1. when evidence is submitted

In face of this uncertainty, there are only few reasonable requirement we can postulate

#### [CM-PROTOCOL-ER-COMM.0]
1. An evidence transaction reaches all validator nodes as "fast as possible".
1. Evidence is not written into a block after it has expired

> With more control over the four points, in principle we might define a real-time property which formalizes "if evidence is submitted at least a day before it expires, then evidence is written into a block before it expires". 

> To ensure Point 2., the unbonding period (and number of blocks) are given to CometBFT as consensus parameters (in genesis; they can be changed by the application via consensus).

<!---
https://github.com/cometbft/cometbft/blob/af3bc47df982e271d4d340a3c5e0d773e440466d/evidence/pool.go#L265

https://github.com/cometbft/cometbft/blob/af3bc47df982e271d4d340a3c5e0d773e440466d/evidence/reactor.go#L193
--> 


## Syncing reactors

Blocksync and Statesync are mainly request/response protocols. The peers act as servers and the node under consideration sends requests to the peers.

### Blocksync

- queries peers for their min-height and max-height
- requests blocks from peers of a given height

### Statesync

- uses RPC to download lightblocks from full nodes. Note that **communication is not via p2p!**
- uses p2p to download the data to reconstruct application state (passes data over ABCI to the application)

### Requirements on P2P
#### [CM-PROTOCOL-ER-COMM.0]
- In princple both syncing reactors need one stable and timely connection to at least one correct full node.

> We could define something like blocksyncing to the neighborhood, and then depending on how well the neighborhood is synced, blocksync will sync to the top of the chain. The the sync reactors just need one good connection. 

In practice, the correct full nodes we need the connection to
1. needs be synchronized with the blockchain
2. needs to have sufficient historical data (old blocks, old headers), to be able to respond to requests
3. As a result, the peer our node talks to needs to be "well-connected". 




## PEX

Right now, PEX (peer exchange) is implemented as yet another reactor on top of P2P. It is our understanding that from a functional viewpoint, the PEX reactor should be considered part of the p2p system. 

## Prioritization of messages

> TODO: are there priorities between / within the reactors?