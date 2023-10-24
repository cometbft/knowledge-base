module gmcast0 {
    type ProcId = int

    //XXX Quint: Ideally these should be consts, but because it would have to be instantiated on every import, there would be duplication.
    //All processes in the system

    pure val MsgType = Set("S0", "S1", "S2")
    pure val ProcIds = Set(1,2,3,4,5)
    type Message = {
        tag: str, //Shoud be in MsgType
        timestamp: int, // -1 means no timestamp
        channel: (ProcId, ProcId), // (sender, receiver)
        // groups of processes this message goes to
        dst: Set[Set[ProcId]],
        payload: str
    }

    pure val Groups = Set(
        Set(1,2),
        Set(3,4),
        Set(5)
    )

    //Nodes keep the following state
    type NodeState = {
        k: int,
        pending: Set[Message],
        delivering: Set[Message],
        delivered: Set[Message],
        previous: Set[Message]
    }

    type Network = {
        // ProcId is the receiver of the message
        msgsSent: Set[Message],         //Unicast sent messages.
        msgsRcvd: Set[Message],         //Unicast received messages
    }

    
    var nodeState: ProcId -> NodeState
    var networkState: Network

    action init: bool = all {
        nodeState' =  ProcIds.mapBy(
            p => {
                k: 0,
                pending: Set(),
                delivering: Set(),
                delivered: Set(),
                previous: Set()
            }),
        networkState' = {msgsSent: Set(), msgsRcvd: Set()}
    }

    action unchanged_all: bool = all {
        networkState' = networkState,
        nodeState' = nodeState
    }

    action GMSend(sender: ProcId, payload: str, groups: Set[Set[ProcId]]): bool = {
        all {
            // the groups are a valid destination for the multicast
            groups.forall(group => Groups.contains(group)),
            // construct the message
            val message = {
                    tag: "S0",
                    timestamp: -1,
                    channel: (-1, -1), // will be filled below
                    dst: groups,
                    payload: payload
                }
            val receivers = groups.flatten()
            val newMsgsSent = 
                receivers.fold(
                    Set(),
                    (acc, receiver) =>
                        acc.union(Set(
                            {
                                channel: (sender, receiver),
                                ...message
                            }
                        )
                    )
                )
            networkState' = {msgsSent: newMsgsSent, ...networkState},
            nodeState' = nodeState
        }
    }
}