# CONS/GOSSIP interaction

State transitions in CONS are specified as **actions** executed once certain pre-conditions apply, such as timeout expirations or reception of information from validators in the system.

An action may require communicating with applications and other reactors, for example to gather data to compose a proposal or to deliver decisions, and with the P2P layer, to communicate with other nodes.

## Northbound Interaction - ABCI

This specification focuses on the southbound interactions of CONS, with the GOSSIP and through GOSSIP-I with P2P.

For those interested in the interactions of CONS with applications and other reactors, we redirect the readers to the [Application Blockchain Interface (ABCI)](../../abci/) specification, which covers most of such communication.
ABCI specifies both what CONS [requires from the applications](../../abci/abci%2B%2B_app_requirements.md) and on what CONS [provides to Applications](../../abci/abci%2B%2B_tmint_expected_behavior.md).

Interactions with other reactors, such as with the Mempool reactor to build tentative proposals, will be covered elsewhere.

## Southbound Interaction - GOSSIP-I

CONS interacts southbound only with GOSSIP, to update the gossip state and to evaluate the current state to check for conditions that enable actions.

To update the state, CONS passes a tuple to GOSSIP with the exact content to be added to the tuple space through a function call.
Implementation are free to do this through message calls, IPC or any other means.

To check for conditions, we assume that CONS constantly queries the tuple space.
The exact mechanism of how conditions are evaluated is implementation specific, but some high level examples would be:

- check on conditions on a loop, starting from the highest known round of the highest known heigh and down the round numbers, sleeping on each iteration for some predefined amount of time;
- set callbacks to inspect conditions on a (heigh,round) whenever a new message for such heigh and round is received;
- provide GOSSIP with evaluation predicates that GOSSIP will execute according to its convenience and with callbacks to be invoked when the predicates evaluate to true.

All approaches should be equivalent and not impact the specification, even if the corresponding implementations would be much different.[^setsOfPred]

[^setsOfPred]: A simple query mechanism may be inefficient since every query must search the whole local view.
Sharing all queries beforehand may allow efficient evaluation, but breaks the GOSSIP-I abstraction.
Giving CONS access to the local views may be more efficient, but but also breaks the abstraction.

### Shared Vocabulary

CONS and GOSSIP share the type of tuples added/consulted to/from the tuple space.

```qnt reactor.gen.qnt
<<VOC-CONS-GOSSIP-TYPES>>
```

### Requires from GOSSIP

CONS is provided with functions to add and remove tuples from the space.[^removal]

[^removal]: removal of tuples has no equivalent in the Tendermint algorithm. **TODO** This is something to be added here.

```qnt reactor.gen.qnt
<<VOC-CONS-GOSSIP-ACTIONS>>
```

CONS is provided access to the local view.

```qnt reactor.gen.qnt
<<DEF-READ-TUPLE>>
```

> **Note**
> If you read previous versions of this draft, you will recall GOSSIP was aware of supersession. In this version, I am hiding supersession in REQ-CONS-GOSSIP-REMOVE and initially attributing the task of identifying superseded entries to CONS, which then removes what has been superseded. A a later refined version of this spec will clearly specify how supersession is handled and translated into removals.

As per the discussion in [Part I](#part-1-background), CONS requires GOSSIP to be a valid tuple space

```qnt reactor.gen.qnt
<<TS-VALIDTY>>
```

and to ensure Eventual $\Delta$-Timely Convergence** from GOSSIP

```qnt reactor.gen.qnt
<<REQ-CONS-GOSSIP-CONVERGENCE>>
```

### Provides to GOSSIP

> **TODO**

# Part III: GOSSIP requirements and provisions

GOSSIP, the Consensus Reactor Communication Layer, provides on its northbound interface the facilities for CONS to communicate with other nodes by adding and removing tuples and exposing the eventually converging tuple space.
On its southbound interface, GOSSIP relies on the P2P layer to implement the gossiping.

## Northbound Interaction - GOSSIP-I

Northbound interaction is performed through GOSSIP-I, whose vocabulary has been already [defined](#gossip-i-vocabulary).

Next we enumerate what is required and provided from the point of view of GOSSIP as a means to detect mismatches between CONS and GOSSIP.

### Requires from CONS
>
> **TODO**

### Provides to CONS
>
> **TODO**

## SouthBound Interaction

### P2P-I Vocabulary

Differently from the interaction between GOSSIP and CONS, in which GOSSIP understands CONS messages, P2P is oblivious to the contents of messages it transfers, which makes the P2P-I interface simple in terms of message types.

```qnt reactor.gen.qnt
<<VOC-GOSSIP-P2P-TYPES>>
```

P2P is free to establish connections to other nodes as long as it respect GOSSIP's restrictions, on the maximum number of connections to establish and on which nodes to not connect.

```qnt reactor.gen.qnt
<<VOC-CONS-GOSSIP-ACTIONS>>
```

GOSSIP needs to know to which other nodes it is connected.

```qnt reactor.gen.qnt
<<VOC-CONS-GOSSIP-ACTIONS>>
```

P2P must expose functionality to allow 1-1 communication with connected nodes.

```qnt reactor.gen.qnt
<<DEF-UNICAST>>
```

### Requires from P2P - P2P-I

Message to nodes that remain connected are reliably delivered.

```qnt reactor.gen.qnt
<<REQ-GOSSIP-P2P-UNICAST>>
```

The neighbor set of $p$ is never larger than `maxCon(p)`.
> TODO: can maxConn change in runtime?

```qnt reactor.gen.qnt
<<REQ-GOSSIP-P2P-CONCURRENT_CONN>>
```

Ignored processes should never belong to the neighbor set.

```qnt reactor.gen.qnt
<<REQ-GOSSIP-P2P-IGNORING>>
```
