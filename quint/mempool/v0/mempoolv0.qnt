// -*- mode: Bluespec; -*-
/** Mempool V0
  *
  * One of the goals of this spec is to easily map actions and data structures
  * to the implementation. 
  */

// Assumptions/Simplifications: 
// - The network topology is fixed: nodes do not leave or join the network, peers do not change.

module mempoolv0 {
    import basicSpells.* from "./basicSpells"
    import params as Params from "./base"
    import base.* from "./base"
    import errors.* from "./errors"
    import chain as Chain from "./chain"
    import abciServers as ABCI from "./abciServers"
    import network as Network from "./network"
    import history as History from "./history"

    //--------------------------------------------------------------------------
    // Spec parameters
    //--------------------------------------------------------------------------
    val MempoolMaxSize: int = 
        Params::__MempoolMaxSize
    // assume(MempoolMaxSize > 0)

    type Config = { keepInvalidTxsInCache: bool }
    val Configs: NodeId -> Config = 
        Params::__Configs

    //--------------------------------------------------------------------------
    // Auxiliary variables
    //--------------------------------------------------------------------------
    type Step = str

    // To keep track of the step (one of the actions defined in `step`) taken by
    // a node.
    var _step: { node: NodeId, name: Step, args: str -> str }

    action setStep(node, s, args) =
        _step' = { node: node, name: s, args: args }

    // To keep track of the error, if any, of the step taken by a node.
    var _error: { node: NodeId, error: Error }

    action setError(node, err) =
        _error' = { node: node, error: err }

    //--------------------------------------------------------------------------
    // Mempool state
    //--------------------------------------------------------------------------
    
    // The data structure stored of the elements stored in the mempool.
    // [mempoolTx]: https://github.com/CometBFT/cometbft/blob/6498d67efdf0a539e3ca0dc3e4a5d7cb79878bb2/mempool/clist_mempool.go#L671
    type MempoolTx = { 
        tx: Tx, 
        height: Height, // height at which tx was validated
        senders: Set[NodeId] // peers that send tx, or none if tx was emmitted by a client
    }

    val noMempoolTx = { tx: "", height: 0, senders: Set() }

    // The main data structure in the mempool. 
    // The actual implementation is a list (a queue), but we modelled it as a
    // set, because for the moment we don't need to reason about the order of
    // transactions.
    var mempool: NodeId -> Set[MempoolTx]

    // The transactions received by a node, to avoid handling repeated
    // transactions.
    var cache: NodeId -> Set[Tx]

    // The height of the last block to which the mempool was updated to.
    var mempoolHeight: NodeId -> Height

    def Mempool(nodeId) = mempool.get(nodeId)
    def Cache(nodeId) = cache.get(nodeId)
    def MempoolHeight(nodeId) = mempoolHeight.get(nodeId)

    //--------------------------------------------------------------------------
    // Cache auxiliary definitions
    //--------------------------------------------------------------------------
    action addToCache(node, tx) =
        cache' = cache.mapPut(node, (txs) => txs.setAdd(tx))

    action forceRemoveFromCache(node: NodeId, tx: Tx): bool =
        cache' = cache.mapPut(node, (txs) => txs.setRemove(tx))

    action removeFromCache(node, invalidTx_) =
        if (not(Configs.get(node).keepInvalidTxsInCache))
            node.forceRemoveFromCache(invalidTx_)
        else cache' = cache

    //--------------------------------------------------------------------------
    // Mempool auxiliary definitions
    //--------------------------------------------------------------------------
    def mempoolIsFull(node) =
        size(node.Mempool()) > MempoolMaxSize

    def mempoolTxs(node: NodeId): Set[Tx] = 
        node.Mempool().map(e => e.tx)

    // Returned value is Optional: either none or a singleton.
    def memTxFor(node: NodeId, tx: Tx): Set[MempoolTx] =
        node.Mempool().filter(e => e.tx == tx)

