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

    pure def conflicts(lhs: int, rhs: int): bool = true

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
        
    action ComputeSeqNumber(p: ProcId, id: int, dst: Set[Set[ProcId]]): bool = {
        all {
            // for all processes in dst, we have received an S1
            dst.flatten().forall(
                receiver => 
                    // there must be a message tagged with S1 sent by receiver to p relating to m
                    networkState.get((p, receiver)).exists(
                        msg => msg.id == id and
                            msg.tag == "S1"
                    )
                    
            ),
            // get messages tagged with S1 received by p relating to the message id
            val receivedMessages = dst.flatten().fold(
                Set(), (acc, receiver) =>
                    val msgsFromReceiver = networkState.get((receiver, p)).filter(
                        msg => msg.id == id and
                            msg.tag == "S1")
                    acc.union(msgsFromReceiver)
            )

            // find the maximal timestamp among the S1 messages
            val timestamp_final = receivedMessages.fold(
                -1,
                (acc, msg) => 
                    if (msg.timestamp > acc) {
                        msg.timestamp
                    } else {
                        acc
                    }
            )
            // tag the message with S2 and the timestamp
            val message_final = {
                tag: "S2",
                timestamp: timestamp_final,
                dst: dst,
                id: id
            }
            // send it to all destination processes
            networkState' = 
                networkState.keys().mapBy(
                    channel => 
                        if (dst.flatten().contains(channel._2)) {
                            networkState.get(channel).union(Set(message_final))
                        } else {
                            networkState.get(channel)
                        }
                ),
            nodeState' = nodeState
        }
    }

    pure def AssignTimestampHelper(
                sender: ProcId, 
                receiver: ProcId, 
                m: Message, 
                netState: Network, 
                noState: NodeState
            ): (Network, NodeState) = {

        val newK =  
            if (noState.previous.exists(om => om.id.conflicts(m.id))) 
                noState.k + 1 
            else 
                noState.k

        val newPrevious =
            if (noState.previous.exists(om => om.id.conflicts(m.id)))
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
        
        val newIncomingChannel = netState.get((sender,receiver)).exclude(Set(m))
        val newOutgoingChannel =    if (sender == receiver) 
                                        newIncomingChannel.union(Set(newMsg))
                                    else
                                        netState.get((receiver,sender)).union(Set(newMsg))
        val newNetworkState = 
            netState.put((sender,receiver), newIncomingChannel)
                    .put((receiver, sender), newOutgoingChannel)

        (newNetworkState, newNodeState)
    }

    action AssignTimestamp(sender: ProcId, receiver: ProcId, s0msg: Message): bool = all {
        all {
            val receiverState = nodeState.get(receiver)
            val newState = AssignTimestampHelper(sender, receiver, s0msg, networkState, receiverState)
            val newNetworkState = newState._1
            val newReceiverState = newState._2
            all {
                networkState' = newNetworkState,
                nodeState' = nodeState.put(receiver, newReceiverState)
            }
        }
    }

    action AssignSeqNumber(receiver: ProcId, id: int, sender: ProcId): bool = {
        all {
            // get the first message from sender to receiver with the id and
            // tag S2
            val msg = networkState.get((sender, receiver)).fold(
                // start with empty dummy message
                {tag: "S2", timestamp: -1, dst: Set(), id: -1},
                (acc, m) => 
                    if (m.id == id and m.tag == "S2") {
                        m
                    } else {
                        acc
                    }
            )
            // get the node state of the receiver
            val receiverState = nodeState.get(receiver)
            // get the timestamp of the message
            val tsf = msg.timestamp
            
            // val newK = 
            // // create the new node state
            // val newReceiverState = 
            //     {
            //         k: if tsf > receiverState.k {k+1},
            //         pending: receiverState.pending.exclude(Set((msg, tsf))),
            //         delivering: receiverState.delivering.union(Set(msg)),
            //         delivered: receiverState.delivered,
            //         previous: receiverState.previous
            //     }
            true
        }
    }
}