# Questions regarding the P2P API for Reactors

This source of this discussion is [CometBFT PR #851][pr-851].

The discussed topics are in companion files:

- [`peer-kvstore.md`](./peer-kvstore.md): discussion regarding the key-value
  store provided by the `Peer` interface to reactors. It is used as a state
  sharing mechanism. Details about the specific use from Consensus, Mempool,
  and Evidence reactors (WIP).
- [`peer-quality.md`](./peer-quality.md): the `Switch` provides a method for
  marking peers as good, only used by the consensus reactor. There is no method
  for marking a peer as bad or banning a peer. Details of the PEX reactor uses
  this feature provided by the Address Book (WIP).
- [`stop-peer.md`](./stop-peer.md): the `Switch` provides a method for stopping
  a peer due to an error. This method has a `reason` field which actual use is
  not specified or implemented. Moreover, the same `Switch` method is used by
  multiplex connections as well, in addition to reactors (WIP).
- [`switch-peer.md`](./switch-peer.md): the API for reactors is split in two
  parts: methods provided by the `Switch` type and methods provided by the
  multiple `Peer` instances, one per connected peer. Discusses the reasons for
  this separation, while providing some extra details of the intricated
  relation between `Peer` instances and the `Switch`.

The goal is to collect the ideas here, discuss them, and see what should go into issues on the main repo.

[pr-851]: https://github.com/cometbft/cometbft/pull/851
