# Part 1: Tuple Space

> :warning:
> We assume that you understand the Tendermint algorithm and therefore we will not review it here.
If this is not the case, please refer to the [Consensus specification](../).

Three kinds of messages are exchanged in the Tendermint algorithm: `PROPOSAL`, `PRE-VOTE`, and `PRE-COMMIT`.
The algorithm progresses when certain conditions are satisfied over the set of messages received.
For example, in order to decide on a value `v`, the set must include a `PROPOSAL` for `v` and `PRE-COMMIT` for the same `v` from more than two thirds of the validators for the same round.
Since processes are subject to failures, correct processes cannot wait indefinitely for messages since the sender may be faulty.
Hence, processes execute in rounds in which they wait for conditions to be met for some time but, if they timeout, send negative messages that will lead to new rounds.


## The need for Gossip Communication

Progress and termination are only guaranteed in if there exists a **Global Stabilization Time (GST)** after which communication is reliable and timely (Eventual $\Delta$-Timely Communication).

| Eventual $\Delta$-Timely Communication|
|-----|
|There is a bound $\Delta$ and an instant GST (Global Stabilization Time) such that if a correct process $p$ sends a message $m$ at a time $t \geq \text{GST}$ to a correct process $q$, then $q$ will receive $m$ before $t + \Delta$.

Eventual $\Delta$-Timely Communication is used to provide **Gossip Communication**, which ensures that all messages sent by correct processes will be eventually delivered to all correct processes.

|Gossip communication|
|-----|
| (i) If a correct process $p$ sends some message $m$ at time $t$, all correct processes will receive $m$ before $\text{max} (t,\text{GST}) + \Delta$.
| (ii) If a correct process $p$ receives some message $m$ at time $t$, all correct processes will receive $m$ before $\text{max}(t,\text{GST}) + \Delta$.

This will, in turn, lead all correct processes to eventually be able to execute a round in which the conditions to decide are met, even if only after GST is reached.

Even if Eventual $\Delta$-Timely Communication is assumed, implementing Gossip Communication would be unfeasible.
Given that all messages, even messages sent before the GST, need to be buffered to be reliably delivered between correct processes and that GST may take indefinitely long to arrive, implementing this primitive would require unbounded memory.

Fortunately, while Gossip Communication is a sufficient condition for the Tendermint algorithm to terminate, it is not strictly necessary:
i) the conditions to progress and terminate are evaluated over the messages of subsets of rounds executed, not all of them; ii) as new rounds are executed, messages in previous rounds may be become obsolete and be ignored and forgotten.
In other words, the algorithm does not require all messages to be delivered, only messages that advance the state of the processes.

## Node's state as a Tuple Space

One way of looking at the information used by CometBFT nodes is as a distributed tuple space (a set of tuples) to which all nodes contribute.
Entries are added by validators over possibly many rounds of possibly many heights.
Each entry has form $\lang h, r, s, p, v \rang$ and corresponds to the message validator node $p$ sent in step $s$ of round $r$ of height $h$; $v$ is a tuple with the message payload.
To propose a value, the proposer adds it to the tuple space, and to vote for a proposal, a validator adds the vote.

Each tuple is signed by the validator adding it to the tuple space.
Since each tuple includes the height, round, there is no room for forgery (and any attempt to add differing entries for the same heigh and round by the same validator will be seen as evidence of misbehavior).[^todo1]

Because nodes are part of an asynchronous distributed system, individual nodes can only maintain approximations of the tuple space, to which they try to converge.
There are essentially two ways of making the tuple space converge.

- **Approach One**: nodes broadcast all the updates they want to perform to all nodes, including themselves.
If using Reliable Broadcast/Gossip Communication, the tuple space will eventually converge to include all broadcast messages.
- **Approach Two**: nodes periodically compare their approximations with each other, 1-to-1, to identify and correct differences by adding missing entries, using some gossip/anti-entropy protocol.

