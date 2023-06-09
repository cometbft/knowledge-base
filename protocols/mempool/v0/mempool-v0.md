# Mempool implementation (v0)

This document describes the implementation of the mempool in CometBFT v0.38.0-rc1.
This implementation, called v0, is simply a queue of transactions with a cache
over a basic push-based gossip protocol.

![Mempool](./mempool-v0.svg)

## Main actions from and onto the mempool
### Add a transaction to the mempool

1. The mempool receives transactions either from two sources. Each transaction
   is checked individually with [`CheckTx`][CheckTx].
    
    - A client sends one transaction via broadcast_tx_* RPC endpoints. 
        [[`rpc.core.mempool.broadcast_tx_*`][broadcast_tx_*]]
        <!-- [spec:CheckTxViaRPC] -->
    
    - A peer sends a list of transactions via the P2P layer.
        [[`mempool.Reactor.Receive`][Receive]]
        <!-- [spec:P2P_ReceiveTxs] -->

2. Process incoming transaction to check its validity. 
    [[`mempool.CListMempool.CheckTx`][CheckTx]]
    <!-- [spec:CheckTxRPC_] -->
    
    2a. If the transaction is not in the cache, add it; otherwise ignore it.
    
    2b. If the transaction is in the mempool, update the list of senders.
    
    2c. Send a `CheckTx` ABCI request to the application.

3. On `CheckTx` response.
    [[`mempool.CListMempool.resCbFirstTime`][resCbFirstTime]]
    <!-- [spec:ReceiveCheckTxResponse] -->
    
    3a. If the transaction is valid, add it to mempool and record its sender.
    
    3b. If the transaction is valid but the mempool is full, or if the the
    transaction is invalid, then remove it from cache.

    3c. Notify Consensus that there is one transaction available.
        [[`mempool.CListMempool.notifyTxsAvailable`][notifyTxsAvailable]]

### Query transactions in the mempool

4. Consensus reactor reads mempool to create a proposal block.
    [[`state.BlockExecutor.CreateProposalBlock`][CreateProposalBlock]]

5. Get a list of unconfirmed transactions in the mempool, with a maximum number
   of entries. [[`rpc.core.mempool.unconfirmed_txs`][unconfirmed_txs]]

### Update transactions in the mempool

