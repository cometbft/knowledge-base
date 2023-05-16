# Mempool V0 implementation (WIP)

![Mempool](./mempool-v0.svg)

### Add a transaction to the mempool

1. The mempool receives transactions either from two sources. Each transaction is checked individually with `CheckTx`.
    
    - A client sends one transaction via broadcast_tx_* RPC endpoints. 
        [`rpc.core.mempool.broadcast_tx_*`]
        <!-- [spec:CheckTxRPC] -->
    
    - A peer sends a list of transactions via the P2P layer.
        [`mempool.Reactor.Receive`]
        <!-- [spec:P2P_ReceiveTxs] -->

2. Process incoming transaction to check its validity. 
    [`mempool.CListMempool.CheckTx`]
    <!-- [spec:CheckTxRPC_] -->
    
    2a. If the transaction is not in the cache, add it; otherwise ignore it.
    
    2b. If the transaction is in the mempool, update the list of senders.
    
    2c. Send a `CheckTx` ABCI request to app.

3. On `CheckTx` response. 
    [`mempool.CListMempool.resCbFirstTime`]
    <!-- [spec:ReceiveCheckTxResponse] -->
    
    3a. If the transaction is valid, add it to mempool and record its sender.
    
    3b. If the transaction is valid but the mempool is full, or if the the transaction is invalid, then remove it from cache.

    3c. Notify Consensus that there is one transaction available.
        [`mempool.CListMempool.notifyTxsAvailable`]

### Query transactions in the mempool

4. Consensus reactor reads mempool to create a proposal block.
    [`state.BlockExecutor.CreateProposalBlock`]

5. Get a list of unconfirmed transactions in the mempool, with a maximum number of entries.
    [`rpc.core.mempool.unconfirmed_txs`]

### Update transactions in the mempool

6. BlockExecutor updates the mempool after committing a block.
    [`state.BlockExecutor.Commit`]

    6a. Flush to ensure all async requests have completed in the ABCI app before commit.
        [`mempool.CListMempool.FlushAppConn`]
    
    6b. Call `Update` on each transaction in the block. 

7. Update the mempool. 
    [`mempool.CListMempool.Update`]
    <!-- [spec:Consensus_Update] -->

    7a. If a transaction is valid, put it in the cache; otherwise, remove it.

    7b. Remove from the mempool each transaction in the block.

    7c. If there are still transactions in the mempool and `config.Recheck` is
    true, then send one `CheckTx` ABCI request to the app for every transaction
    in the block.
        [`mempool.CListMempool.recheckTxs`]
    
    7d. If there are still transactions in the mempool and `config.Recheck` is
    true, then notify Consensus that there are transactions available.
        [`mempool.CListMempool.notifyTxsAvailable`]

8. On `CheckTx` response, if the transaction is invalid.
    [`mempool.CListMempool.resCbRecheck`]
    <!-- [spec:ReceiveRecheckTxResponse] -->
    
    8a. Remove it from mempool.
    
    8b. Remove it from cache.

    8c. If there are still transactions in the mempool, notify Consensus.
        [`mempool.CListMempool.notifyTxsAvailable`]

### Propagate transactions to peers

9. Propagate each transaction in the mempool to all peers.
    [`mempool.Reactor.AddPeer/broadcastTxRoutine`]
    <!-- [spec:P2P_SendTx] -->

    9a. Loop through the mempool.

    9b. Make sure the peer is up to date; then get its height.
        [`peer.Get(types.PeerStateKey).(PeerState)`]

    9c. Send all transactions in the mempool to the peer, one by one.
