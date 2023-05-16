// -*- mode: Bluespec; -*-
// A mempool is a replicated set of transactions which is used as an input by a ledger.
// Below, we follow the specification given here:
// https://github.com/cometbft/knowledge-base/blob/main/protocols/mempool-overview.md

module ABCI {

    import System.* from "System"
    import Ledger.* from "Ledger"

    // a transaction is committed at most once
    pure def isValid(l: LedgerState, p: Process, t: Tx): bool = {
      not(isCommittedFor(l, p, t))
    }

}

module Mempool {

    import Spells.* from "Spells"
    import System.* from "System"
    import Ledger.* from "Ledger"
    import ABCI.*

    type MempoolState = {
      pool: Process -> Set[Tx],
    }

    pure def txsAvailable(state: MempoolState, p: Process): Set[Tx] = {
      state.pool.get(p)
    }

    pure def poolSize(state: MempoolState, p: Process): int = {
      state.pool.get(p).size()
    }

    pure def reap(state: MempoolState, p: Process, max: int): Set[Tx] = {
      setSubsetOfAtMost(state.pool.get(p), max)
    }

    pure def poolOf(state: MempoolState, p: Process): Set[Tx] = {
      state.pool.get(p)
    }

    pure def newMemPool(P: Set[Process]): MempoolState = {
      pool: P.mapBy(p => Set()),
    }

    pure def add(state: MempoolState, p: Process, t: Tx): MempoolState = { // aka. checkTx
      state.with("pool", state.pool.set(p, state.pool.get(p).union(Set(t))))
    }

    pure def clear(state: MempoolState, p: Process): MempoolState = {
      state.with("pool", state.pool.set(p, Set()))
    }

    pure def remove(state: MempoolState, p: Process, t: Tx): MempoolState = {
      state.with("pool", state.pool.set(p, state.pool.get(p).exclude(Set(t))))
    }

    // remove committed and invalid txs from the mempool
    pure def update(state: MempoolState, p: Process, l: LedgerState, ctxs: Set[Tx]): MempoolState = {
          state.with("pool", state.pool.set(p, state.pool.get(p).exclude(ctxs).filter(t => isValid(l, p, t))))
    }

}

module MempoolTests {

    import Spells.* from "Spells"
    import System.* from "System"
    import Ledger.* from "Ledger"
    import Mempool.*
    import ABCI.*

    pure val PROCESSES=Set("alice", "bob")
    pure val TXS=Set("T0", "T1", "T2")

    var ledger: LedgerState
    var mempool: MempoolState
    var hmempool: Process -> Set[Tx] // history variable 

    val print = {ledger: ledger, mempool: mempool, hmempool: hmempool}

    action init : bool = all {
      val nledger = newLedger(PROCESSES)
      all {
        ledger' = nledger,
        mempool' = newMemPool(PROCESSES),
	hmempool' = PROCESSES.mapBy(p => Set())
      }
    }

    action doClient(p: Process, t: Tx): bool = all {
      all {
        require(isValid(ledger, p, t)),
	ledger' = ledger,
        mempool' = add(mempool, p, t),
	hmempool' = hmempool
      }
    }

    action doSubmit(p: Process): bool = all {
      val txs = reap(mempool, p, 1)
      all {
        require(txs.forall(t => isValid(ledger, p, t)) and maySubmit(ledger, p, txs)),
	ledger' = submit(ledger, p, txs),
      	mempool' = mempool,
	hmempool' = hmempool.set(p, hmempool.get(p).union(txs))
      }
    }

    action doCommitThenUpdate(p: Process): bool = all {
      val nledger = if (mayCommit(ledger, p)) commit(ledger, p) else ledger
      val nmempool = if (heightOf(ledger, p)!=heightOf(nledger, p)) update(mempool, p, nledger, lastEntry(nledger, p)) else mempool
      all {
        require(mayCommit(ledger, p)),
	ledger' = nledger,
        mempool' = nmempool,
	hmempool' = hmempool
      }
    }

    action step: bool = {
      nondet p = oneOf(PROCESSES)
      nondet t = oneOf(TXS)
      any {
        doClient(p,t),
        doSubmit(p),
	doCommitThenUpdate(p)
      }	
    }


    // INVARIANTS
    
    // INV1. the mempool is used as an input for the ledger
    def inv1() = {
      PROCESSES.forall(p => getSubmittedFor(ledger,p).subseteq(hmempool.get(p)))
    }

    // INV2. committed transactions are not in the mempool
    def inv2() = {
      PROCESSES.forall(p => 0.to(heightOf(ledger, p)-1).forall(i =>  entry(ledger, p, i).intersect(poolOf(mempool, p)).size()==0))
    }

    // INV3. every transaction in the mempool is valid
    def inv3() = {
      PROCESSES.forall(p => poolOf(mempool, p).forall(t => isValid(ledger, p, t)))
    }
    
    // INV4. every transaction that appears in the mempool is eventually committed or forever invalid
    // cannot be checked ftm. with Quint
    // instead we consider the (weaker) invariant below
    // INV4b. every transaction in hmempool is always committed or if valid then still in the mempool
    def inv4() = {
      PROCESSES.forall(p => hmempool.get(p).forall(tx => isCommittedFor(ledger, p, tx) or not(isValid(ledger, p, tx)) or poolOf(mempool, p).contains(tx)))
    }

    def allInv = {inv1 and inv2 and inv3 and inv4}
    

    run moveHeightOnce = {
      nondet p = oneOf(PROCESSES)
      nondet t = oneOf(TXS)
      init
      .then(doClient(p,t))
      .then(doSubmit(p))
      .then(doCommitThenUpdate(p))
    }

}
