// -*- mode: Bluespec; -*-

// 👉 This is WORK IN PROGRESS; not everything here is correct 👈 

/*
Dynamic Spanning Forest gossip protocol. Or Dinamic Optimal Graph (DOG) gossip protocol.

Briefly, if node A receives from B a transaction that it already has, this means that there must
exist a cycle in the network topology, so A tells B to stop sending transactions. So the idea is
simply to cut cycles (while respecting the graph!). 

The protocol adds two new messages to the current "flood" mempool: 
- HaveTx(TxKey) for cutting cycles, and 
- Reset for dynamic re-routing when a node disconnects (more on this later).

The rules:
- H1. If node A receives a transaction tx from node B that it already received (that is, it's in the
  cache), then A replies to B with a message HaveTx(tx).
    - HaveTx messages contains a transaction hash, so its size is insignificant. 
- H2. If node B receives a HaveTx(tx) message from node A, it disables the route sender(tx) → A. 
    - A route in a node is a tuple `sourceNodeID → targetNodeID`, with source and target being any
      of the node's peers. Initially, all nodes have all their routes enabled.
    - We don't want to cut all routes from B to A, only those that come from the transaction's
      original sender, that's why we need to take the source into account.
    - The protocol implicitly favours routes with low latency, by cutting routes to peers that send
      the duplicate tx at a later time.
- H3. Before node A sends a transaction tx to B, check if the route sender(tx) → B is enabled. 
    - Txs received from users are always gossiped to all peers.
- H4. After node A sends a HaveTx message to B, start a timer on A and don't let A send any other
  HaveTx message while the timer is on. 
    - This is to avoid a specific interleaving of messages that could render node A isolated from
      gossip traffic.
    - While the timer is on, we allow incoming traffic that flows from B to gradually stop. During
      this time, the traffic is diverted to other routes from other peers, while A still receives a
      small number of duplicate transactions (it's visible in the picture above).
    - The suggested minimum timeout should be the time it takes already-dispatched messages from B
      to arrive to A, so it's enough for the traffic from B to fully stop. We don't care to receive
      a few more duplicate transactions, therefore the timer could be safely extended to be sure
      that A does not become isolated.
- R1. If node A detects that its peer B is disconnected, remove any route that has B as source or
  target, and broadcast to all other peers a message Reset.
    - This is to signal A's peers that A's situation has changed and its routing data should be
      reset so it can be rerouted if needed.
- R2. On receiving a Reset message from A, remove any route that has A as source or target. 
    - This will allow traffic to flow again to A and nodes will dynamically adapt to the new
      traffic, closing routes when needed.
*/

module spanningForest {
    import spells.* from "./spells"
    
    type NodeId = str
    
    type Tx = str
    
    type Message =
        | T(Tx)      // "Here's a transaction."
        | HaveTx(Tx) // "I have this tx already; don't send me any more txs from the same source."
        | Reset      // "My situation has changed; reset my routing data on your side."
    
    pure def isTxMsg(msg) = match msg { T(_) => true | _ => false }
    pure def isHaveTxMsg(msg) = match msg { HaveTx(_) => true | _ => false }
    pure def isResetMsg(msg) = match msg { Reset => true | _ => false }

    type Step =
        | InitStep
        | ReceiveTxFromUserStep((NodeId, Tx))
        | BroadcastTxStep((NodeId, Tx, List[NodeId], Set[NodeId]))
        | ReceiveTxMessageStep((NodeId, NodeId, Tx))
        | ReceiveHaveTxMessageStep((NodeId, NodeId, Tx))
        | ReceiveResetMessageStep((NodeId, NodeId))
        | JoinNetworkStep((NodeId, Set[NodeId]))
        | DisconnectNetworkStep(NodeId)

    //--------------------------------------------------------------------------
    // Parameters
    //--------------------------------------------------------------------------
    
    // all nodes in the network, even those that have not joined yet
    const NodeIds: Set[NodeId]
    
    // all available txs
    const Txs: Set[Tx]
    
