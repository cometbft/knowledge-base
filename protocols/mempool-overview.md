** This (unfinished) document was used to collect a common understanding of the mempool. We will need to see how/whether this should be incorporated in the specification at some moment **

# Mempool

The mempool is a distributed pool of pending transactions.
A pending transaction is a valid transaction that has been submitted by a
client of the blockchain but has not yet been committed to the blockchain.
The mempool is thus fed with client transactions,
that a priori can be submitted to any node in the network.
And it is consumed by the consensus protocol, more specifically by validator nodes,
which retrieve from the mempool transactions to be included in proposed blocks.

More concretely, every node participating in the mempool protocol maintains a
local copy of the mempool, namely a list of pending transactions.
Nodes that expose an interface to receive transactions from clients
append the submitted transactions to their local copy of the mempool.
These nodes are the entry point of the mempool protocol,
and by extension of the consensus protocol.
Nodes that play the role of validators in the consensus protocol,
in their turn, retrieve from their local copy of the mempool
pending transactions to be included in proposed blocks.
Validator nodes are therefore the recipients of the transactions stored and
transported by the mempool protocol.

The goal of the mempool protocol is then to convey transactions
from the nodes that act as entry points of the network
to the nodes whose role is to order transactions.

## Interactions

### RPC server

Clients submit transactions through the RPC endpoints offered by certain
(public) nodes, which add the submitted transactions to the mempool.

### ABCI application

The mempool should only store and convey valid transactions.
It is up to the ABCI application to define whether a transaction is valid.

Transactions received by a node are sent to the application to be validated,
through the CheckTx method from the mempool ABCI connection.
This applies for both transactions received from a client and transactions
received from a peer in the mempool protocol.
Transactions that are validated by the application are appended to the local
copy of the mempool.
Transactions considered invalid by the application are drooped, therefore are
not added to the local copy of the mempool.

The validity of a transaction may depend on the state of the application.
In particular, some transactions that were valid considering a given state of
the application can become invalid when the state of the application is updated.
The state of the application is updated when a committed block of transactions
is delivered to the application for being executed.
Thus, whenever a new block is committed, the list of pending transactions
stored in the mempool is updated to exclude the executed transactions and
 sent to the application to be validated against the
new state of the application.
Transactions that have become invalid with the new state of application are
then removed from the mempool.

### Consensus: validators

The consensus protocol consumes pending transactions stored in the mempool to
build blocks to be proposed.
More precisely, the consensus protocol requests to the mempool a list of
pending transactions that respects certain limits, in terms of the number of
transactions returned, their total size in bytes, and their required gas.
The mempool then returns the longest prefix of its local list of pending
transactions that respects the limits established by the consensus protocol.
This means that the order with which the transactions are stored in the mempool
is preserved when transactions are provided to the consensus protocol.

> Notice that the transactions provided to the consensus protocol are not
> removed from the mempool, as they are still pending transactions albeit being
> included in a proposed block.

As proposing blocks is a prerogative of nodes acting as validators,
only validator nodes interact with the mempool in this way.

### Consensus: all nodes

The consensus protocol is responsible for committing blocks of transactions to 
the blockchain.
Once a block is committed to the blockchain, all transactions included in the
block should be removed from the mempool, as they are no any longer pending.
The consensus protocol thus, as part of the procedure to commit a block,
informs the mempool the list of transactions included in the committed block.
The mempool then removes from its local list of pending transactions the
transactions that were included in the committed block, and therefore are no
longer pending.
This procedure precedes the re-validation of transactions against the new state
of the application, which is part of this same procedure to commit a block.

> **Note**    
> Notice that a node can commit blocks to the blockchain through different
> procedures, such as via the block sync protocol.
> The above operation should be part of these other procedures, and should be
> performed whenever a node commits a new block to the blockchain.

## Formalization

In what follows, we formalize the notion of mempool.
To this end, we first provide a (brief) definition of what is a ledger, that is a replicated log of transactions.
At a process $p$, we shall write $p.var$ the local variable $var$ at $p$.