6. BlockExecutor updates the mempool after committing a block.
    [[`state.BlockExecutor.Commit`][Commit]]

    6a. Flush to ensure all async requests have completed in the ABCI app before
        commit (see the [note below](#flush)). [[`mempool.CListMempool.FlushAppConn`][FlushAppConn]]

    6b. Call mempool's `Update` for all transactions in the block. 

7. Update the mempool. [[`mempool.CListMempool.Update`][Update]]
    <!-- [spec:Consensus_Update] -->

    7a. If a transaction is valid, put it in the cache (in case it was missing);
    otherwise, remove it from the cache, to give it a chance to be resubmitted
    later.

    7b. Remove from the mempool each transaction in the block.

    7c. If there are still transactions in the mempool and `config.Recheck` is
    true, then send one `CheckTx` ABCI request to the app for every transaction
    in the block. [[`mempool.CListMempool.recheckTxs`][recheckTxs]]
    
    7d. If there are still transactions in the mempool and `config.Recheck` is
    false, then notify Consensus that there are transactions available.
        [[`mempool.CListMempool.notifyTxsAvailable`][notifyTxsAvailable]]

8. On `CheckTx` response, if the transaction is invalid.
    [[`mempool.CListMempool.resCbRecheck`][resCbRecheck]]
    <!-- [spec:ReceiveRecheckTxResponse] -->
    
    8a. Remove it from the mempool.
    
    8b. Remove it from the cache.

    8c. If there are still transactions in the mempool, notify Consensus.
        [[`mempool.CListMempool.notifyTxsAvailable`][notifyTxsAvailable]]

### Propagate validated transactions to peers

9. Propagate each transaction in the mempool to all peers.
    [[`mempool.Reactor.broadcastTxRoutine`][broadcastTxRoutine]]
    <!-- [spec:P2P_SendTx] -->

    9a. Loop through the mempool.
        [[`mempool.CListMempool.TxsFront/TxsWaitChan`][txs-loop]]

    9b. Make sure the peer is up to date; then get its height.
        [[`peer.Get(types.PeerStateKey).(PeerState)`][Peer.Get]]
      - If we suspect that the peer is lagging behind, wait some time before
        checking again if the peer has caught up. See
        [RFC-103](https://github.com/cometbft/cometbft/blob/main/docs/rfc/rfc-103-incoming-txs-when-catching-up.md)

    9c. Send all transactions in the mempool to the peer, one by one.

## Links to code
### RPC
- [broadcast_tx_*]
- [unconfirmed_txs]

### Mempool reactor
- [Receive]
- [broadcastTxRoutine]

### CListMempool
- [CheckTx]
- [Update]
- [TxsFront/TxsWaitChan][txs-loop]
- [FlushAppConn]
- [resCbFirstTime]
- [resCbRecheck]
- [recheckTxs]
- [notifyTxsAvailable]

### Consensus
- [CreateProposalBlock]
- [Commit]
- [PeerState]

### Peer

- [Peer.Get]

[broadcast_tx_*]: https://github.com/cometbft/cometbft/blob/v0.38.0-rc1/rpc/core/mempool.go#L22-L144
[unconfirmed_txs]: https://github.com/cometbft/cometbft/blob/v0.38.0-rc1/rpc/core/mempool.go#L149

[Receive]: https://github.com/cometbft/cometbft/blob/v0.38.0-rc1/mempool/reactor.go#L93
[broadcastTxRoutine]: https://github.com/cometbft/cometbft/blob/v0.38.0-rc1/mempool/reactor.go#L132

[FlushAppConn]: https://github.com/cometbft/cometbft/blob/v0.38.0-rc1/mempool/clist_mempool.go#L178
[txs-loop]: https://github.com/cometbft/cometbft/blob/v0.38.0-rc1/mempool/clist_mempool.go#L198-L209
[CheckTx]: https://github.com/cometbft/cometbft/blob/v0.38.0-rc1/mempool/clist_mempool.go#L219
[resCbFirstTime]: https://github.com/cometbft/cometbft/blob/v0.38.0-rc1/mempool/clist_mempool.go#L377
[resCbRecheck]: https://github.com/cometbft/cometbft/blob/v0.38.0-rc1/mempool/clist_mempool.go#L439
[notifyTxsAvailable]: https://github.com/cometbft/cometbft/blob/v0.38.0-rc1/mempool/clist_mempool.go#L513
[Update]: https://github.com/cometbft/cometbft/blob/v0.38.0-rc1/mempool/clist_mempool.go#L586
[recheckTxs]: https://github.com/cometbft/cometbft/blob/v0.38.0-rc1/mempool/clist_mempool.go#L650

[CreateProposalBlock]: https://github.com/cometbft/cometbft/blob/v0.38.0-rc1/state/execution.go#L101
[Commit]: https://github.com/cometbft/cometbft/blob/v0.38.0-rc1/state/execution.go#L351
[PeerState]: https://github.com/cometbft/cometbft/blob/v0.38.0-rc1/consensus/reactor.go#L1021

[Peer.Get]: https://github.com/CometBFT/cometbft/blob/v0.38.0-rc1/p2p/peer.go#L44

## Notes

### Flush

In practice, the ABCI `Flush` method has no practical side effects on the system
(see
[tendermint/tendermint#6994](https://github.com/tendermint/tendermint/issues/6994)).
While simplifying the client interface for v0.36, it was proposed to remove it
(see comments in
[tendermint/tendermint#7607](https://github.com/tendermint/tendermint/issues/7607)).
The client interface for ABCI has [a
comment](https://github.com/CometBFT/cometbft/blob/4790ea3e46475064d5475c787427ae926c5a9e94/abci/client/client.go#L31)
saying that this method should be removed as it is not implemented.
