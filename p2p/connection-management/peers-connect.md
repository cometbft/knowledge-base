# Connecting to Peers

This document describes the execution flows in the p2p layer for establishing a
connection with a peer.

It distinguishes [inbound peers](#inbound-peers)
from [outbound peers](#outbound-peers), 
as the connection procedures are different, in fact mirrored.

Then, it describes the specific operation in the case of dialing nodes
configured as [persistent peers](#persistent-peers) and [seed nodes](#seeds).

Finally, RPC commands instructing the nodes to dial peer addresses are
described in the [Manual Dialing](#manual-dialing) section.

> This document does not cover all the execution flows of nodes operating in _seed mode_.

## Inbound Peers

An inbound peer is a peer that dials the node.
The node in the case accepts an incoming connection from the peer.

A node should keep at most the configured `MaxNumInboundPeers` active connections with inbound peers.

These are the steps for a node to accept a connection and add an inbound peer:

1. The Switch listens to the connections accepted by the Transport (`acceptRoutine` method)

1. The Transport returns an accepted inbound connection to the Switch
   encapsulated in a `Peer` object

   - `Transport.Accept(cfg)` returns a `peer`

1. The Switch rejects the connection if the maximum number of inbound peers is reached:

	```
	if peers.Inbound() >= config.MaxNumInboundPeers && !IsUnconditional(peer)
		transport.Cleanup(peer) // Disconnect
		continue
	```

 	- `peers.Inbound()` returns the number of connected peers with inbound connections

1. The Switch starts up the  `peer`, adds it to the `peers` set and to all registered reactors: `addPeer(peer)` method

   - In case of errors, the Switch asks the Transport to disconnect from the
     peer: `transport.Cleanup(peer)`

1. When the inbound `peer` is added to the PEX reactor, its address is added to the Address Book.


## Outbound Peers

An outbound peer is a peer that the node has dialed.
The node in this case establishes a connection with the peer.

A node should maintain the configured `MaxNumOutboundPeers` connections with outbound peers.
While the node has less than this number of outbound peers, it should attempt
to establish outbound connections with additional peers.

These are the steps for a node to dial a peer address and add an outbound peer:

1. The PEX reactor periodically checks whether the node needs to dial peers (`ensurePeers` method)

   - This check is performed every `ensurePeersPeriod = 30 seconds`

1. The PEX reactor compares the current number of outbound peers with the
   target number of outbound peers.
   Candidate peer addresses to dial, if needed, are retrieved from the Address Book:

   ```
   while peers.Outbound() + peers.Dialing() < config.MaxNumOutboundPeers
   	addr = addrbook.PickAddress(bias)
   	dialPeer(addr)
   ```

   - `peers` is the set of peers tracked by the Switch
   - `peers.Dialing()` returns the number of peers in the `dialing` state
   - `peers.Outbound()` returns the number of connected peers with outbound connections

1. The PEX reactor checks with the Switch if the selected peer addresses
   are not in use

   - Addresses from already connected peers or from a peers the Switch is
     currently dialing are skipped

1. The PEX reactor dials in parallel the selected peer addresses (concurrent
   calls to `dialPeer` method)

1. The PEX reactor checks if the node can immediately attempt to dial the peer address:

	```
	if dialAttempts > maxAttemptsToDial
		return errMaxAttemptsToDial
	if time.Since(lastDialedTime) < backoffDuration
		return errTooEarlyToDial
	```

   - If a new dial cannot be attempted, the procedure is interrupted for this peer address

1. The PEX reactor invokes the Switch to dial the address: `Switch.DialPeerWithAddress(addr)`

1. The Switch sets the peer (`addr.ID`) to the `dialing` state

1. The Switch invokes the Transport to dial the peer: `Transport.Dial(addr, cfg)`

   - In case of errors when dialing the peer, skip to the last step.

1. The Transport returns the established outbound connection to the Switch
   encapsulated in a `Peer` object

1. The Switch starts up the `peer`, adds it to the `peers` set and to all registered reactors: `addPeer(peer)` method

   - In case of errors, the Switch asks the Transport to disconnect from the
     peer: `transport.Cleanup(peer)`

1. The Switch removes the peer (`addr.ID`) from the `dialing` state

### Expedite Dialing

The following procedure has been introduced to speed up, in some scenarios, the
process of dialing peers:


1. The PEX reactor receives a PEX response `PexAddrs` message from a peer configured as a _seed node_

1. The PEX reactor adds the received list of peer addresses to the Address Book (`ReceiveAddrs` method) 

1. The PEX reactor dials in parallel every peer addressed received (`dialPeer`
   method).  From this point, the procedure is the same as for
dialing a peer address and adding an outbound peer, starting from step 5.

> As detailed in this [issue](https://github.com/cometbft/cometbft/issues/486),
> this procedure does not take into consideration the configured limit of
> outbound peers (`MaxNumInboundPeers`), and should be reconsidered or fixed.

## Persistent Peers

The persistent peers configuration option defines a list of peer addresses to
which the node should maintain persistent connections.
The steps for establishing connections to a persistent peers are the following:

1. As part of the Node creation procedure, the Switch is configured with a list of persistent peers

   - The `NewNode()` constructor invokes `Switch.AddPersistentPeers(config.P2P.PersistentPeers)`

1. As part of the Node startup procedure, the Switch is invoked to dial the configured persistent peers

   - The `Node.OnStart()` method invokes `Switch.DialPeersAsync(config.P2P.PersistentPeers)`

1. The Switch parses the persistent peer addresses (strings) into network addresses

   - Errors are returned to the Node and the procedure is interrupted

1. The Switch adds the persistent peer addresses to the Address Book and
   persists the Address Book

1. The remaining steps are performed in parallel for every persistent peer address (`dialPeersAsync` method)

1. The Switch sleeps for random interval, from 0 to 3 seconds (`randomSleep` method)

1. The Switch dials the persistent peer address: `DialPeerWithAddress(addr)`

1. The Switch sets the peer (`addr.ID`) to the `dialing` state

1. The Switch invokes the Transport to dial the peer: `Transport.Dial(addr, cfg)`

   - In case of errors when dialing the peer, skip to the last step.
   - In parallel, the Switch spawns a routine to 
    [dial the persistent peer again](#reconnect-to-peer): `reconnectToPeer` method

1. The Transport returns the established outbound connection to the Switch
   encapsulated in a `Peer` object

1. The Switch starts up the `peer`, adds it to the `peers` set and to all registered reactors: `addPeer(peer)` method

   - In case of errors, the Switch asks the Transport to disconnect from the
     peer: `transport.Cleanup(peer)`

1. The Switch removes the peer (`addr.ID`) from the `dialing` state

### Reconnect to Peer

If a connection attempt to a peer configured as persistent peer fails, or if
the connection with a persistent peer is dropped, the node is expected to
reconnect to the persistent peer.  

The following steps are performed to reconnect to a peer (`reconnectToPeer` method):

1. The Switch checks whether the peer is already in the `reconnecting` state.
   If this is the case, the current execution of this routine is aborted, as
   there is another concurrent execution in progress.

1. The Switch sets the peer (`addr.ID`) to the `reconnecting` state

1. The Switch sleeps for random interval (`randomSleep` method) with a given target duration:

   1. For the first `reconnectAttempts = 20`, a linear back off: `reconnectInterval = 5s`
   1. For the following `reconnectBackOffAttempts = 10`, an exponential back
      off: with each new attempt the target duration is multiplied by
      `reconnectBackOffBaseSeconds = 3`

1. The Switch dials the persistent peer address: `DialPeerWithAddress(addr)`.

   -  The procedure here is the same as for establishing a connection to a
      [persistent peer](#persistent-peers), starting from step 8.

1. If the connection attempt fails and the number of failed attempts is below
the maximum number of attempts (`reconnectAttempts + reconnectBackOffAttempts = 30`),
go back to step 2.

1. The Switch removes the peer (`addr.ID`) from the `reconnecting` state,
   indicating that:

   1. The reconnection to the persistent peer has succeeded
   1. Or the Switch has given up attempting to reconnect to the persistent peer.


## Seeds

A node attempts dialing to the configured seed nodes in the following scenario:

1. As part of the Node creation procedure, the PEX reactor receives a list of seed node addresses

   - The `NewNode()` constructor passes `config.P2P.Seeds` to the PEX `ReactorConfig`

1. The PEX reactor periodically checks whether the node needs to dial peers (`ensurePeers` method)

   - This check is performed every `ensurePeersPeriod = 30 seconds`

1. The PEX reactor defines that the node needs to dial peers, namely:

   `peers.Outbound() + peers.Dialing() < config.MaxNumOutboundPeers`

1. The PEX reactor, however, fails to retrieve dialable peer addresses from the
   Address Book, because either:

   - The Address Book is empty or does not contain valid addresses
   - All the peer addresses retrieved from the Address Book are already in use

1. The PEX reactor tries dialing to the configured seed node addresses (`dialSeeds` method)

1. The PEX reactor randomly sorts the list of configured seed node addresses 

1. The PEX reactor invokes the Switch to dial the next seed node address: `Switch.DialPeerWithAddress(addr)`

   - The procedure here is the same as for establishing a connection to an
     [outbound peer](#outbound-peers), starting from step 7.

1. If the connection attempt fails, step 6 is repeated for the next
   seed node address in the randomly sorted list

1. The procedure is completed when either:

   1. The connection attempt to the selected seed node addresses succeeds
   1. The node is already connected to the selected seed node
   1. All the configured seed node addresses were dialed without success

The goal of this procedure is to request peer addresses to a seed node.
The following is expected to happen once the outbound connection to a
configured seed node is established:

1. When the seed node is a added as outbound peer, the PEX reactor sends a
   `PexRequest` message to it

1. The remote peer is expected to reply to the PEX request with a `PexAddrs`
   message, containing peer addresses

   - When the `PexAddrs` message is received, the 
     [Expedite Dialing](#expedite-dialing) procedure should take place

1. As a seed node, the remote peer is expected to disconnect from the
   node after sending the PEX response

The `dialSeeds` method can also complete without establishing a new connection
with a seed node, in particular if the node is already connected to a seed
node, situation in which the above procedure is not performed.


## Manual Dialing

The RPC endpoint contains two unsafe methods allowing to manually dial peers:

- [/dial_seeds](https://docs.cometbft.com/main/rpc/#/Unsafe/dial_seeds):
  receives a list of seed node addresses to dial
  - This method does not update the list of configured seed node addresses
- [/dial_peers](https://docs.cometbft.com/main/rpc/#/Unsafe/dial_peers):
  receives a list of peer addresses to dial
  - This method allows configuring the provided peer addresses as persistent,
    unconditional, or private

In spite of different descriptions, the implementation of both RPC methods
(in `rpc/core/net.go`) rely on the Switch `Switch.DialPeersAsync(addrs)`
method, the same used to dial [persistent peers](#persistent-peers) on startup.

The `/dial_peers` method, in addition, before dialing the provided addresses
can configure them as:

- Persistent using `Switch.AddPersistentPeers(addrs)`
- Private using `Switch.AddPrivatePeerIDs(addrs)`.
Private addresses are not exchanged by the PEX protocol.
- Unconditional using `Switch.AddUnconditionalPeerIDs(addrs)`.
Unconditional peers do not count to the limit of inbound peers
(`MaxNumInboundPeers`) a node can be connected to.

Notice that the same methods are used when creating a node, based on the
content of the configuration file.

Unsafe RPC methods are disabled by default, but they can be enabled in the
configuration file for testing.
