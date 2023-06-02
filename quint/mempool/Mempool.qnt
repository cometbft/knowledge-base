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

    pure def newMemPool(P: Set[Process]): MempoolState = {
      pool: P.mapBy(p => Set()),
    }

    // 1. helpers

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

    // 2. preconditions
    // none, as we use mostly the ones of the ledger 

    // 3. transitions

    pure def add(state: MempoolState, p: Process, txs: Set[Tx]): MempoolState = {
      {pool: state.pool.set(p, state.pool.get(p).union(txs)), ...state}
    }

    pure def clear(state: MempoolState, p: Process): MempoolState = {
      {pool: state.pool.set(p, Set()), ...state}
    }

    pure def remove(state: MempoolState, p: Process, t: Tx): MempoolState = {
      {pool: state.pool.set(p, state.pool.get(p).exclude(Set(t))), ...state}
    }

    // remove committed and invalid txs from the mempool
    pure def update(state: MempoolState, p: Process, l: LedgerState): MempoolState = {
      {pool: state.pool.set(p, state.pool.get(p).exclude(l.getCommittedFor(p)).filter(t => isValid(l, p, t))), ...state}      
    }

    // 4. state machine

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
      val txs = Set(t)
      all {
        require(isValid(ledger, p, t)),
        ledger' = ledger,
        mempool' = mempool.add(p, txs),
        hmempool' = hmempool.set(p, hmempool.get(p).union(txs))
      }
    }

    action doGossipThenUpdate(p: Process, q: Process): bool = all {
      val txs = mempool.poolOf(p)
      val nmempool = mempool.add(q, txs).update(q, ledger)
      all {
        require(p != q and txs.size()>0),
        ledger' = ledger,
        mempool' = nmempool,
        hmempool' = hmempool.set(q, hmempool.get(q).union(txs))
      }
   }

    action doSubmit(p: Process): bool = all {
      val txs = reap(mempool, p, 1)
      all {
        require(txs.forall(t => ledger.isValid(p, t)) and ledger.maySubmit(p, txs)),
        ledger' = ledger.submit(p, txs),
      	mempool' = mempool,
        hmempool' = hmempool
      }
    }

    action doCommitThenUpdate(p: Process): bool = all {
      val nledger = if (ledger.mayCommit(p)) { ledger.commit(p) } else { ledger }	
      val nmempool = mempool.update(p, nledger)
      all {
        require(ledger.mayCommit(p)),
        ledger' = nledger,
        mempool' = nmempool,
        hmempool' = hmempool
      }
    }

    action step: bool = {
      nondet p = oneOf(PROCESSES)
      nondet q = oneOf(PROCESSES)
      nondet t = oneOf(TXS)
      any {
        doClient(p,t),
        doSubmit(p),
        doCommitThenUpdate(p),
        doGossipThenUpdate(p,q)
      }	
    }

    // 5. invariants
    
    // INV1. the mempool is used as an input for the ledger
    val inv1 = {
      PROCESSES.forall(p => ledger.getSubmittedFor(p).subseteq(hmempool.get(p)))
    }

    // INV2. committed transactions are not in the mempool
    val inv2 = {
      PROCESSES.forall(p => 0.to(ledger.heightOf(p)-1).forall(i =>  ledger.entry(p, i).intersect(mempool.poolOf(p)).size()==0))
    }

    // INV3. every transaction in the mempool is valid
    val inv3 = {
      PROCESSES.forall(p => mempool.poolOf(p).forall(t => ledger.isValid(p, t)))
    }
    
    // INV4. every transaction that appears in the mempool is eventually committed or forever invalid
    // temporal inv4 = {
    //   PROCESSES.forall(p => mempool.get(p).forall(tx => eventually(ledger.isCommittedFor(p, tx) or always(not(ledger.isValid(p, tx))))))
    // }
    // FIXME. cannot be verified yet

    // Instead, we use the (weaker) invariant below
    // INV4b. every transaction in hmempool is always committed or if valid then still in the mempool
     def inv4() = {
       PROCESSES.forall(p => hmempool.get(p).forall(tx => ledger.isCommittedFor(p, tx) or not(ledger.isValid(p, tx)) or mempool.poolOf(p).contains(tx)))
     }

    val allInv = and {
      inv1,
      inv2,
      inv3,
      inv4
   }

    // 6. tests

    run moveHeightOnceTest = {
      nondet p = oneOf(PROCESSES)
      nondet t = oneOf(TXS)
      init
      .then(doClient(p,t))
      .then(doSubmit(p))
      .then(doCommitThenUpdate(p))
    }

}