    // Get the element from the singleton or none in any other case
    def chooseSomeMemTxFor(node: NodeId, tx: Tx): MempoolTx =
        // node.memTxFor(tx).chooseSome()
        val memTxs = node.memTxFor(tx).setToList()
        if (memTxs.length() == 1) memTxs[0] else noMempoolTx

    // Returned value is Optional: either none or a singleton.
    def sendersFor(node: NodeId, tx: Tx): Set[NodeId] = 
        node.memTxFor(tx).map(e => e.senders).flatten()

    def inMempool(node, tx) =
        tx.in(node.mempoolTxs())

    def senderFor(node, tx) = 
        node.Mempool().map(e => e.tx)

    action addToMempool(node, tx, h, senderId) =
        val senders = if (senderId == noNode) Set() else Set(senderId)
        val memTx = { tx: tx, height: h, senders: senders }
        mempool' = mempool.mapPut(node, (memTxs) => memTxs.setAdd(memTx))

    action removeFromMempool(node: NodeId, txs: Set[Tx]): bool =
        mempool' = mempool.mapPut(node, (memTxs) => memTxs.filter(e => e.tx.notIn(txs)))

    action addSender(node, tx, senderId) =
        if (node.inMempool(tx)) {
            val oldMemTx: MempoolTx = node.chooseSomeMemTxFor(tx)
            val newMemTx = oldMemTx.with("senders", oldMemTx.senders.union(senderId))
            mempool' = mempool.mapPut(node, (memTxs) => memTxs.setRemove(oldMemTx).setAdd(newMemTx))
        } else mempool' = mempool

    //--------------------------------------------------------------------------
    // Actions
    //--------------------------------------------------------------------------
    action init = all {
        mempool' = NodeIds.mapBy(_ => Set()),
        cache' = NodeIds.mapBy(_ => Set()),
        _step' = { node: noNode, name: "init", args: Map() },
        _error' = { node: noNode, error: noError },
        mempoolHeight' = NodeIds.mapBy(_ => 0),
        History::init,
        Network::init,
        Chain::init,
        ABCI::init,
    }
    
    // Validate an incoming transaction by sending an ABCI request to the
    // application.
    // [CListMempool.CheckTx]: https://github.com/CometBFT/cometbft/blob/5a8bd742619c08e997e70bc2bbb74650d25a141a/mempool/clist_mempool.go#L202
    //-- __subaction__: this action is not part of the next-state relation
    action CheckTx(node: NodeId, tx: Tx, senderId: NodeId): bool = all {
        if (node.mempoolIsFull()) all {
            node.setError(MempoolIsFullError),
            mempool' = mempool,
            cache' = cache,
            ABCI::unchanged,
        } else if (tx.in(node.Cache())) all {
            // Record new sender for the tx we've already seen.
            // Note it's possible a tx is still in the cache but no longer in the mempool
            // (eg. after committing a block, txs are removed from mempool but not cache),
            // so we only record the sender for txs still in the mempool.
            node.addSender(tx, senderId),
            node.setError(TxInCacheError),
            cache' = cache,
            ABCI::unchanged,
        } else all {
            node.addToCache(tx),
            node.ABCI::sendRequestNewCheckTx(tx, senderId, node.MempoolHeight() + 1),
            node.setError(noError),
            mempool' = mempool,
        },
        mempoolHeight' = mempoolHeight,
    }

