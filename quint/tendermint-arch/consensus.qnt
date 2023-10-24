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
    validRound: Round_t,
    //continue
}  

type Event = {
    name : str,
    height : int,
    round: Round_t,
    value: Value_t,
    vr: Round_t
}    

// what is a good way to encode optionals.
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

pure def Proposer (height: int, round: Round_t) : Proc_t = "Josef"

pure def line11 (state: ConsensusState, ev: Event) : (ConsensusState, Result) = {
    val newstate = state.with("round", ev.round).with("step", "propose")
    if (Proposer(ev.height, ev.round) == state.p)
        val result = defaultResult.with("proposal", {   src: state.p, 
                                                        round: ev.round, 
                                                        proposal: ev.value,
                                                        validRound: state.validRound})
        (newstate, result)
    else
        val result = defaultResult.with("timeout", "timeoutPropose") // do we need the roundnumber here?
        (newstate, result)
}

pure def line22 (state: ConsensusState, ev: Event) : (ConsensusState, Result) = {
    (state, defaultResult)
}

pure def consensus (state: ConsensusState, ev: Event) : (ConsensusState, Result) = {
    if (ev.name == "StartRound") 
        line11(state, ev)
    else if (ev.name == "Proposal")
        line22(state, ev)
    else
        (state, defaultResult)
}

    
}