module gmcast0 {
    type ProcId = int

    //XXX Quint: Ideally these should be consts, but because it would have to be instantiated on every import, there would be duplication.
    //All processes in the system

    pure val MsgType = Set("S0", "S1", "S2")
    pure val ProcIds = Set(1,2,3,4,5)
    type Message = {
        tag: Set[string], //Shoud be MsgType
        src: ProcId,
        dst: ProcId
    }

    //Nodes keep the following state
    type Node = {
        k: ProcId => int,
        pending: ProcId => Set[(Message)],
        delivering: ProcId => Set[(Message)],
        delivered: ProcId => Set[(Message)],
        previous: ProcId => Set[(Message)]
    }

    type Network = {
        msgsSent: Set[(Message)],         //Unicast sent messages.
        msgsRcvd: Set[(Message)],         //Unicast received messages
    }

    
    var nodeState: ProcId -> NodeState
    var networkState: Network

    action init: bool = all {
        nodeState' = {
            ProcIds.mapBy(p => 0)


            
        },
        networkState' = {msgsSent: Set(), msgsRcvd: Set()}
    }
}