    // Callback function to process a CheckTx response of type "New".
    // Note that tx and sender are arguments to CListMempool.resCbFirstTime.
    // [CListMempool.resCbFirstTime]: https://github.com/CometBFT/cometbft/blob/6498d67efdf0a539e3ca0dc3e4a5d7cb79878bb2/mempool/clist_mempool.go#L369
    action ReceiveCheckTxResponse(node) = all {
        node.setStep("ReceiveCheckTxResponse", Map()),
        require(node.ABCI::checkTxRequests().nonEmpty()),
        nondet req = oneOf(node.ABCI::checkTxRequests()) 
        val resp = node.ABCI::responseFor(req)
        all {
            node.ABCI::removeRequest(req),
            if (resp.err == noError) {
                if (node.mempoolIsFull()) all {
                    node.forceRemoveFromCache(req.tx), // There may be enough space for tx later.
                    node.setError(MempoolIsFullError),
                    mempool' = mempool,
                    History::unchanged,
                } else all { 
                    require(not(node.inMempool(req.tx))),
                    val senderId = node.ABCI::senderFor(req)
                    val h = node.ABCI::heightFor(req) // height at which tx was validated
                    node.addToMempool(req.tx, h, senderId),
                    node.setError(noError),
                    node.History::recordMempoolTx(req.tx),
                    cache' = cache,
                }
            } else all { // ignore invalid transaction
                node.removeFromCache(req.tx),
                node.setError(InvalidTxWarning),
                mempool' = mempool,
                History::unchanged,
            }
        },
        mempoolHeight' = mempoolHeight,
        Network::unchanged,
        Chain::unchanged,
    }

    /** Consensus' BlockExecutor calls Update to update the mempool after executing txs.
      * txResults are the results of ResponseFinalizeBlock for every tx in txs.
      * BlockExecutor holds the mempool lock while calling this function.
      */
    // [CListMempool.Update]: https://github.com/CometBFT/cometbft/blob/6498d67efdf0a539e3ca0dc3e4a5d7cb79878bb2/mempool/clist_mempool.go#L577
    //-- __subaction__: this action is not part of the next-state relation
    action Update(node: NodeId, h: Height, txs: Set[Tx], execTxResults: Tx -> bool): bool = all {
        require(h > node.MempoolHeight()),

        // Update mempool's height.
        mempoolHeight' = mempoolHeight.put(node, h),

        // Remove all txs from the mempool.
        node.removeFromMempool(txs),

        // Update cache for all transactions.
        // - Add valid committed txs to the cache (in case they are missing).
        //      It may happen that tx has never been seen by this node before,
        //      so we add it to the cache just for this case.
        // - Remove invalid txs, if keepInvalidTxsInCache is false.
        //      If we know that tx is invalid, we need to remove it from the cache.
        val validTxs = txs.filter(tx => execTxResults.get(tx))
        val invalidTxs = txs.filter(tx => not(execTxResults.get(tx)) and not(Configs.get(node).keepInvalidTxsInCache)) 
        cache' = cache.mapPut(node, (ts) => ts.union(validTxs).exclude(invalidTxs)),

        // Either recheck non-committed txs to see if they became invalid
        // or just notify there're some txs left.
        val txsStillInMempool = node.mempoolTxs().exclude(txs)
        if (txsStillInMempool.nonEmpty())
            node.ABCI::sendRequestRecheckTxs(txsStillInMempool, h)
        else ABCI::unchanged,

        node.setError(noError),
        History::unchanged,
        Network::unchanged,
    }

    // Callback function to process a CheckTx response with type "Recheck".
    // [CListMempool.resCbRecheck]: https://github.com/CometBFT/cometbft/blob/6498d67efdf0a539e3ca0dc3e4a5d7cb79878bb2/mempool/clist_mempool.go#L432
    action ReceiveRecheckTxResponse(node: NodeId): bool = all {
        node.setStep("ReceiveRecheckTxResponse", Map()),
        require(node.ABCI::recheckTxRequests().nonEmpty()),
        nondet request = oneOf(node.ABCI::recheckTxRequests())
        val response = node.ABCI::responseFor(request)
        all {
            node.ABCI::removeRequest(request),
            if (response.err != noError) all {
                // Tx became invalidated due to newly committed block.
                node.removeFromMempool(Set(request.tx)),
                node.removeFromCache(request.tx),
            } else all {
                mempool' = mempool,
                cache' = cache,
            }
        },
        node.setError(noError),
        mempoolHeight' = mempoolHeight,
        History::unchanged,
        Network::unchanged,
        Chain::unchanged,
    }
    //--------------------------------------------------------------------------
    // RPC initiated actions
    //--------------------------------------------------------------------------
    