    // initial network topology
    const InitialPeers: NodeId -> Set[NodeId]

    //--------------------------------------------------------------------------
    // State
    //--------------------------------------------------------------------------

    // Incoming messages with sender.
    var msgs: NodeId -> Set[(NodeId, Message)]

    // The dynamic network topology.
    var peers: NodeId -> Set[NodeId]
    
    // Uncommitted transactions. For checking if the node already received a transaction and for
    // picking transactions to send to peers.
    var pool: NodeId -> List[Tx]

    // Index of the last gossipped transaction in the pool.
    //
    // NOTE: in the current implementation there is a separate goroutine for each peer (and thus a
    // separate pool index for each peer). In this model we broadcast to all peers atomically. We
    // should consider if it's worth to refine this variable.
    var poolIndex: NodeId -> int

    // For each node, a set of disabled routes `source -> target`.
    var disabledRoutes: NodeId -> Set[(NodeId, NodeId)]

    // To eep track of all peers that send a transaction to a node.
    var senders: NodeId -> Tx -> List[NodeId]

    // The set of transactions sent to each peer. History variable.
    var sentTxs: NodeId -> NodeId -> Set[Tx]

    // Last performed step; for traces.
    var step: Step

    //--------------------------------------------------------------------------
    // Actions
    //--------------------------------------------------------------------------

    action init = all {
        msgs' = NodeIds.mapBy(_ => Set()),
        peers' = InitialPeers,
        disabledRoutes' = NodeIds.mapBy(node => Set()),
        pool' = NodeIds.mapBy(_ => List()),
        poolIndex ' = NodeIds.mapBy(_ => -1),
        senders' = NodeIds.mapBy(_ => Map()),
        sentTxs' = NodeIds.mapBy(_ => Map()),
        step' = InitStep,
    }

    // A node receives a transaction from a user via an RPC endpoint.
    // It immediately sends the transaction to all its peers.
    // Users are allowed to submit the same tx more than once and to multiple nodes.
    // This action is only enabled if the transaction is not in the pool. In the current mempool
    // implementation we have the cache that prevents this scenario.
    action receiveTxFromUser(node, tx) = all {
        require(not(pool.get(node).includes(tx))),
        msgs' = msgs.mapPutMany(peers.get(node), p => msgs.get(p).setAdd((node, T(tx)))),
        peers' = peers,
        disabledRoutes' = disabledRoutes,
        pool' = pool.mapPut(node, txs => txs.append(tx)),
        poolIndex' = poolIndex,
        senders' = senders,
        sentTxs' = sentTxs,
        step' = ReceiveTxFromUserStep((node, tx)),
    }

