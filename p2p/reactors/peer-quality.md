# Peer: mark as good or bad

This document derives from discussions on [CometBFT's PR #851][pr-851].

The [`Switch`][switch-type] offers to reactors a method to 
[mark as peer as a good peer][good-peer]:

    func (sw *Switch) MarkPeerAsGood(peer Peer)

However, there is no method in the [API to Reactors][p2p-api] to mark a peer as
a bad peer.
Observe that the [`AddrBook` interface][addr-iface] have methods to mark a
peer as a good or as a bad peer.
In fact, the PEX reactor marks peers as bad in some situations.

## Mark peer as good

## Mark peer as bad

## Peer banning

[addr-iface]: https://github.com/cometbft/cometbft/blob/main/p2p/pex/addrbook.go#L37
[switch-type]: https://github.com/cometbft/cometbft/blob/main/p2p/switch.go
[good-peer]: https://github.com/cometbft/cometbft/blob/main/spec/p2p/reactor/p2p-api.md#vetting-peers

[pr-851]: https://github.com/cometbft/cometbft/pull/851
[p2p-api]: https://github.com/cometbft/cometbft/blob/main/spec/p2p/reactor/p2p-api.md