    // Receive a given transaction from a client via RPC.
    // [Environment.BroadcastTxAsync]: https://github.com/CometBFT/cometbft/blob/111d252d75a4839341ff461d4e0cf152ca2cc13d/rpc/core/mempool.go#L22
    //-- __subaction__: this action is not part of the next-state relation
    action CheckTxRPC(node, tx) = all {
        node.setStep("ReceiveTxViaRPC", Map("tx" -> tx)),
        node.CheckTx(tx, noNode),
        History::recordSubmittedTx(node, tx),
        Network::unchanged,
        Chain::unchanged,
    }

    /* Receive some transaction from a client via RPC. */
    action ReceiveTxViaRPC(node) = 
        nondet tx = oneOf(Txs)
        all {
            // This guard is for not repeating the same step on the same transaction as the last time.
            require(_step.name == "ReceiveTxViaRPC" and _step.node == node implies _step.args.get("tx") != tx),
            node.CheckTxRPC(tx),
        }

    /* Receive some transaction from a client via RPC: only a transaction that
     * was not sent before. */
    action ReceiveNonRepeatedTxViaRPC(node) =
        val availableTxs = Txs.exclude(History::txsReceivedViaRPC.mapValues().flatten())
        all {
            require(availableTxs.nonEmpty()),
            nondet tx = oneOf(Txs.exclude(History::txsReceivedViaRPC.mapValues().flatten()))
            node.CheckTxRPC(tx)
        }

    //--------------------------------------------------------------------------
    // Consensus actions
    //--------------------------------------------------------------------------
    // Consensus reactor's BlockExecutor updates the mempool with the latest
    // block it created and rechecks outstanding txs.

    // Note that BlockExecutor flushes the mempool's ABCI connection before
    // committing the block and updating the mempool, to make sure all requests are
    // processed before advancing to the next height.

    action Flush(node) = all {
        require(node.ABCI::checkTxRequests().isEmpty()),
        require(node.ABCI::recheckTxRequests().isEmpty()),
    }


    // This node is not the proposer: take the block from the chain.
    action BlockExecutor_MempoolUpdate_nonProposer(node) = all {
        require(not(Chain::chainIsEmpty)),
        require(node.MempoolHeight() < Chain::latestHeight),
        node.ABCI::FlushConnection(),
        val nextBlockHeight = node.MempoolHeight() + 1
        val txs: Set[Tx] = Chain::getBlockAt(nextBlockHeight)
        all {
            node.setStep("UpdateAsNonProposer", txs.mapBy(tx => tx)),
            // All txs are valid because they are committed in the chain.
            node.Update(nextBlockHeight, txs, txs.mapBy(_ => true)),
            Chain::unchanged,
        },
    }

    //-- __subaction__: this action is not part of the next-state relation
    action BlockExecutor_MempoolUpdate_proposer_(node, txs, nextBlockHeight) = all {
        node.setStep("UpdateAsProposer", txs.mapBy(tx => tx)),
        node.ABCI::FlushConnection(),
        val execTxResults: Tx -> bool = txs.mapBy(tx => tx.isValidAt(nextBlockHeight))
        all {
            node.Update(nextBlockHeight, txs, execTxResults),
            Chain::addNewBlock(txs.filter(tx => execTxResults.get(tx))),
        }
    }

    // [ReapMaxBytesMaxGas]: https://github.com/cometbft/cometbft/blob/111d252d75a4839341ff461d4e0cf152ca2cc13d/mempool/clist_mempool.go#L519
    def reapTxs(node) = 
        // Note that block may be empty.
        nondet txs = oneOf(node.mempoolTxs().powerset())
        txs

    // This node is the proposer: create the next block with txs from the mempool.
    action BlockExecutor_MempoolUpdate_proposer(node) = all {
        require(node.mempoolTxs().nonEmpty()),
        require(node.MempoolHeight() == Chain::latestHeight),
        val nextBlockHeight = node.MempoolHeight() + 1
        val txs = node.reapTxs()
        BlockExecutor_MempoolUpdate_proposer_(node, txs, nextBlockHeight)
    }

