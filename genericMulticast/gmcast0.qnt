module gmcast0 {
    import spell.* from "./spell"

    type ProcId = int

    //XXX Quint: Ideally these should be consts, but because it would have to be instantiated on every import, there would be duplication.
    //All processes in the system

    pure val MsgType = Set("S0", "S1", "S2")
    pure val ProcIds = Set(1,2,3,4,5)
    type Message = {
        tag: str, //Shoud be in MsgType
        timestamp: int, // -1 means no timestamp
        // groups of processes this message goes to
        dst: Set[Set[ProcId]],
        id: int
    }

    type Channel = (ProcId, ProcId)

    pure val Groups = Set(
        Set(1,2),
        Set(3,4),
        Set(5)
    )

    //Nodes keep the following state
    type NodeState = {
        k: int,
        pending: Set[(Message,int)],
        delivering: Set[Message],
        delivered: Set[Message],
        previous: Set[Message]
    }

    type Network = 
       Channel -> Set[Message]

    
    var nodeState: ProcId -> NodeState
    var networkState: Network

    pure def conflicts(lhs: Message, rhs: Message): bool = true

    action init: bool = all {
        nodeState' =  ProcIds.mapBy(
            p => {
                k: 0,
                pending: Set(),
                delivering: Set(),
                delivered: Set(),
                previous: Set()
            }),
        // create channels between all processes
        networkState' = 
            ProcIds.crossproduct(ProcIds).mapBy(
                (p1, p2) => Set()
            )
    }

    action unchanged_all: bool = all {
        networkState' = networkState,
        nodeState' = nodeState
    }

    action GMSend(sender: ProcId, id: int, groups: Set[Set[ProcId]]): bool = {
        all {
            // the groups are a valid destination for the multicast
            groups.forall(group => Groups.contains(group)),
            // construct the message
            val message = {
                    tag: "S0",
                    timestamp: -1, // not used for S0 messages
                    dst: groups,
                    id: id
                }
            val receivers = groups.flatten()
            val newMsgsSent = 
                ProcIds.crossproduct(ProcIds).mapBy(
                    (p1, p2) => Set()
                )
            networkState' = 
                networkState.keys().mapBy(
                    channel => 
                        if (channel._1 == sender and receivers.contains(channel._2)) {
                            networkState.get(channel).union(Set(message))
                        } else {
                            networkState.get(channel)
                        }
                ),
            nodeState' = nodeState
        }
    }
        
    // action ComputeSeqNumber(p: ProcId, m: Message): bool = {
    //     all {
    //         // for each destination process, we have received an S1
    //         m.dst.flatten().forall(
    //         receiver => 
    //             networkState.msgsRcvd.exists(
    //                 msg => msg.channel == (p, receiver) and
    //                     equal(msg, m) and
    //                     msg.tag == "S1"
    //             )
    //         ),
    //         // find the maximal timestamp among the S1 messages
    //         m.dst.flatten().fold(
    //             -1,
    //             (acc, receiver) =>
    //                 val msgFromReceiver = networkState.msgsRcvd.filter(
    //                     msg => msg.channel == (p, receiver) and
    //                         equal(msg, m) and
    //                         msg.tag == "S1"
    //                 ).chooseSome()
    //         )

    pure def AssignTimestampHelper(
                sender: ProcId, 
                receiver: ProcId, 
                m: Message, 
                netState: Network, 
                noState: NodeState
            ): (Network, NodeState) = {

        val newK =  
            if (noState.previous.exists(om => om.conflicts(m))) 
                noState.k + 1 
            else 
                noState.k

        val newPrevious =
            if (noState.previous.exists(om => om.conflicts(m)))
                Set(m) 
            else 
                noState.previous.union(Set(m))
        
        val newPending = noState.pending.union(Set((m,newK)))

        val newNodeState = {
                                k: newK,
                                pending: newPending,
                                previous: newPrevious,
                                ...noState
                            }

        val newMsg = {tag: "S1", timestamp: newK, ...m}
        
        val newMsgsSent = netState.get((receiver,sender)).exclude(Set(m)).union(Set(newMsg)) //This is incomplete.
        
        val newNetworkState = netState.put((receiver, sender), newMsgsSent)

        (newNetworkState, newNodeState)
    }

    action AssignTimestamp(): bool = all {
        val s0channels = networkState.keys()
                            .filter( k => 
                                    val src = k._1
                                    val dst = k._2
                                    networkState.get(k).exists(m => m.tag == "S0"))
        all {
            s0channels.size() > 0,
            nondet s0channel = s0channels.oneOf()
            val sender = s0channel._1
            val receiver = s0channel._2
            val receiverState = nodeState.get(s0channel._2)
            nondet s0msg = networkState.get(s0channel).filter(m => m.tag == "S0").oneOf()
            val newState = AssignTimestampHelper(sender, receiver, s0msg, networkState, receiverState)
            val newNetworkState = newState._1
            val newReceiverState = newState._2
            all {
                networkState' = newNetworkState,
                nodeState' = nodeState.put(receiver, newReceiverState)
            }
        }
    }
}