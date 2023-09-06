# Allowing Non-Determinism in `ProcessProposal` (a.k.a. addressing #1174)

## Context

### Consensus Properties

Byzantine Fault Tolerant (BFT) Consensus is usually specified by the following properties.
For every height $h$:

- _agreement_: no two correct processes decide differently.
- _validity_: function $valid(v, bc_{h-1})$, when applied to the decided block, always returns _true_.
- _termination_: all correct processes eventually decide.

The _validity_ property refers to $valid(v, bc_{h-1})$, which is defined as a (mathematical) function
whose output depends exclusively on its inputs: the value proposed $v$ (i.e., a block),
and the state of the blockchain after applying the block decided at height $h-1$,
denoted $bc_{h-1}$.

The consensus algorithm implemented in CometBFT (Tendermint) fulfills these properties.

### ABCI interface

In the version of ABCI (`v0.17.0`) that existed before ABCI 1.0 and 2.0 (a.k.a. ABCI++),
the implementation of function $valid(v, bc_{h-1})$ was totally internal to CometBFT.
Technically, the application's part of $bc_{h-1}$ was not considered by function $valid()$.
Thus, the application had no direct say on the validity of a block,
although it could (and still can) influence it indirectly via the best-effort ABCI call `CheckTx`.

With the evolution of ABCI to ABCI 1.0 and 2.0, CometBFT's implementation of
function $valid(v, bc_{h-1})$ now has two components:

- the validity checks performed directly by CometBFT on blocks
  (block format, hashes, etc; the same as in ABCI `v0.17.0`)
- the validity checks that now the application can perform as part of `ProcessProposal`;
  i.e., `ProcessProposal` is now part of $valid(v, bc_{h-1})$

With the new structure of the implementation of function $valid(v, bc_{h-1})$:

- consensus _agreement_ is not affected and all processes are still required to agree on the same value
- the consensus _validity_ property is not affected since we are changing the
  internals of function $valid(v, bc_{h-1})$; consensus _validity_ just requires this function to be true

However, the new structure of the implementation of function $valid(v, bc_{h-1})$
may affect _termination_ of consensus, as some implementations of `ProcessProposal` might reject values
that CometBFT's internal validity checks would otherwise accept.

This document focuses on how consensus _termination_ is affected
by the new structure of function $valid(v, bc_{h-1})$,
in particular, the different implementations of `ProcessProposal`.

### ABCI 1.0 (and 2.0) Specification

The [ABCI 1.0 specification][abci-spec] imposes a set of new requirements on the application
so that its implementation of `PrepareProposal` and `ProcessProposal` does not compromise _termination_ of consensus,
given the current CometBFT consensus algorithm
(called Tendermint, and described in the [arXiv paper][arxiv]).
In contrast to $valid(v, bc_{h-1})$, which is defined as a mathematical function used for consensus's formal specification,
`PrepareProposal` and `ProcessProposal` are understood as implemented functions in CometBFT.
We reproduce here the requirements in the ABCI 1.0 (and 2.0) specification that are relevant for this discussion.

Let $p$ and $q$ be two correct processes.
Let $r_p$ be a round of consensus at height $h$ where $p$ is the proposer.
Let $s_{p,h-1}$ be $p$'s application's state committed for height $h-1$.
In other words, $s_{p,h-1}$ is $p$'s view of $bc_{h-1}$.
Let $v_p$ be the block that $p$'s CometBFT passes
on to the application
via `RequestPrepareProposal` as proposer of round $r_p$, height $h$,
known as the _raw proposal_.
Let $u_p$ be the (possibly modified) block that $p$'s application
returns via `ResponsePrepareProposal` to CometBFT in round $r_p$, height $h$,
known as the _prepared proposal_.

* Requirement 3 [`PrepareProposal`, `ProcessProposal`, coherence]: For any two correct processes $p$ and $q$
  and any round $r_p \geq 0$,
  if $q$'s CometBFT calls `RequestProcessProposal` on $u_p$,
  $q$'s application returns _Accept_ in `ResponseProcessProposal`.

