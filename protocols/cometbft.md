CometBFT consists of multiple protocols, namely,
- Consensus (Tendermint consensus)
- Mempool [[mempool-overview]]
- Evidence
- Blocksync
- Statesync

that each plays a role in making sure that validators can produce blocks. These protocols are implemented in so-called reactors (one for each protocol) that encode two functionalities:

- Protocol logic (controlling the local state of the protocols and deciding what messages to send to others, e.g., the rules we find in the arXiv paper)

- Communication. Implement the communication abstractions needed by the protocol on top of the p2p system (e.g., Gossip)

> perhaps we should clarify nomenclature: the Consensus gossip service actually is not implemented by a gossip algorithm but a peer-to-peer system

The p2p system maintains an overlay network that should satisfy a list of requirements (connectivity, stability, diversity in geographical peers) that are inherited from the communication needs of the reactors that are discussed here [[reactor-survey]].

CometBFT communicates with the (SMR) application via ABCI:

- ABCI spec (as of `v0.38.x`) _mandates_ that `ProcessProposal` MUST fulfill the following two requirements (non exhaustive)
  - Coherence (1 requirement)
  - Determinism (worded as two requirements)
- dYdX have an application use case that cannot (currently) guarantee these two properties
  - PBTS spec has a similar problem if expressed in terms of ABCI++ (timely predicate)
  - They filed
    - Changes that were needed for PBTS in `v0.36.x`:
      - [#1171](https://github.com/cometbft/cometbft/issues/1171) - DONE
      - [#1231](https://github.com/cometbft/cometbft/issues/1231) - DONE
    - [#1174](https://github.com/cometbft/cometbft/issues/1174)
      - It is a proposal to handle non-determinism in `ProcessProposal`
      - We have discussed internally, the result is [RFC105](https://github.com/cometbft/cometbft/blob/main/docs/rfc/rfc-105-non-det-process-proposal.md)
