// -*- mode: Bluespec; -*-

// An ABCI server implemented by an application receives asynchronous ABCI
// requests and replies with ABCI responses.
module abciServers {
    import basicSpells.* from "./basicSpells"
    import base.* from "./base"
    import errors.* from "./errors"
    import abciMessages as Msg from "./abciMessages"

    type ABCIRequests = { tag: str, tx: Tx }
    val ABCIRequestTags = Set("CheckTx", "RecheckTx")
    
    // The server receives requests in a queue (actually, a set) and responds
    // to a queue (a set) of responses. Each request maps to: the node id of the
    // sender, the height at which it was requested, and the response, if any.
    var requestResponses: NodeId -> (Msg::Request -> (NodeId, Height, Msg::Response))

    //--------------------------------------------------------------------------
    // Auxiliary definitions
    //--------------------------------------------------------------------------
    def RequestResponses(node) = requestResponses.get(node)
    def ResponsesTo(node, request) = requestResponses.get(node).get(request)
    def Requests(node) = node.RequestResponses().keys()
    
    def senderFor(node, request) = node.ResponsesTo(request)._1
    def heightFor(node, request) = node.ResponsesTo(request)._2
    def responseFor(node, request) = node.ResponsesTo(request)._3

    def checkTxRequests(node) = 
        node.Requests().filter(r => r.checkTxType == "New")
    def recheckTxRequests(node) = 
        node.Requests().filter(r => r.checkTxType =="Recheck")

    //--------------------------------------------------------------------------
    // Actions
    //--------------------------------------------------------------------------
    action init =
        requestResponses' = NodeIds.mapBy(_ => Map())

    // The "New" request includes the sender and the height of mempool when it
    // was requested.
    action sendRequestNewCheckTx(nodeId, tx, senderId, h) = 
        val req = { tag: "CheckTx", tx: tx, checkTxType: "New" }
        val err = if (req.tx.isValidAt(h)) noError else InvalidTxError
        val resp = { tag: req.tag, err: err }
        requestResponses' = requestResponses.mapPut(nodeId, 
            (rs) => rs.put(req, (senderId, h, resp)))

    // The "Recheck" request only includes the height. We process multiple
    // requests at once.
    action sendRequestRecheckTxs(nodeId, txs, h) =
        val newRequests = txs.map(tx => { tag: "CheckTx", tx: tx, checkTxType: "Recheck" })
        requestResponses' = requestResponses.mapPut(nodeId, (rs) =>
            rs.mapPutMany(newRequests, (req) => {
                val err = if (req.tx.isValidAt(h)) noError else InvalidTxError
                (noNode, h, { tag: req.tag, err: err }) 
            }))

    // When a response is processed by the ABCI client, we no longer need so we
    // remove it.
    action removeRequest(nodeId, request) =
        requestResponses' = requestResponses.mapPut(nodeId, (rs) => rs.mapRemove(request))

    action unchanged =
        requestResponses' = requestResponses

}