    // Broadcast a given tx to all the peers of a given node, except if peer is sender(tx) or if the
    // route sender(tx) -> peer is disabled, where sender(tx) is any of the peers that have sent the
    // tx to this node.
    //
    // NOTE: in the current implementation, there is a separate goroutine for each peer, so not all
    // txs are sent at the same time.
    action broadcastTx(node, tx) = all {
        require(pool.get(node).includes(tx)),
        val txSenders = senders.get(node).mapGetSafe(tx).optionListToList()
        val disabledTargets = disabledRoutes.get(node).filter(r => txSenders.includes(r._1)).map(r => r._2)
        def targets = peers.get(node).exclude(disabledTargets).exclude(txSenders.listToSet())
        all {
            val msg = (node, T(tx))
            msgs' = msgs.mapPutMany(targets, p => msgs.get(p).setAdd(msg)),
            peers' = peers,
            disabledRoutes' = disabledRoutes,
            pool' = pool,
            senders' = senders,
            sentTxs' = sentTxs.mapPut(node, peerTxs => 
                if (peerTxs.keys().isEmpty()) targets.mapBy(t => Set(tx)) else
                peerTxs.mapPutMany(targets, p => if (peerTxs.keys().contains(p)) peerTxs.get(p).setAdd(tx) else Set(tx))),
            step' = BroadcastTxStep((node, tx, txSenders, targets)),
        }
    }

    // A node takes the next transaction from the pool and broadcast it to all its peers.
    action gossipOneTx(node) = 
        val i = poolIndex.get(node) + 1
        all {
            require(i < pool.get(node).length()),
            broadcastTx(node, pool.get(node)[i]),
            poolIndex' = poolIndex.mapPut(node, _ => i),
        }

    // TODO: a malicious node sends the same tx to one or more of its peers, maybe in coordination with another malicious node.
    // action gossipDuplicate(node) = ...

    // Handle a received Tx message.
    // If the transaction has been seen already (it's in the pool), reply with HaveTx(tx); otherwise add it to the pool.
    action handleTxMessage(node, sender, tx, msgs1) = all {
        senders' = senders.mapPut2(node, tx, List(), ls => ls.append(sender)),
        if (pool.get(node).includes(tx)) all {
            // reply HaveTx(tx)
            // TODO: send HaveTx message only if there's no incoming message from sender(tx) and sender(tx) has the route to this node disabled.
            //       This is to simulate the timeout that disables sending HaveTx.
            msgs' = msgs1.mapPut(sender, ms => ms.setAdd((node, HaveTx(tx)))),
            pool' = pool,
        } else all {
            // add tx to pool
            msgs' = msgs1,
            pool' = pool.mapPut(node, txs => txs.append(tx)),
        },
        disabledRoutes' = disabledRoutes,
        peers' = peers,
        poolIndex' = poolIndex,
        sentTxs' = sentTxs,
        step' = ReceiveTxMessageStep((node, sender, tx)),
    }

    // Disable the route (sender(tx) -> sender).
    pure def disable(routes, node, tx, txSenders, sender) =
        if (txSenders.listIsEmpty()) routes else
            routes.mapPut(node, rs => rs.setAdd((txSenders[0], sender)))

    // Handle a received HaveTx message.
    // Disable the route (sender(tx) -> sender).
    action handleHaveTxMessage(node, sender, tx, msgs1) = all {
        msgs' = msgs1,
        senders' = senders,
        val txSenders = senders.get(node).mapGetSafe(tx).optionListToList() // in most cases, there exists one and only one sender for tx
        disabledRoutes' = disabledRoutes.disable(node, tx, txSenders, sender),
        peers' = peers,
        pool' = pool,
        poolIndex' = poolIndex,
        sentTxs' = sentTxs,
        step' = ReceiveHaveTxMessageStep((node, sender, tx)),
    }

    pure def isSourceOrTarget(node, route) =
        node == route._1 or node == route._2

    // Remove any route that has sender as source or target. 
    pure def remove(routes, node, sender) = 
        routes.mapPut(node, rs => rs.filter(route => not(sender.isSourceOrTarget(route))))

    // Handle a received Reset message.
    // Remove any route that has the message sender as source or target. 
    action handleResetMessage(node, sender, msgs1) = all {
        msgs' = msgs1,
        senders' = senders,
        disabledRoutes' = disabledRoutes.remove(node, sender),
        peers' = peers,
        pool' = pool,
        poolIndex' = poolIndex,
        sentTxs' = sentTxs,
        step' = ReceiveResetMessageStep((node, sender)),
    }

    // A node receives a message from a peer and handles it according to its type.
    action receiveMessage(node) = all {
        require(msgs.get(node).nonEmpty()),
        // Give priority to control messages (HaveTx and Reset).
        val controlMsgs = msgs.get(node).filter(m => m._2.isHaveTxMsg() or m._2.isResetMsg())
        val msgTuple = if (controlMsgs.nonEmpty()) oneOf(controlMsgs) else oneOf(msgs.get(node))
        val sender = msgTuple._1
        val msg = msgTuple._2
        val msgs1 = msgs.mapPut(node, ms => ms.exclude(Set(msgTuple)))
        match msg {
        | T(tx) => handleTxMessage(node, sender, tx, msgs1)
        | HaveTx(tx) => handleHaveTxMessage(node, sender, tx, msgs1)
        | Reset => handleResetMessage(node, sender, msgs1)
        }
    }

    // A new node joins the network. 
    // Immediately all peers are aware and have it added to their list of peers.
    // TODO: join network only once.
    action joinNetwork(node: NodeId, peerIds: Set[NodeId]): bool = all {
        require(not(node.in(peers.keys()))),
        msgs' = msgs,
        peers' = peers.put(node, peerIds).mapPutMany(peerIds, peer => peers.get(peer).setAdd(node)),
        disabledRoutes' = disabledRoutes,
        pool' = pool,
        poolIndex' = poolIndex,
        senders' = senders,
        sentTxs' = sentTxs,
        step' = JoinNetworkStep((node, peerIds)),
    }

    // A node gets disconnected from the network.
    // All its peers are immediately aware that the node is no longer one of their peers.
    // TODO: this is not finished! Send Reset messages.
    // TODO: check that the network does not become disconnected; we don't want to model that.
    // TODO: disconnect from network only once.
    action disconnectNetwork(node) = all {
        msgs' = msgs,
        peers' = peers.mapRemove(node),
        disabledRoutes' = disabledRoutes,
        pool' = pool,
        poolIndex' = poolIndex,
        senders' = senders,
        sentTxs' = sentTxs,
        step' = DisconnectNetworkStep(node),
    }

    action nextState = 
        val nodes = peers.keys() // current nodes in the network
        any {
            nondet node = oneOf(nodes)
            node.gossipOneTx(),

            nondet node = oneOf(nodes)
            val tx = oneOf(Txs)
            node.receiveTxFromUser(tx),

            nondet node = oneOf(nodes)
            node.receiveMessage(),

            all {
                require(NodeIds.exclude(nodes).nonEmpty()),
                require(peers.keys().nonEmpty()),
                nondet node = oneOf(NodeIds.exclude(nodes))
                nondet peerIds = oneOf(peers.keys().powerset())
                node.joinNetwork(peerIds),
            },
            
            all {
                require(NodeIds.exclude(nodes).nonEmpty()),
                nondet node = oneOf(NodeIds.exclude(nodes))
                node.disconnectNetwork()
            },
        }

    //--------------------------------------------------------------------------
    // Properties
    //--------------------------------------------------------------------------

    // All messages have been delivered.
    val allMsgsDelivered = 
        NodeIds.forall(node => msgs.get(node).isEmpty())

    // The pools of all nodes contain a given tx.
    def txInAllPools(tx) =
        NodeIds.forall(n => pool.get(n).includes(tx))

    // All available transactions are in the pool of all nodes.
    val allTxsGossipped =
        NodeIds.forall(node => pool.get(node).listToSet().size() == Txs.size())

    // No node sends the same transaction more than once to the same peer.

    // The first time a node receives some tx from a user, the tx eventually reaches all nodes (possibly some nodes will receive it more than once).
    // The second time the node receives another tx from a user, the tx eventually reaches all nodes one and only once (the nodes don't get tx more than once).

    // When a transaction that is received by node A from a user, and the transaction in the pool of all nodes, 
    // then if the same transaction is received again on the same node A from a user, then the other nodes will not receive it a second time.

    //--------------------------------------------------------------------------
    // For debugging in REPL
    //--------------------------------------------------------------------------

    val state = (
        "msgs" -> msgs, 
        "peers" -> peers, 
        "disabledRoutes" -> disabledRoutes, 
        "pool" -> pool, 
        "senders" -> senders
    )

    def s(node) = (
        "msgs" -> msgs.get(node), 
        "peers" -> peers.get(node), 
        "disabledRoutes" -> disabledRoutes.get(node), 
        "pool" -> pool.get(node), 
        "poolIndex" -> poolIndex.get(node), 
        "senders" -> senders.get(node)
    )

    def s1 = s("n1")
    def s2 = s("n2")
    def s3 = s("n3")
    def s4 = s("n4")
    def s5 = s("n5")
    def s6 = s("n6")
    def s7 = s("n7")

}