    //--------------------------------------------------------------------------
    // Mempool reactor (P2P) actions
    //--------------------------------------------------------------------------
    /* Receive a Txs message from a peer, and calls CheckTx on each Tx. */
    // [Reactor.Receive]: https://github.com/CometBFT/cometbft/blob/111d252d75a4839341ff461d4e0cf152ca2cc13d/mempool/reactor.go#L93
    action P2P_ReceiveTx(node) = all {
        node.setStep("P2P_ReceiveTx", Map()),
        require(node.Network::incomingMsgs().nonEmpty()),
        nondet msg = oneOf(node.Network::incomingMsgs())
        all {
            node.CheckTx(msg.tx, msg.senderId),
            node.Network::receiveMsg(msg),
            History::unchanged,
            Chain::unchanged,
        }
    }

    /* The reactor loops through its mempool and sends the tx one by one to
     * each of its peers. */
    //-- __subaction__: this action is not part of the next-state relation
    action P2P_SendTx_(node: NodeId, peer: NodeId): bool = all {
        node.setStep("P2P_SendTx", Map("peer" -> peer)),
        require(not(node.Mempool().isEmpty())),
        nondet tx = oneOf(node.mempoolTxs())
        val msg = { tag: "Txs", senderId: node, tx: tx }
        all {
            // If the msg was not already sent to this peer.
            require(peer.Network::incomingMsgs().forall(m => m != msg)),
            // If the peer is not a tx's sender.
            require(peer.notIn(node.sendersFor(tx))),
            Network::sendTo(msg, peer),
            node.setError(noError),
            node.History::recordGossippedTx(tx),
            mempool' = mempool,
            cache' = cache,
            mempoolHeight' = mempoolHeight,
            ABCI::unchanged,
            Chain::unchanged,
        }
    }

    // [Reactor.broadcastTxRoutine]: https://github.com/CometBFT/cometbft/blob/5049f2cc6cf519554d6cd90bcca0abe39ce4c9df/mempool/reactor.go#L132
    action P2P_SendTx(node: NodeId): bool =
        nondet peer = oneOf(Network::Peers.get(node))
        node.P2P_SendTx_(peer)

    // The reactor sends at once a tx in the mempool to all its peers.
    // Action `P2P_SendTx` introduces a lot of additional, unnecessary steps to the trace,
    // one for each peer. It doesn't make any real difference to put the message in
    // all the peers' inboxes (Network::msgs) at once, because each peer may
    // process non-deterministically the received message when they need to.
    // [Reactor.broadcastTxRoutine]: https://github.com/CometBFT/cometbft/blob/5049f2cc6cf519554d6cd90bcca0abe39ce4c9df/mempool/reactor.go#L132
    action P2P_BroadcastTx(node: NodeId): bool = all {
        node.setStep("P2P_BroadcastTx", Map()),
        require(not(node.Mempool().isEmpty())),
        nondet tx = oneOf(node.mempoolTxs())
        val msg = { tag: "Txs", senderId: node, tx: tx }
        val peers = Network::Peers.get(node).exclude(node.sendersFor(tx))
        all {
            // If the msg was not already sent to all the peers.
            require(peers.forall(peer => peer.Network::incomingMsgs().forall(m => m != msg))),
            Network::sendToMany(msg, peers),
            node.setError(noError),
            node.History::recordGossippedTx(tx),
            mempool' = mempool,
            cache' = cache,
            mempoolHeight' = mempoolHeight,
            ABCI::unchanged,
            Chain::unchanged,
        }
    }

