// -*- mode: Bluespec; -*-

module consensus {

  // a process name is just a string in our specification
  type Proc_t = str
  // a value is also a string
  type Value_t = str
  // a state is also a string
  type Step_t = str
  // a round is an integer
  type Round_t = int
  // a state is also a string
  type Timeout_t = str

// the type of propose messages
  type ProposeMsg_t = {
    src: Proc_t,
    round: Round_t,
    proposal: Value_t,
    validRound: Round_t
  }

  // the type of Prevote and Precommit messages
  type VoteMsg_t = {
    src: Proc_t,
    round: Round_t,
    step: Step_t,  // "prevote" or "precommit"
    id: Value_t,
  }

type ConsensusState = {
    p: Proc_t,
    height : int,
    round: Round_t,
    step: Step_t,
    lockedRound: Round_t,
    lockedValue: Value_t,
    validRound: Round_t,
    validValue: Value_t
    //continue
}  

type Event = {
    name : str,
    height : int,
    round: Round_t,
    value: Value_t,
    vr: Round_t
}    

// what is a good way to encode optionals? I do with default values
type Result = {
    proposal: ProposeMsg_t,
    voteMessage: VoteMsg_t,
    timeout: Timeout_t,
    decided: Value_t,
    skipRound: Round_t
}


val noProp : ProposeMsg_t = {src: "", round: -1, proposal: "", validRound: -1}
val noVote : VoteMsg_t = {src: "", round: -1, step: "", id: ""}
val noTimeout : Timeout_t = ""
val noDecided = ""
val noSkipRound : Round_t = -1
val defaultResult : Result = { 
                proposal: noProp, 
                voteMessage: noVote, 
                timeout: noTimeout, 
                decided: noDecided,
                skipRound: noSkipRound}

// How are we actually doing this in the state machine approach
pure def Proposer (height: int, round: Round_t) : Proc_t = "Josef"

// line 11.14
pure def startRoundProposer (state: ConsensusState, ev: Event) : (ConsensusState, Result) = {
    val newstate = state.with("round", ev.round).with("step", "propose")
    val proposal =  if (state.validValue != "nil") state.validValue
                    else ev.value
    val result = defaultResult.with("proposal", {   src: state.p, 
                                                        round: ev.round, 
                                                        proposal: proposal,
                                                        validRound: state.validRound})
    (newstate, result)
}

// line 11.20
pure def startRoundNonProposer (state: ConsensusState, ev: Event) : (ConsensusState, Result) = {
    val newstate = state.with("round", ev.round).with("step", "propose")
    val result = defaultResult.with("timeout", "timeoutPropose") // do we need the roundnumber here?
        (newstate, result)
}

pure def line22 (state: ConsensusState, ev: Event) : (ConsensusState, Result) = {
    if (state.step == "propose") {
        val newstate = state.with("step", "prevote")
        if (state.lockedRound == -1 or state.lockedValue == ev.value)
            val result = defaultResult.with("voteMessage", { src: state.p,
                                                            round: state.round,
                                                            step: "prevote",  // "prevote" or "precommit"
                                                            id: ev.value})
            (newstate, result)
        else
            val result = defaultResult.with("voteMessage", { src: state.p,
                                                            round: state.round,
                                                            step: "prevote",  // "prevote" or "precommit"
                                                            id: "nil"})
            (newstate, result)
    }
    else
        (state, defaultResult)
}

pure def consensus (state: ConsensusState, ev: Event) : (ConsensusState, Result) = {
    if (ev.name == "StartRoundAsProposer") 
        startRoundProposer(state, ev)
    else if (ev.name == "Proposal")
        line22(state, ev)
    else
        (state, defaultResult)
}

/* ****************************************************************************
 * Global state
 * ************************************************************************* */

var system : Proc_t -> ConsensusState
var _Result : Result


pure def initialProcess (name: Proc_t) : ConsensusState = {
    { p: name, height : 1, round: 0, step: "", lockedRound: -1, lockedValue: "nil", validRound: -1, validValue: "nil"}
}

action init = all {
    system' = Map ("Josef" -> initialProcess("Josef")),
    _Result' = defaultResult
}

// just to write a test.
action FireEvent(eventName: str, proc: Proc_t, h: int, r: Round_t, value: Value_t) : bool = all {
    val res = consensus(system.get(proc),  {name : eventName,
                                            height : h,
                                            round: r,
                                            value: value,
                                            vr: -1} )
    all {
        system' = system.put(proc, res._1),
        _Result' = res._2
    }
}



run FirstTest = {
    init
    .then(FireEvent("StartRound", "Josef", 1, 0, "testbal"))
    .then(all{
        assert(_Result.timeout == noTimeout),
        assert(_Result.proposal.src == "Josef"),
        system' = system,
        _Result' = _Result,
        })
    .then(FireEvent(("Proposal", "Josef", 1, 0, "testbal")))
    .then(all{
        assert(true), //TODO
        system' = system,
        _Result' = _Result,       
    })
}   

}