**Ledger.**
We use the standard definition of (BFT) SMR, where each process $p$ has a ledger, written $p.ledger$.
At process $p$, the $i$-th entry of the ledger is denoted $p.ledger[i]$.
This entry contains either a null value ($\bot$), or a set of transactions, aka., a block.
The height of the ledger at $p$ is the index of the first null entry.
Operation $submit(txs, i)$ attempts to write the set of transactions $txs$ to the $i$-th entry of the ledger.
As standard, the ledger ensures that there is no gap between two entries at each process,
that is  $\forall i. \forall p. p.ledger[i] \neq \bot \implies (i=0 \vee p.ledger[i-1] \neq \bot)$.
It also makes sure that no two correct processes have different ledger entries (agreement);
formally: $\forall i. \forall p,q \in Correct. (p.ledger[i] = \bot) \vee (q.ledger[i] = \bot) \vee (p.ledger[i] = q.ledger[i])$.
Finally, the ledger requires that if some transaction appears at an index $i$, then a process submitted it at that index (validity).
All the transactions in the non-null entries of the ledger are denoted $p.committed$;
formally $p.committed = \\{ tx : \exists j. tx \in p.ledger[j] \\}$.
The (history) variable $p.submitted$ holds all the transactions submitted so far by $p$.

**Mempool.**
A mempool is a replicated set of transactions.
At a process $p$, we write it $p.mempool$.
We also define $p.hmempool$, the (history) variable that tracks all the transactions ever added to the mempool by process $p$.

Below, we list the invariants of the mempool (at a correct process).

The mempool is used as an input for the ledger:  
**INV1.** $\forall tx. \forall p \in Correct. \square(tx \in p.submitted \implies tx \in p.hmempool)$

Committed transactions are not in the mempool:  
**INV2.** $\forall tx. \forall p \in Correct. \square(tx \in p.committed \implies tx \notin p.mempool)$

In blockchain, a tx is (or not) valid in a given state.
That is a transaction can be valid (or not) at a given height of the ledger.
To model this, consider that $p.ledger.valid(tx)$ is such a check for the current height of the ledger at process $p$ (ABCI call).
Our third invariant is that only valid transactions are present in the mempool:  
**INV3.** $\forall tx, \forall p \in Correct. \square(tx \in p.mempool \implies p.ledger.valid(tx))$

Finally, we require some progress from the mempool.
Namely, if a transaction appears at a correct process then eventually it is committed or forever invalid.  
**INV4** $\forall tx. \forall p \in Correct. \square(tx \in p.mempool \implies \lozenge\square(tx \in p.committed \vee \neg p.ledger.valid(tx)))$

**Practical considerations.**
In practice, as it requires to traverse the whole ledger, INV2 is too expensive.
Instead, we would like to maintain this only over the last $\alpha$ committed transactions, for some parameter $\alpha$.
Given a process $p$, we write $p.lcommitted$ the last $\alpha$ committed transactions at $p$.
Invariant INV2 is replaced with:  
**INV2a.** $\forall tx. \forall p \in Correct. \square(tx \in p.lcommitted \implies tx \notin p.mempool)$

Another practical concern is with INV3.
This invariant requires to have a green light from the client application before adding a transaction to the mempool.
For efficiency, such a validation needs to be made at most $\beta$ times per transaction at each height, for some parameter $\beta$.
Ideally, $\beta$ equals $1$.
In practice, $\beta = f(T)$ for some function f of the maximal number of transactions T submitted between two heights.
Given some transaction $tx$, variable $p.valid[tx]$ tracks the number of times the application was asked at the current height.
Invariant INV3 is replaced with:  
**INV3a.** $\forall tx. \forall p \in Correct. \square(tx \in p.mempool \implies p.valid[tx] \in [1, \beta])$

## Implementation in CometBFT (as of v0.38.0-alpha.2)

The mempool is implemented in clist_mempool.go, in the `CListMempool` data type.
`CListMempool` uses a single variable for the two mechanisms covered in the previous section.
Below, we present this approach in detail then establish its correctness.