    //--------------------------------------------------------------------------
    /* All possible actions on a node. */
    action NodeNext =
        nondet node = oneOf(NodeIds)
        any {
            // Receive a transaction from a client via RPC endpoints broadcast_tx_*
            node.ReceiveTxViaRPC(),
            // Receive a transaction from a client via RPC endpoints broadcast_tx_*, only transactions not sent before.
            // node.ReceiveNonRepeatedTxViaRPC(),

            // Receive a (New) CheckTx response from the application
            node.ReceiveCheckTxResponse(),

            // Consensus reactor's BlockExecutor updates the mempool and rechecks txs.
            // There are two cases:
            // - The node is not the proposer: it computes the block from consensus votes 
            //   (here it takes the block from the chain).
            node.BlockExecutor_MempoolUpdate_nonProposer(),
            // - The node is the proposer: it creates a block from the mempool.
            node.BlockExecutor_MempoolUpdate_proposer(),

            // Receive a (Recheck) CheckTx response from the application
            node.ReceiveRecheckTxResponse(),

            // Receive a Txs message from a peer
            node.P2P_ReceiveTx(),

            // Send a transaction in the mempool:
            // - to a peer
            // node.P2P_SendTx(),
            // - to all its peers
            node.P2P_BroadcastTx(),
        }

    /* There may be action in other nodes too. */
    /* In case we want that other nodes other than the ones defined here generate blocks. */
    // action ChainNext = 
    //     val notCommittedTxs = Txs.exclude(Chain::allTxsInChain)
    //     all {
    //         require(notCommittedTxs.nonEmpty()),
    //         nondet txs = oneOf(notCommittedTxs.powerset())
    //         all {
    //             require(txs.forall(tx => isValidAt(tx, Chain::latestHeight + 1))),
    //             Chain::addNewBlock(txs),
    //             setStep(noNode, "ChainNext", txs.mapBy(x => x)),
    //             setError(noNode, noError),
    //             mempool' = mempool, 
    //             mempoolHeight' = mempoolHeight, 
    //             cache' = cache, 
    //             History::unchanged,
    //             ABCI::unchanged,
    //             Network::unchanged,
    //         }
    //     }
    
    // action step = any { NodeNext, ChainNext }
    action step = NodeNext

    //--------------------------------------------------------------------------
    //--------------------------------------------------------------------------
    // NOTE: tried to move this section to its own module but for some reason
    // quint complains.
    //--------------------------------------------------------------------------
    // Test properties that define scenarios for extracting traces
    //--------------------------------------------------------------------------

    // a node whose mempool is not empty
    val mempoolNonEmpty = 
        nondet node = oneOf(NodeIds)
        node.mempoolTxs().nonEmpty()
    val notMempoolNonEmpty = not(mempoolNonEmpty)

    // a node whose cache has tx that is not in the mempool
    val InCacheNotInMempool = 
        nondet node = oneOf(NodeIds)
        all {
            node.Cache().nonEmpty(),
            nondet tx = oneOf(node.Cache())
            tx.notIn(node.mempoolTxs())
        }
    val notInCacheNotInMempool = not(InCacheNotInMempool)

    // a node whose cache has tx that is also in the mempool
    val InCacheInMempool = 
        nondet node = oneOf(NodeIds)
        all {
            node.Cache().nonEmpty(),
            nondet tx = oneOf(node.Cache())
            tx.in(node.mempoolTxs())
        }
    val notInCacheInMempool = not(InCacheInMempool)

    // two different nodes have the same tx in mempool
    val SameTx = 
        nondet tx = oneOf(Txs)
        nondet n1 = oneOf(NodeIds)
        nondet n2 = oneOf(NodeIds)
        all {
            n1 != n2,
            tx.in(n1.mempoolTxs()),
            tx.in(n2.mempoolTxs()),
        }
    val notSameTx = not(SameTx)

    //--------------------------------------------------------------------------

    // a state in which all available transactions (Txs) are included in the chain
    val FullChain = 
        Chain::allTxsInChain == Txs
    val notFullChain = not(FullChain)

    // a state in which all nodes are synced to height 2
    val AllNodesSynced =
        NodeIds.forall(node => node.MempoolHeight() == 2)
    val notAllNodesSynced = not(AllNodesSynced)
}
