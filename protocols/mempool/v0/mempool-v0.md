# Mempool V0 implementation (WIP)

![Mempool](./mempool-v0.svg)

### Add a transaction to the mempool

1. The mempool receives transactions either from two sources.
    
    - A client sends one transaction via broadcast_tx_* RPC endpoints. 
        [`rpc.core.mempool.broadcast_tx_*`]
    
    - A peer sends a list of transactions via the P2P layer. Each transaction is checked whether it's valid.
        [`mempool.Reactor.Receive`]

2. Process incoming transaction to check its validity. 
    [`mempool.CListMempool.CheckTx`]
    
    2a. If the transaction is not in the cache, add it; otherwise ignore it.
    
    2b. If the transaction is in the mempool, update the list of senders.
    
    2c. Send a `CheckTx` ABCI request to app.

3. On `CheckTx` response. 
    [`mempool.CListMempool.resCbFirstTime`]
    
    3a. If tx is valid, add tx to mempool and record its sender.
    
    3b. If tx is valid but mempool is full, or if tx is invalid, remove it from cache.

### Update transactions in the mempool

4. Flush to ensure all async requests have completed in the ABCI app before Commit.
    [`mempool.CListMempool.FlushAppConn`]

5. Consensus reactor reads mempool to create a proposal block 
    [`mempool.CListMempool.ReapMaxBytesMaxGas`]

6. BlockExecutor updates the mempool after finalizing a block (list of txs).
    [`mempool.CListMempool.Update`]

7. Update each transaction in the block. 
    [`mempool.CListMempool.Update`]

    7a. If a transaction is valid, put it in the cache; otherwise, remove it.

    7b. Remove from mempool each tx in the block.

8. Send one `CheckTx` ABCI request to app for every transaction in the block.
    [`mempool.CListMempool.recheckTxs`]

9. On `CheckTx` response, if the transaction is invalid.
    [`mempool.CListMempool.resCbRecheck`]
    
    9a. Remove it from mempool.
    
    9b. Remove it from cache.

### Propagate transactions

10. Make sure the peer is up to date and get its height.
    [`peer.Get(types.PeerStateKey).(PeerState)`]

11. Send all transactions in the mempool to the peer, one by one.
    [`mempool.Reactor.AddPeer/broadcastTxRoutine`]

### Other RPC endpoints

12. Get a list of unconfirmed transactions in the mempool, with a maximum number of entries.
    [`rpc.core.mempool.unconfirmed_txs`]
