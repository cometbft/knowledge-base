module skeen {
    type ProcId = int

    //XXX Quint: Ideally this should be a const, but because it would have to be instantiated on every import, there would be duplication.
    //All processes in the system
    pure val ProcIds = Set(1,2,3,4,5)

    //Nodes are fully connected

    //Nodes keep the following state
    type NodeState = {
    }

    type NetworkState = {
        msgsSent: Set[{src:ProcId, dst:ProcId}],         //Unicast sent messages.
        msgsRcvd: Set[{src:ProcId, dst:ProcId}],         //Unicast received messages
    }

    var pid2nodeState: ProcId -> NodeState

    action init: bool = all {
        pid2nodeState' = ProcIds.mapBy(p => {
            
        }),
        networkState' = {msgsSent: Set(), msgsRcvd: Set()}
    }
}