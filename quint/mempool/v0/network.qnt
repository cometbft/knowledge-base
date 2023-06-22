// -*- mode: Bluespec; -*-
// The messages in the network of peers
module network {
    import basicSpells.* from "./basicSpells"
    import base.* from "./base"
    import params as Params from "./base"

    // const Peers: NodeId -> Set[NodeId]
    val Peers: NodeId -> Set[NodeId] = Params::__Peers

    //--------------------------------------------------------------------------
    // Network state
    //--------------------------------------------------------------------------
    type TxsMsg = { tag: str, senderId: NodeId, tx: Tx }
    
    // For each node, the messages sent by other nodes and still to be processed.
    var msgs: NodeId -> Set[TxsMsg]

    def incomingMsgs(nodeId) =
        msgs.get(nodeId)

    //--------------------------------------------------------------------------
    action init =
        msgs' = NodeIds.mapBy(_ => Set())

    action sendTo(msg: TxsMsg, peer: NodeId): bool =
        msgs' = msgs.mapPut(peer, (_msgs) => _msgs.setAdd(msg))

    action sendToMany(msg: TxsMsg, peers: Set[NodeId]): bool =
        msgs' = msgs.mapPutMany(peers, (peer) => peer.incomingMsgs().setAdd(msg))

    action receiveMsg(nodeId: NodeId, msg: TxsMsg): bool =
        msgs' = msgs.mapPut(nodeId, (_msgs) => _msgs.setRemove(msg))    

    action unchanged =
        msgs' = msgs
}