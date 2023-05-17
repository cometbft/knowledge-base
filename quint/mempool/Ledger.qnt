// -*- mode: Bluespec; -*-
// A Ledger is a replicated log of blocks (i.e., set of transactions).
// The specification below considers that
// - replication is made with consensus (SMR)
// - idempotence is not granted (that is, two log entries might have transactions in common).

module Ledger{

    import Spells.* from "Spells"
    import System.* from "System"
    import Consensus.* from "Consensus"

    type LedgerState = {
      log: List[ConsensusState],
    }

    pure def newLedger(P: Set[Process]): LedgerState = {log: List(newConsensus(P))}

    // index of the first null entry
    pure def height(state: LedgerState): int = length(state.log.select(s => s.hasDecision()))

    pure def heightOf(state: LedgerState, p: Process): int = length(state.log.select(s => s.hasDecided(p)))

    pure def entry(state: LedgerState, p: Process, i: int): Set[Tx] = state.log[i].decisionOf(p)

    pure def lastEntry(state: LedgerState, p: Process): Set[Tx] = entry(state, p, heightOf(state, p)-1)

    pure def getSubmittedFor(state: LedgerState, p: Process): Set[Tx] = 0.to(heightOf(state, p)).fold(Set(), (s, i) => s.union(proposalOf(state.log[i],p)))

    pure def isSubmitted(state: LedgerState, t: Tx): bool = 0.to(height(state)).exists(h => isProposed(state.log[h], t))

    pure def isCommitted(state: LedgerState, t: Tx): bool = {
      if (height(state)==0) false else 0.to(height(state)-1).exists(i => isDecided(state.log[i], t))
    }

    pure def isCommittedFor(state: LedgerState, p: Process, t: Tx): bool = {
      if (heightOf(state, p)==0) false else 0.to(heightOf(state, p)-1).exists(h => isDecided(state.log[h], t))
    }

    pure def maySubmit(state: LedgerState, p: Process, txs: Set[Tx]): bool = {
      val currentConsensus = state.log[heightOf(state,p)]
      txs.size()>0 and not(currentConsensus.hasProposed(p))
    }

    pure def mayCommit(state: LedgerState, p: Process): bool = {
      val currentConsensus = state.log[heightOf(state,p)]
      currentConsensus.hasProposed(p) and not(currentConsensus.hasDecided(p))
    }

    pure def submit(state: LedgerState, p: Process, txs: Set[Tx]): LedgerState = {
      val currentConsensus = state.log[heightOf(state,p)]
      val nextLog = state.log.replaceAt(heightOf(state,p), currentConsensus.propose(p, txs))
      {log: nextLog, ...state}
    }

    pure def commit(state: LedgerState, p: Process): LedgerState = {
      val currentConsensus = state.log[heightOf(state,p)]
      val nextLog = if (heightOf(state, p) == height(state)) {
          state.log.append(newConsensus(processes(state.log[0])))
      }else{
    	  state.log
      }
      state.with("log", nextLog.replaceAt(heightOf(state,p), currentConsensus.decide(p)))
    }

    // INVARIANTS

    // Validity: every non-null entry is submitted
    pure def ledgerValidityInv(state: LedgerState): bool = {
      0.to(height(state)).forall(h => consensusValidityInv(state.log[h]))
    }
    
    // Total Order: for any two processes, entries are prefix one from another
    pure def ledgerOrdertInv(state: LedgerState): bool = {
      0.to(height(state)-1).forall(h => consensusAgreementInv(state.log[h]))
    }

}

module LedgerTests {

    import Spells.* from "Spells"
    import System.* from "System"
    import Ledger.*

    pure val PROCESSES=Set("alice", "bob", "charlie")
    pure val TXS=Set("T0", "T1", "T2", "T3")

    var st: LedgerState

    val invariant: bool = {
      ledgerValidityInv(st) and ledgerOrdertInv(st)
    }

    action init = all {
        st' = newLedger(PROCESSES)
    }

    action doSubmit = all {
      nondet p = oneOf(PROCESSES)
      nondet txs = oneOf(TXS.powerset())
      all {
        require(maySubmit(st, p, txs)),
    	st' = submit(st, p, txs)
      }
    }

    action doCommit = all {
      nondet p = oneOf(PROCESSES)
      all {
        require(mayCommit(st, p)),
	st' = commit(st, p)
      }
    }

    action step = any {
      doSubmit,
      doCommit
    }

    run submitTwiceError = {
      nondet p = oneOf(PROCESSES)
      nondet txs = oneOf(TXS.powerset())
      init
      .then(
        all {
	  maySubmit(submit(st, p, txs), p, txs),
	  st'=st
	}
      )
      .fail()
    }

    run commitNonSubmittedError = {
      nondet p = oneOf(PROCESSES)
      init
      .then(
        all {
    	  mayCommit(st, p),
	  st'=st
	}
      )
      .fail()
    }

    run commitSubmittedSuccess = {
      nondet p = oneOf(PROCESSES)
      nondet q = oneOf(PROCESSES)
      nondet txs0 = oneOf(TXS.powerset())
      nondet txs1 = oneOf(TXS.powerset())
      init
      .then(st'=submit(submit(st, p, txs0), q, txs1))
      .then(
        all {
	  mayCommit(st, p) and heightOf(commit(st, p), p)==1,
	  st'=st
	}
      )
    }

}
