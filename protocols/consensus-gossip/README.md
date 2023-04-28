# README

## Organization

This specification is divided into multiple documents and should be read in the following order:

- [layers.md](./layers.md): the entry point for the specification
- [tuple-space.md](./tuple-space.md): background on why we specify the communication in Tendermint as a convergent tuple-space.
- [gossip.md](./gossip.md): English specification of GOSSIP, GOSSIP-I, and how GOSSIP may use P2P.
    > :warning: The text is filled with `<<TAGS>>` that will eventually be used to implement "literate" specification (automatically include the corresponding snippets from the Quint spec). In the mean time, use the tag to locate the corresponding definition in on of the accompanying `.qnt` files. [^todo1]

- Quint
  - Essential
    - [Helpers.qnt](./Helpers.qnt): Handy Quint spells;
    - [Globals.qnt](./Globals.qnt): Global definitions;

TODO

    - [GossipI.qnt](./GossipI.qnt): GOSSIP-I interface;
    - [GossipAbstract.qnt](./GossipAbstract.qnt): State and actions shared by GOSSIP-I "implementations";
    - [P2PI.qnt](./P2PI.qnt): The P2P-I interface;[^todo2]
    - [P2PAbstract.qnt](./P2PAbstract.qnt): State and actions shared by P2P-I "implementations";

  - Extra (for spec testing)[^todo4]
    - `GossipInstP2P.qnt`: GOSSIP-I implementation in which nodes synchronize with each other using some P2P-I implementation;
    - `GossipInstCheat.qnt`: GOSSIP-I implementation in which gossiped state is immediately seen by all nodes (used for testing specs);
    - `GossipInstNoP2P.qnt`: GOSSIP-I implementation in which nodes synchronize with each other, but without using the P2P layer (used for testing specs);
    - `GossipTests.qnt`: tests the GOSSIP-I implementations (requires manual tweaking);
    - `P2PInstNetwork.qnt`: P2P-I implementation in which messages are added to a set of messages to be eventually delivered;
    - `P2PInstCheat.qnt`: P2P-I implementation in which messages are immediately delivered by the destination.(used for testing specs);
    - `P2PTests.qnt`: tests the P2P-I implementations (requires manual tweaking);
  - Relationship between `.qnt` files (see on github):
    - Edges indicate that source imports the target;
    - Named edges indicate named imports;
    - Blocks of modules indicate a choice of mutually exclusive imports;
    - Red modules have state that must be updated or marked unchanged;
    - Green blocks do not have state;

        ```mermaid
        graph BT
        subgraph P2PInst
            P2PInstCheat & P2PInstNetwork
        end
        P2PTests --P2PInst--> P2PInst --PA-->P2PAbstract --> P2pI --> Globals

        subgraph GInst
            GossipInstCheat
            GossipInstNoP2P
            GossipInstP2P
        end
        GossipTests --GInst--> GInst --GA--> GossipAbstract -->GossipI --> Globals
        GossipAbstract --P2PInst-->P2PInst

        style GossipInstCheat fill:green
        style GossipInstNoP2P fill:green
        style GossipI fill:green
        style Globals fill:green
        style P2pI fill:green
        style P2PInstCheat fill:green
        style P2PInstNetwork fill:green


        style GossipInstP2P fill:#904000
        style GossipAbstract fill:#904000
        style P2PAbstract fill:#904000
        ```

- Current implementation. [^todo3]

[^todo1]: TODO: Remove comment once literate programming is used.

[^todo2]: TODO: Compatibilize with the P2P spec work.

[^todo3]: TODO: Provide [implementation.md](./implementation.md) with a description of what is currently implemented in CometBFT, in English and [implementation.qnt](./implementation.qnt), in Quint, for model checking of provided properties.

[^todo4]: to be added in a followup PR.

## Conventions

- MUST, SHOULD, MAY... are used according to RFC2119.
- [X-Y-Z-W.C]
  - X: What
    - VOC: Vocabulary
    - DEF: Definition
    - REQ: Requires
    - PROV: Provides
  - Y-Z: Who-to whom
  - W.C: Identifier.Counter

## Status

- V1 - Consolidation of work done on PR #74 as a "mergeable" PR.
