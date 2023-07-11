# Mempool

In this document, we define the notion of **mempool** and characterize its role in the **CometBFT** protocol.
First, we provide an overview of what is a mempool, and relates it to other blockchains.
Then, the interactions with the consensus and client application are detailed.
A formalization of the mempool follows.
We close this document with a proof that the current implementation of the mempool in CometBFT (as of v0.38.0-rc1) is correct.

## Overview

The mempool acts as an entry point to consensus.
It permits to disseminate transactions from one node to another, for their eventual inclusion in the blockchain.
To this end, the mempool maintains a replicated set, or _pool_, of transactions.
Transactions in the mempool are consumed by consensus to create the next proposed block.
The mempool is refreshed once a new block in the blockchain  is decided.

A transaction can be received from a local client, or a remote disseminating process.
Each transaction is subject to a test by the client application.
This test verifies that the transaction is _valid_.
Such a test provides some form of protection against byzantine agents, whether they be clients or other system nodes.
It also serves to optimize the overall utility of the blockchain.
Validity can be simply syntactical which is stateless, or a more complex verification that is state-dependent.
If the transaction is valid, the local process further propagates it in the system using a gossip (or an anti-entropy) mechanism.

_In other blockchains._
The notion of mempool appears in all blockchains, but with varying definitions and/or implementations.
For instance in Ethereum, the mempool contains two types of transactions: processable and pending ones.
To be pending, a transactions must first succeed in a series of tests.
Some of these tests are [syntactic](https://github.com/ethereum/go-ethereum/blob/281e8cd5abaac86ed3f37f98250ff147b3c9fe62/core/txpool/txpool.go#L581) ones (e.g., valid source address), while [others](https://github.com/ethereum/go-ethereum/blob/281e8cd5abaac86ed3f37f98250ff147b3c9fe62/core/txpool/txpool.go#L602) are state-dependent (e.g., enough gas, at most one pending transactions per address, etc).
[Narwhal](https://arxiv.org/abs/2105.11827.pdf) is the mempool abstraction for the Tusk and [Bullshark](https://arxiv.org/pdf/2201.05677) protocols.
It provides strong global guarantees.
In particular, once a transaction is added to the mempool, it is guaranteed to be available at any later point in time.

## Interactions

In what follows, we present the interactions of the mempool with other parts of the CometBFT protocol.
Some of the specificities of the current implementation (`CListMempool`) are also detailed.
For further information about the current implementation, the reader may consult the overview [document](https://github.com/cometbft/knowledge-base/blob/main/protocols/mempool/v0/mempool-v0.md), as well as the quint [specification](https://github.com/cometbft/knowledge-base/pull/11/files).

**RPC server**
To add a new transaction to the mempool, a clients may submit it through an appropriate RPC endpoint.
This endpoint is offered by some of the system nodes (but not necessarily all of them).

**Gossip protocol** 
Transactions can also be received from other nodes, through a gossiping mechanism.

**ABCI application**
As pointed above, the mempool should only store and disseminate  valid transactions.
It is up to the ABCI (client) application to define whether a transaction is valid.
Transactions received locally are sent to the application to be validated, through the `checkTx` method from the mempool ABCI connection.
Such a check indicates with a flag whether it is the first time (or not) that the transaction is received.
Transactions that are validated by the application are later added to the mempool.
Transactions tagged as invalid are simply drooped.
The validity of a transaction may depend on the state of the client application.
In particular, some transactions that are valid in some state of the application may later become invalid.
The state of the application is updated when consensus commits a block of transactions.
When this happens, the transactions still in the mempool have to be validated again.
We further detail this mechanism below.

**Consensus**
The consensus protocol consumes transactions stored in the mempool to build blocks to be proposed.
To this end, consensus requests from the mempool a list of transactions which abide by certain limits (namely, total number of transactions included, or total size in bytes).
In the current implementation, the mempool is a list of transactions.
Such a call returns the longest prefix of the list that is matching the requirements.
Notice that at this point the transactions returned to consensus are not removed from the mempool.
This comes from the fact that the block is proposed but not decided yet.

Proposing a block is the prerogative of the nodes acting as validators.
At all the nodes (validators or not), consensus is also responsible for committing blocks of transactions to the blockchain.
Once a block is committed, all the transactions included in the block are removed from the mempool.
This happens with an `update` call to the mempool.
Before doing this call, consensus takes a `lock` on the mempool.
It then `flush` the connection with the client application.
Both operations aim at preventing any concurrent `checkTx` while the mempool is updated.
At the end of `update`, all the transactions still in the mempool are re-validated against the new state of the client application.
This procedure is executed asynchronously with a call to `recheckTxs`.
Finally, consensus removes its lock on the mempool by issuing a call to `unlock`.

## Formalization

In what follows, we formalize the notion of mempool.
To this end, we first provide a (brief) definition of what is a ledger, that is a replicated log of transactions.
At a process $p$, we shall write $p.var$ the local variable $var$ at $p$.

**Ledger.**
We use the standard definition of (BFT) SMR in the context of blockchain, where each process $p$ has a ledger, written $p.ledger$.
At process $p$, the $i$-th entry of the ledger is denoted $p.ledger[i]$.
This entry contains either a null value ($\bot$), or a set of transactions, aka., a block.
The height of the ledger at $p$ is the index of the first null entry; denoted $p.height$.
Operation $submit(txs, i)$ attempts to write the set of transactions $txs$ to the $i$-th entry of the ledger.
The (history) variable $p.submitted[i]$ holds all the transactions (if any) submitted by $p$ at height $i$.
By extension, $p.submitted$ are all the transaction submitted by $p$.
A transaction is committed when it appears in one of the entries of the ledger.
We write $p.committed$ the committed transactions at $p$.

As standard, the ledger ensures that:  
* _(Gap-freedom)_ There is no gap between two entries at a correct process:  
$\forall i \in 	\mathbb{N}. \forall p \in Correct. \square(p.ledger[i] \neq \bot \implies (i=0 \vee p.ledger[i-1] \neq \bot))$;  
* _(Agreement)_ No two correct processes have different ledger entries; formally:  
$\forall i \in 	\mathbb{N}. \forall p,q \in Correct. \square((p.ledger[i] = \bot) \vee (q.ledger[i] = \bot) \vee (p.ledger[i] = q.ledger[i]))$;  
* _(Validity)_ If some transaction appears at an index $i$ at a correct process, then a process submitted it at that index:  
$\forall p \in Correct. \exists q \in Processes. \forall i \in 	\mathbb{N}. \square(tx \in p.ledger[i] \implies tx \in \bigcup_q q.submitted[i]$).
* _(Termination)_ If a correct process submits a block at its current height, eventually its height get incremented:  
$\forall p \in Correct. \square((h=p.height \wedge p.submitted[h] \neq \varnothing) \implies \lozenge(p.height>h))$  

**Mempool.**
A mempool is a replicated set of transactions.
At a process $p$, we write it $p.mempool$.
We also define $p.hmempool$, the (history) variable that tracks all the transactions ever added to the mempool by process $p$.
Below, we list the invariants of the mempool (at a correct process).

The mempool is used as an input for the ledger:  
**INV1.** $\forall tx. \forall p \in Correct. \square(tx \in p.submitted \implies tx \in p.hmempool)$

Committed transactions are not in the mempool:  
**INV2.** $\forall tx. \forall p \in Correct. \square(tx \in p.committed \implies tx \notin p.mempool)$

In blockchain, a transaction is (or not) valid in a given state.
That is, a transaction can be valid (or not) at a given height of the ledger.
To model this, consider a transaction $tx$.
Let $p.ledger.valid(tx)$ be such a check at the current height of the ledger at process $p$ (ABCI call).
Our third invariant is that only valid transactions are present in the mempool:  
**INV3.** $\forall tx, \forall p \in Correct. \square(tx \in p.mempool \implies p.ledger.valid(tx))$

Finally, we require some progress from the mempool.
Namely, if a transaction appears at a correct process then eventually it is committed or forever invalid.  
**INV4** $\forall tx. \forall p \in Correct. \square(tx \in p.mempool \implies \lozenge\square(tx \in p.committed \vee \neg p.ledger.valid(tx)))$

The above invariant ensures that if a transaction enters the mempool, then it eventually leaves it at all the correct processes.
For this to be true, the client application must ensure that the validity of a transaction converges toward some value.
That is, there is a height after which $valid(tx)$ always returns the same value.
This requirement is termed _eventual non-oscillation_ (see this [section](https://github.com/cometbft/cometbft/blob/main/spec/abci/abci%2B%2B_app_requirements.md) of the ABCI documentation).
It also appears in [Ethereum](https://github.com/ethereum/go-ethereum/blob/5c51ef8527c47268628fe9be61522816a7f1b395/light/txpool.go#L401) as a transaction is always valid until a transaction from the same address executes with the same or higher nonce.
A simple way to satisfy this for the programmer is by having $valid(tx)$ deterministic and stateless (e.g., a syntactic check).

A quint specification of the above abstraction is available [here](https://github.com/cometbft/knowledge-base/blob/main/quint/mempool/Mempool.qnt).

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
**INV3a.** $\forall tx. \forall p \in Correct. \square(tx \in p.hmempool \implies p.valid[tx] \in [1, \beta])$

## Correctness of the implementation in CometBFT (as of v0.38.0-rc1)

The mempool is implemented in `clist_mempool.go`, in the `CListMempool` data type.
`CListMempool` uses a single variable for the two mechanisms covered in the previous section.
Below, we present this approach at coarse grain, then establish its correctness.

**Algorithm**
For starters, we explain at a high-level the logic in `CListMempool`.
Variables `txs` and `cache` respectively hold the mempool and the validity cache in a FIFO and LRU list.
We omit the use of `txsMap`, assuming that a transaction is in `txs` iff it is also in `txsMap` (see [this](https://github.com/cometbft/cometbft/pull/890) fix).
For simplicity, we shall also consider that
- the mempool is never full,
- invalid transactions are _not_ kept in the cache (`mem.config.KeepInvalidTxsInCache=false`), and
- the mempool rechecks the transactions that are still present (`mem.config.Recheck=true`).

In addition, we shall assume that a finite amount of transactions is received by the system, and that if a transaction is received at a correct process, then it is eventually received at all the correct processes (thanks to the gossip layer in `mempool/reactor.go`).

Then, let us consider some transaction $tx$.
According to the logic in `clist_mempool.go`,

$tx$ is added to the cache at time $t$ (in short, @t) if  
(1) $tx$ is received and not already there @t (`checkTx`, [l237](https://github.com/cometbft/cometbft/blob/1f524d12996204f8fd9d41aa5aca215f80f06f5e/mempool/clist_mempool.go#L237)), or  
(2) $tx$ is committed and valid @t (`update`, [l598](https://github.com/cometbft/cometbft/blob/1f524d12996204f8fd9d41aa5aca215f80f06f5e/mempool/clist_mempool.go#L598)).

$tx$ is removed from the cache @t if  
(3) $tx$ was received @t'<t, re-checked and invalid t'<@t''<t (`resCbRecheck`, [l477](https://github.com/cometbft/cometbft/blob/1f524d12996204f8fd9d41aa5aca215f80f06f5e/mempool/clist_mempool.go#L4747)), or  
(4) $tx$ is ejected from the cache as it is the last transaction wrt. cache and a new transaction is added, or  
(5) $tx$ is committed and invalid @t'<t (`update`, [l598](https://github.com/cometbft/cometbft/blob/1f524d12996204f8fd9d41aa5aca215f80f06f5e/mempool/clist_mempool.go#L601)).

$tx$ is added to the mempool @t if  
(6) $tx$ was received and added to the cache @t'<t, and was valid t'<@t"<t  (`addTx` after `recvCbFirstTime`, [l318](https://github.com/cometbft/cometbft/blob/1f524d12996204f8fd9d41aa5aca215f80f06f5e/mempool/clist_mempool.go#L318)).

$tx$ is removed from the mempool @t if  
(7) $tx$ is committed @t (`RemoveTx` after `removeTxByKey` after `update`, [l614](https://github.com/cometbft/cometbft/blob/1f524d12996204f8fd9d41aa5aca215f80f06f5e/mempool/clist_mempool.go#L614)), or  
(8) $tx$ is re-checked and invalid @t'<t (`removeTx` after `resCbRecheck`, [l474](https://github.com/cometbft/cometbft/blob/1f524d12996204f8fd9d41aa5aca215f80f06f5e/mempool/clist_mempool.go#L474)).

In addition, following the logic of CometBFT,  
- check and re-check operations are asynchronous,
- before committing transactions, checks and re-checks are frozen and all the pending calls return, and
- upon commit, all the transactions remaining in the mempool are re-checked.

**Correctness**
We now establish that the above algorithm implements the mempool abstraction.
For invariants INV2a and INV3a, we show that **there exist** such an $\alpha$ and $\beta$, but we do not look at characterizing them precisely.
Regarding INV4, we shall assume that step (1) occurs infinitely often and not once upon the reception of the transaction.
This models that a CometBFT client may re-submit a transaction forever until it succeeds (if it does), i.e., it is both committed and valid at some height.

The refinement mapping from `CListMempool` to the mempool abstraction is as follows:
Step (1) increments $p.valid[tx]$, which is initially set to 0.
Conversely, steps (3) and (5) reset $p.valid[tx]$ to 0.
Transaction $tx$ is added to $p.lcommitted$ when step (2).
It is removed when (4) takes place.
Step (6) adds the transaction to the mempool.
The transaction is removed from the mempool upon (7) and (8).

Consider some correct process $p$.
Below, we show in order that all the invariants of the mempool are maintained at $p$:  

- INV1.
Clear from the code base, as the consensus input corresponds to a call to `Execution:CreateProposalBlock` which itself is calling `ClistMempool:ReapMaxBytesMaxGas`, returning a subset of $p.mempool$.

- INV2a.
If $tx$ is in $p.lcommitted$, it was added due to step (2).
This step occurs only if the transaction was committed at some height.
Furthermore, when this happens step (7) is taken.
It follows, that the transaction is removed from the mempool, as required.

- INV3a.
Consider some height $h$ for which $tx$ is in the mempool and $p.valid[tx]>0$.
For any transaction $tx$, this counter is set to $0$ initially.
Hence, $p.valid[tx]$ was incremented at some height $h' \leq h$.
Consider the point in time $t'$, where p moves to height $h$.
If $p.valid[tx]$ equals 0 at that time, then it was incremented at height h.
From (6), it is necessarily valid at height $h$, as required.
Otherwise, the transaction is rechecked at the current (new) height h with step (8).
Because $p.valid[tx]$ is not reset, it follows that the application considers it valid at h 

- INV4.
Consider that a transaction $tx$ enters the mempool at $p$.
If $tx$ leaves the mempool, step (7) or (8) happens.
In the former case, $tx$ is committed as required.
In the latter, $tx$ is re-checked and invalid at some height $h$.
Re-checking a transaction happens only once per height, say at time $t$ for transaction $tx$ and height $h$.
When this happens at time $t$ (line 474), the transaction is also removed from the cache (line 477) due to step (3).
By assumption, step (1) is eventually re-executed for transaction $tx$ after time $t$.
Because $tx$ is no more in the cache, it is added again after time $t$.
Now, assume that transaction $tx$ is not invalid infinitely often at process $p$.
By assumption, the validity of a transaction converges toward some value.
Hence after some time, it is always valid at $p$.
Observe that this is also eventually the case at all the correct processes in the system.
Name $t'$ the moment in time when this occurs.
By assumption, there are only a bounded amount of transactions submitted in the system.
After time $max(t,t')$, $tx$ is eventually submitted at some height at which it is valid and committed.

*A remark.* 
The reader might observe that in the above reasoning we do not use step (5).
This comes from the fact that strictly speaking this step is not necessary for the mempool invariants to hold.
One could consider a stronger variation of INV4 in which a transaction is eventually either 
forever invalid,
or at some height both valid and committed.
This variation would necessitate step (5) to oust a committed yet invalid transaction from the cache.
It remains unclear whether this stronger variation of INV4, and thus of the mempool abstraction, is of interest or not to applications.