* Requirement 4 [`ProcessProposal`, determinism-1]:
  `ProcessProposal` is a (deterministic) function of the current
  state and the block being processed.
  In other words, for any correct process $p$, and any arbitrary block $u$,
  if $p$'s CometBFT calls `RequestProcessProposal` on $u$ at height $h$,
  then $p$'s application's acceptance or rejection **exclusively** depends on $u$ and $s_{p,h-1}$.

* Requirement 5 [`ProcessProposal`, determinism-2]:
  For any two correct processes *p* and *q*, and any arbitrary
  block $u$,
  if CometBFT instances at $p$ and $q$ call `RequestProcessProposal` on $u$ at height $h$,
  then $p$'s application accepts $u$ if and only if $q$'s application accepts $u$.
  Note that this requirement follows from the previous one and consensus _agreement_.

The requirements expressed above are good enough for most applications using ABCI 1.0 or 2.0.
They are simple to understand and it is relatively easy to check whether an application's
implementation of `PrepareProposal` and `ProcessProposal` fulfills them.
All applications that are able to enforce these properties do not need to reason about
the internals of the consensus implementation: they can consider it as a black box.
This is the most desirable situation in terms of modularity between CometBFT and the application.

The easiest (and thus canonical) way to ensure these requirements is to make sure
that `PrepareProposal` only prepares blocks $v$ that satisfy (mathematical) function `valid(v, bc(h-1))`,
and `ProcessProposal` just evaluates the same function.
However, `PrepareProposal` and `ProcessProposal` MAY also use other input in their
implementation, but a priori, CometBFT only guarantees consensus termination
if these implementations still ensure the requirements.

## Problem Statement

This document is dealing with the case when an application cannot guarantee
the coherence and/or determinism requirements as stated in the ABCI 1.0 specification.

An example of this is when `ProcessProposal` needs to take inputs from third-party entities
(e.g. price oracles) that are not guaranteed to provide exactly the same values to
different processes during the same height.
Another example is when `ProcessProposal` needs to read the system clock in order to perform its checks
(e.g. Proposer-Based Timestamp when expressed as an ABCI 1.0 application).

In principle, if an application's implementation of `PrepareProposal` and `ProcessProposal`
is not able to fulfill coherence and determinism requirements,
CometBFT cannot guarantee consensus _termination_ in all runs of the system.
As a result, the application designers a priori must start considering both CometBFT and their application
as one monolithic block, in order to reason about termination.
We thus lose the modularity provided when fulfilling the ABCI 1.0 requirements.
Remember that CometBFT's consensus algorithm (Tendermint) is a well-known algorithm that
has been studied, reviewed, formally analyzed, model-checked, etc.
The combination of CometBFT and an arbitrary application as one single algorithm cannot
leverage that extensive body of research applied to the Tendermint algorithm.
This situation is risky and undesirable.

So, the questions that arise are the following.
Can we come up with a set of weaker requirements
that applications unable to fulfill the current ABCI 1.0 requirements
can still fulfill?
Can we maintain modularity with these new requirements?
Is this set of weaker requirements still strong enough to guarantee consensus _termination_?

## Solution Proposed

### Modified consensus _validity_

Function $valid(v, bc_{h-1})$, as explained above, exclusively depends on its inputs
(a block, and the blockchain state at the previous height).
So it is always supposed to provide the same result when called at the same height for the same inputs,
no matter at which process.
This was the main reason for introducing the determinism requirements on `ProcessProposal`
in the ABCI 1.0 specification.

If we are to relax the determinism requirements on the application,
we first need to modify function $valid()$ to be of the form $valid(v, bc_{h-1}, x_p)$,
where $x_p$ is a variable local to process $p$.
As $x_p$ may be different from $x_q$ for two processes $p$ and $q$, using
$valid(v, bc_{h-1}, x_p)$ to implement in `PrepareProposal`  and `ProcessProposal`
may break Requirements 3 to 5.

Consensus _validity_ property is then modified as follows:

