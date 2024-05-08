// -*- mode: Bluespec; -*-
module spanningForestTest {
    import spells.* from "./spells"
    import spanningForest(
        NodeIds = Set("n1", "n2", "n3", "n4"),
        Txs = Set("tx1", "tx2", "tx3"),
        // Topology:
        //     1
        //   /   \
        // 2 ----- 3
        //   \   /
        //     4
        InitialPeers = Map(
            "n1" -> Set("n2", "n3"),
            "n2" -> Set("n1", "n3", "n4"),
            "n3" -> Set("n1", "n2", "n4"),
            "n4" -> Set("n2", "n3")
        )
    ) as M1 from "./spanningForest"

    def n1 = "n1"
    def n2 = "n2"
    def n3 = "n3"
    def n4 = "n4"
    def n5 = "n5"
    def T1 = "tx1"
    def T2 = "tx2"

    //--------------------------------------------------------------------------

    // Node n1 receives T1; then T1 is disseminated to all nodes.
    run t1 = M1::init
        .then(M1::receiveTxFromUser(n1, T1))
            .expect(M1::pool.get(n1).includes(T1))
        .then(M1::gossipOneTx(n1))
            .expect(M1::msgs.get(n2).contains((n1, M1::T(T1))))
            .expect(M1::msgs.get(n3).contains((n1, M1::T(T1))))
        .then(M1::receiveMessage(n2))
            .expect(M1::pool.get(n2).includes(T1))
            .expect(M1::senders.get(n2).get(T1) == List(n1))
        .then(M1::receiveMessage(n3))
            .expect(M1::pool.get(n3).includes(T1))
            .expect(M1::senders.get(n3).get(T1) == List(n1))
        .then(M1::gossipOneTx(n2))
            .expect(M1::msgs.get(n4).contains((n2, M1::T(T1))))
        .then(M1::receiveMessage(n4))
            .expect(M1::pool.get(n4).includes(T1))
            .expect(M1::senders.get(n4).get(T1) == List(n2))
        .then(M1::receiveMessage(n3))
            .expect(M1::msgs.get(n2).contains((n3, M1::HaveTx(T1))))
        .then(M1::receiveMessage(n2))
            .expect(M1::disabledRoutes.get(n2).contains((n1,n3)))
        .then(M1::gossipOneTx(n3))
            .expect(M1::msgs.get(n4).contains((n3, M1::T(T1))))
        .then(M1::receiveMessage(n4))
            .expect(M1::msgs.get(n3).contains((n4, M1::HaveTx(T1))))
        .then(M1::receiveMessage(n3))
            .expect(M1::disabledRoutes.get(n3).contains((n1,n4)))
        .expect(M1::allMsgsDelivered and M1::txInAllPools(T2))

    // Node n1 receives T2; then T2 is disseminated to all nodes.
    run t2 = t1
        .then(M1::receiveTxFromUser(n1, T2))
        .then(M1::gossipOneTx(n1))
        .then(M1::receiveMessage(n2))
        .then(M1::receiveMessage(n3))
        .then(M1::gossipOneTx(n2))
        .then(M1::receiveMessage(n4))
        .expect(M1::allMsgsDelivered and M1::txInAllPools(T2))

    //--------------------------------------------------------------------------
    // For generating traces
    //--------------------------------------------------------------------------

    action init = M1::init
    action step = M1::nextState
    
    val notAllTxsGossipped = not(M1::allTxsGossipped) or not(M1::allMsgsDelivered)

}