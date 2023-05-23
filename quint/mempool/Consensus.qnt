// -*- mode: Bluespec; -*-
// The common consensus abstraction where processes agree on some blocks (i.e., set of transactions).

module Consensus{

    import Spells.* from "Spells"
    import System.* from "System"

    type ConsensusState = {
      proposed: Process -> Set[Tx],
      decided: Process -> Set[Tx]
    }

    pure def newConsensus(P: Set[Process]): ConsensusState = {
      proposed: P.mapBy(p => Set()),
      decided: P.mapBy(p => Set())
    }

    pure def processes(state: ConsensusState): Set[Process] = {
      state.proposed.keys()
    }

    pure def hasProposed(state: ConsensusState, p: Process): bool = {
      state.proposed.get(p).size() > 0
    }
    
    pure def hasDecided(state: ConsensusState, p: Process): bool = {
      state.decided.get(p).size() > 0
    }

    pure def isProposed(state: ConsensusState, t: Tx): bool = {
      state.proposed.keys().filter(p => state.proposed.get(p).contains(t)).size() > 0
    }

    pure def isDecided(state: ConsensusState, t: Tx): bool = {
      state.decided.keys().filter(p => state.decided.get(p).contains(t)).size() > 0
    }

    pure def hasDecision(state: ConsensusState): bool = {
      state.decided.keys().filter(p => state.decided.get(p).size()>0).size() > 0
    }

    pure def decisionOf(state: ConsensusState, p: Process): Set[Tx] = {
      state.decided.get(p)
    }

    pure def proposalOf(state: ConsensusState, p: Process): Set[Tx] = {
      state.proposed.get(p)
    }

    pure def getProposed(state: ConsensusState): Set[Tx] = {
      flatten(mapValues(state.proposed))
    }

    pure def getDecided(state: ConsensusState): Set[Tx] = {
      flatten(mapValues(state.decided))
    }

    pure def mayPropose(state: ConsensusState, p: Process, txs: Set[Tx]): bool = {
      state.processes().contains(p) and not(state.hasProposed(p)) and txs.size() != 0
    }

    pure def mayDecide(state: ConsensusState, p: Process): bool = {
      processes(state).contains(p) and size(state.getProposed()) > 0 and not(state.hasDecided(p))
    }

    pure def propose(state: ConsensusState, p: Process, txs: Set[Tx]): ConsensusState = {
      val newProposed = state.proposed.set(p, txs)
      {proposed: newProposed, ...state}
    }

    // decide any proposed values
    pure def decide(state: ConsensusState, p: Process): ConsensusState = {
      val proposal = state.proposed.get(setChooseSome(state.proposed.keys().filter(x => state.proposed.get(x).size()>0)))
      val decisions = state.decided.keys().filter(x => state.decided.get(x).size()>0)
      val decision = if (decisions.size()>0) {state.decided.get(setChooseSome(decisions))}  else {proposal}
      val newDecided = state.decided.set(p, decision)
      {decided: newDecided, ...state}
    }

    // INVARIANTS
    
    // Irrevocability: a process decides at most once
    // This requires applying Consensus:mayDecide before Consensus:decide.
    
    // Validity: a process decides only proposed values
    pure def consensusValidityInv(state: ConsensusState): bool = {
        state.processes().forall(
        p => or {
	       not(state.hasDecided(p)),
	       state.proposed.keys().filter(q => state.proposed.get(q) == state.decided.get(p)).size()>0
	     } 
      )
    }
    
    // Agreement: no two processes decide different values
    pure def consensusAgreementInv(state: ConsensusState): bool = {
      size(mapValues(state.decided).filter(x => x.size()>0)) <= 1
    }

}

module ConsensusTests {

    import Spells.* from "Spells"
    import System.* from "System"
    import Consensus.*

    pure val PROCESSES=Set("alice", "bob", "charlie")
    pure val TXS=Set("T0", "T1", "T2", "T3")

    var st: ConsensusState

    val invariant: bool = {
      consensusValidityInv(st) and consensusAgreementInv(st)
    }

    action init = all {
        st' = newConsensus(PROCESSES)
    }

    action doPropose = all {
      nondet p = oneOf(PROCESSES)
      nondet txs = oneOf(TXS.powerset())
      all {
        require(st.mayPropose(p, txs)),
        st' = st.propose(p, txs)
      }
    }

    action doDecide = all {
      nondet p = oneOf(PROCESSES)
      all {
        require(st.mayDecide(p)),
        st' = st.decide(p)
      }
    }

    action step = any {
      doPropose,
      doDecide
    }

    run proposeTwiceError = {
      nondet p = oneOf(PROCESSES)
      nondet txs = oneOf(TXS.powerset())
      init
      .then(
        all {
    	  st.propose(p, txs).mayPropose(p, txs),
    	  st' = st
    	})
      .fail()
    }

    run decideNonProposedError = {
      init
      .then(
        all {
          st.mayDecide(oneOf(PROCESSES)),
          st' = st
        })
      .fail()
    }

    run decideProposedSuccess = {
      nondet p = oneOf(PROCESSES)
      nondet q = oneOf(PROCESSES)
      nondet txs0 = oneOf(TXS.powerset())
      nondet txs1 = oneOf(TXS.powerset())
      init
      .then(st' = st.propose(p, txs0).propose(q, txs1))
      .then(
        all {
    	  st' = st,
    	  st.mayDecide(p) and st.decide(p).hasDecided(p)
        })
    }

}
