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