**Algorithm**
For starters, we explain at a high-level the logic in `CListMempool`.
Variables `txs` and `cache` respectively hold the mempool and the validity cache in a FIFO and LRU list.
We omit the use of `txsMap`, assuming that a transaction is in `txs` iff it is also in `txsMap` (see [this](https://github.com/cometbft/cometbft/pull/890) fix).
For simplicity, we consider that 
_(i)_ the mempool is never full, 
_(ii)_ invalid transactions are _not_ kept in the cache, that is the parameter `KeepInvalidTxsInCache` is always set to false, and
_(iii)_ the `flush` operation is never called.
In addition, we shall assume that a finite amount of transactions is received by the system, and that if a transaction is received at a correct process, then it is eventually received at all the correct processes (thanks to the gossip layer in `mempool/reactor.go`).

Then, let us consider some transaction $tx$.
According to the logic in `clist_mempool.go`,

$tx$ is added to the cache at time $t$ (in short, @t) if  
(1) $tx$ is received and not already there @t (`checkTx`, [l237](https://github.com/cometbft/cometbft/blob/1f524d12996204f8fd9d41aa5aca215f80f06f5e/mempool/clist_mempool.go#L237)), or  
(2) $tx$ is committed and valid @$t (`update`, [l598](https://github.com/cometbft/cometbft/blob/1f524d12996204f8fd9d41aa5aca215f80f06f5e/mempool/clist_mempool.go#L598)).

$tx$ is removed from the cache @t if  
(3) $tx$ was received @t'<t, re-checked and invalid t'<@t''<t (`resCbRecheck`, [l477](https://github.com/cometbft/cometbft/blob/1f524d12996204f8fd9d41aa5aca215f80f06f5e/mempool/clist_mempool.go#L4747)), or  
(4) $tx$ is ejected from the cache as it is the last transaction wrt. cache and a new transaction is added.

$tx$ is added to the mempool @t if  
(5) $tx$ was received and added to the cache @t'<t, and was valid t'<@t"<t  (`addTx` after `recvCbFirstTime`, [l318](https://github.com/cometbft/cometbft/blob/1f524d12996204f8fd9d41aa5aca215f80f06f5e/mempool/clist_mempool.go#L318)).

$tx$ is removed from the mempool @t if  
(6) $tx$ is committed @t (`RemoveTx` after `removeTxByKey` after `update`, [l614](https://github.com/cometbft/cometbft/blob/1f524d12996204f8fd9d41aa5aca215f80f06f5e/mempool/clist_mempool.go#L614)), or  
(7) $tx$ is re-checked and invalid @t'<t (`removeTx` after `resCbRecheck`, [l474](https://github.com/cometbft/cometbft/blob/1f524d12996204f8fd9d41aa5aca215f80f06f5e/mempool/clist_mempool.go#L474)).

In addition, following the logic of CometBFT,  
- check and re-check operations are asynchronous,
- before committing transactions, checks and re-checks are frozen and all the pending calls return, and
- upon commit, all the transactions remaining in the mempool are re-checked.

**Correctness**
We now establish that the above algorithm implements the mempool abstraction.
For invariants INV2a and INV3a, we show that there exist such an $\alpha$ and $\beta$, but we do not look at characterizing them precisely.
Regarding INV4, we shall assume that step (1) occurs infinitely often and not once upon the reception of the transaction.
This models that a CometBFT client may re-submit a failed transaction forever until it succeeds (if it does).

The refinement mapping from `CListMempool` to the mempool abstraction is as follows:
Step (1) increments $p.valid[tx]$, which is initially set to 0.
Conversely, step (3) resets $p.valid[tx]$ to 0.
Transaction $tx$ is added to $p.lcommitted$ when step (2) occurs.
It is removed when (4) takes place.
Step (5) adds the transaction to the mempool.
The transaction is removed from the mempool upon (6) and (7).

Consider some correct process $p$.
Below, we show in order that all the invariants of the mempool are maintained at $p$:  

- INV1.
Clear from the code base, as the consensus input corresponds to a call to `Execution:CreateProposalBlock` which itself is calling `ClistMempool:ReapMaxBytesMaxGas`, returning a subset of $p.mempool$.

- INV2a.
If $tx$ is in $p.lcommitted$, it was added due to step (2).
This step occurs only if the transaction was committed at some (previous or current) height, as required.

- INV3a.
Assume $p.valid[tx]$ is larger than $0$ at a given height $h$.
For any transaction $tx$, this counter is set to $0$ initially.
Hence, $p.valid[tx]$ was incremented at some height $h' \leq h$.
Consider the point in time, where p moves to height $h$. 
If $p.valid[tx]$ equals 0 at that point in time, then it was incremented at height h, as required.
Otherwise, the transaction is rechecked at the current (new) height h.
Because $p.valid[tx]$ is not reset, it follows that the application considers it valid at h.

- INV4.
Consider that a transaction $tx$ enters the mempool at $p$.
If $tx$ leaves the mempool, step 6 or 7 happens.
In the former case, $tx$ is committed as required.
In the latter, $tx$ is re-checked and invalid at some height $h$.
Re-checking a transaction happens only once per height, say at time $t$ for $tx$ and height $h$.
When this happens at time $t$ (line 474), the transaction is also removed from the cache (line 477).
By assumption, step (1) is eventually re-executed for transaction $tx$ after time t.
Because $tx$ is no more in the cache, it is added again.
Hence, $tx$ eventually reaches again the cache after time $t$.
We can thus repeat the above reasoning.
Assume that transaction $tx$ is not forever invalid at process $p$.
This means that there exists a series of heights at which transaction $tx$ is valid.
Thanks to the gossip layer, this also hold eventually at all the correct processes.
As a consequence, eventually $tx$ is submitted at some height at which it is valid and committed there.