- _weak validity_: function $valid(v, bc_{h-1}, x_p)$ has returned _true_ at least once
  by a correct process for the decided block $v$.

### Eventual Requirements

We now relax the relevant ABCI 1.0 requirements in the following way.

* Requirement 3b [`PrepareProposal`, `ProcessProposal`, eventual coherence]:
  There exists a round $r_s \ge 0$ of height $h$ such that,
  for any two correct processes $p$ and $q$ and any round $r_p \geq r_s$,
  if $q$'s CometBFT calls `RequestProcessProposal` on $u_p$,
  $q$'s application returns _Accept_ in `ResponseProcessProposal`.

* The determinism-related requirements, namely requirements 4 and 5, are removed.

We call round $r_s$ the coherence-stabilization round.

If we think in terms of $valid(v, bc_{h-1}, x_p)$, notice that it is the application's responsibility
to ensure 3b, that is, the application designers need to prove that the $x_p$ values at correct processes
are evolving in a way that eventually `ResponseProcessProposal` returns _Accept_ at some correct process.
For instance, in Proposer-Based Timestamp, $x_p$ can be considered to be process $p$'s local clock,
and having clocks synchronized is the mechanism ensuring eventual acceptance of a proposal.

> [TODO: can we _tighten up_ eventual coherence?... i.e., make it even weaker?]
>
> [TODO: Since we have removed determinism, can byzantine proposers cause mayhem now?]

### Modifications to the consensus Algorithm

The Tendermint algorithm as described in the [arXiv paper][arxiv],
and as implemented in CometBFT up to version `v0.38.0-rc3`,
cannot guarantee consensus _termination_ for applications
that just fulfill requirement 3b (eventual coherence), but do not fulfill requirements 3, 4, and 5.

We need the following modifications (in terms of the algorithm as described in page 6 of the arXiv paper):

- remove the evaluation of `valid(v)` in lines 29, 36 and 50 (i.e. replace `valid(v)` by `true`)
- modify line 23 as follows

> _\[Original\]_ &nbsp; 23: **if** $valid(v) \land (lockedRound_p = −1 \lor lockedValue_p = v)$ **then**

> _\[Modified\]_
>
> &nbsp; 23a: $validValMatch := (validRound_p \neq -1 \land validValue_p = v)$
>
> &nbsp; 23b: **if** $[lockedRound_p = −1 \land (validValMatch \lor valid(v))] \lor lockedValue_p=v$ **then**

The occurrences of `valid(v)` that we have removed were in a way redundant,
so removing them does not affect the ability of the algorithm to fulfill consensus properties.
Notice we have kept the original `valid(v)` notation, but it stands for the more general $valid(v, bc_{h-1}, x_p)$.
These algorithmic modifications have also been made to CometBFT (on branch `main`)
as part of issues [#1171][1171], and [#1230][1230].

## Conclusion

This document has explored the possibility of relaxing the coherence and determinism properties
of the ABCI 1.0 (and 2.0) specification affecting `PrepareProposal` and `ProcessProposal`
for a class of applications that cannot guarantee them.

We first weakened the _validity_ property of the consensus specification
in a way that keeps the overall consensus specification strong enough to be relevant.
We then proposed a weaker coherence property for ABCI 1.0 (and 2.0) that can replace the original
coherence and determinism properties related to `PrepareProposal` and `ProcessProposal`.
The new property is useful for applications that cannot fulfill the original properties
but can fulfill the new one.
Finally, we explained how to modify the Tendermint consensus algorithm to guarantee
the consensus _termination_ property for applications that fulfill the new property.

In this document, we have not tackled the problem of applications
that cannot fulfill coherence and determinism properties that refer to vote extensions in the ABCI 2.0 specification.
We leave this as future work.

[abci-spec]: https://github.com/cometbft/cometbft/blob/main/spec/abci/abci++_app_requirements.md#formal-requirements
[arxiv]: https://arxiv.org/abs/1807.04938
[1171]: https://github.com/cometbft/cometbft/issues/1171
[1230]: https://github.com/cometbft/cometbft/issues/1230