These approaches work to reach convergence because the updates are commutative regarding the tuple space; each update simply adds an entry to a set.
From the Tendermint algorithm's point of view, convergence guarantees progress but is not requirement for correctness.[^todo2]
In other words, nodes observing different approximations of the tuple space may decide at different point in time but cannot violate any correctness guarantees and the eventual convergence of tuple space implies the eventual termination of the algorithm.

[^todo1]: Formalize using [Making CRDTs Byzantine Fault Tolerant](https://martin.kleppmann.com/papers/bft-crdt-papoc22.pdf) as basis; "Many CRDTs, such as Logoot [44] and Treedoc [ 36], assign a unique identifier to each item (e.g. each element in a sequence); the data structure does not allow multiple items with the same ID, since then an ID would be ambiguous.”

[^todo2]: This should be trivial from the fact that the first approach is essentially Tendermint using Gossip Communication.


### Tuple Removal and Garbage Collection

In both approaches for synchronization, the tuple space could grow indefinitely, given that the number of heights and rounds is infinite.
To save memory, entries should be removed from the tuple space as soon as they become stale, that is, they are no longer useful.
For example, if a new height is started, all entries corresponding to previous heights become stale.

In general, simply forgetting stale entries in the local view would save the most space.
However, it could lead to entries being added back or circulating on the network.
Even if re-adding tuples does not compromise CometBFT's correctness, removed entries should not be added again, for performance and resource utilization sake.

Re-adding entries may be prevented by keeping _tombstones_ for the removed entries.
We note the tombstone for an entry $e$ as $\bar{e}$.

With time, even small tombstones may accrue and need to be garbage collected, in which cause the corresponding entry may be added again; again, this will not break correctness and as long as tombstones are kept for long enough, the risk of re-adding is minimal.

In the case of the Tendermint algorithm we note that staleness comes from adding newer messages (belonging to higher rounds and heights) to the tuple space.
Hence, in Approach Two, if as an optimization these newer messages are exchanged first, then the stale messages can be excluded before being shared to other nodes that might have forgotten them and tombstones may not be needed at all.


### Querying the Tuple Space

The tuple space is consulted through queries, which have the same form as the entries.
Queries return all entries whose values match those in the query, where a `*` matches all values.
For example, suppose a node's local view of the tuple space has the following entries, here organized as rows of a table for easier visualization:

| Height | Round | Step     | Validator | Value |
|--------|-------|----------|-----------|-------|
| 1      | 0     | Proposal | p         | pval  |
| 1      | 0     | PreVote  | p         | vval  |
| 1      | 1     | PreCommit| q         | cval  |
| 2      | 0     | Proposal | p         | pval' |
| 2      | 2     | PreVote  | q         | vval' |
| 2      | 3     | PreCommit| q         | cval' |

- Query $\lang 0, 0, Proposal, p, * \rang$ returns $\{ \lang 0, 0, Proposal, p, pval \rang \}$
- Query $\lang 0, 0, *, p, * \rang$ returns $\{ \lang 0, 0, Proposal, p, pval \rang,  \lang 0, 0, PreVote, p, vval \rang \}$.


#### Local views

Let $T$ be the tuple space and $t_p$ be node $p$'s approximation of $T$, also denominated $p$'s **local views**.
Because of the asynchronous nature of distributed systems, local views may not include entries in the space or may still include entries no longer in the space.

Formally, let $P$ be the set of validators; $T = \cup_P t_p$ and $e \in T \Leftrightarrow \exists p \in P, e \in t_p \land \not\exists q \in Q, \bar{e}\in t_q$

Nodes can only query their own local views, not $T$.
If needed for disambiguation, queries are subscripted with the node being queried.

#### State Validity

Let $\text{ValSet}_h$ be the set of validators of height $h$ and $\text{Prop}_{h,r}$ be the proposal of round $r$ of height $h$.

Given that each validator can execute each step only once per round, a query that specifies height, round, step and validator must either return empty or a single tuple.

- $\forall h \in \N, r \in \N, s \in \{\text{Proposal, PreVote, PreCommit}\}, v \in \text{ValSet}_h$,  $\lang h, r, s, v, * \rang$ returns at most one value.

In the specific case of the Proposal step, only the proposer of the round can have a matching entry.

- $\forall h \in \N, r \in \N, \lang h, r, \text{Proposal}, *, * \rang$ returns at most one value and it also matches $\lang h, r, \text{Proposal}, \text{Prop}_{h,r}, * \rang$.

A violation of these rules is a proof of misbehavior.


### Eventual Convergence

Consider the following definition for **Eventual Convergence**.

|Eventual Convergence|
|-----|
| If there exists a correct process $p$ such that $e \in t_p$, then, eventually, for every correct process $q$, $e \in t_q$ or there exists a correct process $r$ such that $\bar{e} \in t_r$.|

> **Note**
> Nodes may learn of an entry deletion before learning of its addition.

In order to ensure convergence even in the presence of failures, the network must be connected in such a way to allow communication around any malicious nodes and to provide redundant paths between correct ones.
This can be achieved if there is a GST, after which timeouts eventually do not expire precociously, given that they all can be adjusted to reasonable values, which implies that all communication will eventually happen timely, which implies that the tuple space will converge and keep converging.
Formally, if there is a GST then following holds true:

| Eventual $\Delta$-Timely Convergence |
|---|
| If $e\in t_p$, for some correct process $p$, at instant $t$, then by $\text{max}(t,\text{GST}) + \Delta$, either $e \in t_q$, for every correct process $q$ or $\bar{e} \in t_p$.

Although GST may be too strong an expectation, in practice timely communication frequently happens within small stable periods, also leading to convergence.


### Why use a Tuple Space

Let's recall why we are considering using a tuple space to propagate Tendermint's messages.
It should be straightforward to see that Reliable Broadcast may be used to achieve Eventual Convergence and Gossip Communication may be used to implement Eventual $\Delta$-Timely Convergence:
to add an entry to the tuple space, broadcast the entry;
once delivered, add the entry to the local view.[^proof]
If indeed we use Gossip Communication, then there are no obvious gains.

It should also be clear that if no entries are ever removed from the tuple space, then the inverse is also true:
to broadcast a message, add it to the local view;
once an entry is added to the local view, deliver it.

However, if entries can be removed, then the Tuple Space is actually weaker, since some entries may never be seen by some nodes, and should be easier to implement.
We argue later that it can be implemented using Anti-Entropy or Epidemic protocols/Gossiping (not equal Gossip Communication).
We pointed out [previously](#the-need-for-gossip-communication) that Gossip Communication is overkill for Tendermint because it requires even stale messages to be delivered.
Removing tuple is exactly how stale messages get removed.


[^proof]:  TODO: do we need to extend here?


### When to remove

> **TODO** Define conditions for tuple removal.

## The tuple space as a CRDT

The two approaches described [earlier](#nodes-state-as-a-tuple-space), without the deletion of entries, correspond to operation-based and state-based [Grow-only SET](https://en.wikipedia.org/wiki/Conflict-free_replicated_data_type#G-Set_(Grow-only_Set)) CRDT (G-Set).
This distributed data-structure is easily described as a set per process in which elements are added to include them G-Set; the sets kept by processes are approximations of the G-Set.

The [2 Phase-Set](https://en.wikipedia.org/wiki/Conflict-free_replicated_data_type#2P-Set_(Two-Phase_Set)) (2P-Set) is a variation that allows removals.
It combines two sets, one in which elements are added to include them in the 2P-Set, $A$, and one in which elements are added to remove them from the 2P-Set, $D$; the actual membership of the 2P-Set is given by $A \setminus D$.




> Warning/TODO: A word about tombstones, that is $D$
>
> - Only state that is not required should be deleted/tombstone'd.
> - Instead of tombstones, add new entries that trigger removal of other entries (for example, state about a new height); each node must be given information to realize by itself that an entry is no longer needed.
> - Tombstones are an optimization, kept to prevent data recreation and redeletion.
> - Tombstones should be garbage collected at some point; imprecision shouldn't affect correctness/termination, since this is an optimization (as long as deleted state is never required again).
> - Tombstones are not to be gossiped; if they were, they would need to carry proof for the reason they were created, defeating their point.

