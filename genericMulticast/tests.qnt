module tests {
    import gmcast0.* from "./gmcast0"

    run GMSendTest: bool = {
        init.then(
            GMSend(1, 0, Groups)
        ).then(
            all {
                Groups.flatten().forall(p => 
                    networkState.get((1, p)).exists(
                        msg => msg.id == 0
                    )),
                unchanged_all
            }
        )
    }

    run ComputeSeqNumberTest: bool = {
        GMSendTest.then(
            // everyone assigns a timestamp
            val procIdList = ProcIds.fold(
                List(),
                (acc, p) => acc.append(p)
            )
            procIdList.length().reps(
                i => AssignTimestamp(
                    procIdList[i], 1, networkState.get((1, procIdList[i])).oneOf()
                )
            )
        ).then(
            // everyone computes a sequence number
            ComputeSeqNumber(
                1, 0, Groups
            )
        ).then(
            all {
                // 1 sent a message with the same timestamp to everyone
                Groups.flatten().forall(p => 
                    networkState.get((1, p)).exists(
                        msg => msg.id == 0 and msg.timestamp == 0 and msg.tag == "S2"
                    )),
                unchanged_all
            }
        )
    }

    run GMReceiveTest: bool = {
        init.then(
            GMSend(1, 0, Groups)
        ).then(
            nondet s0channel = networkState.keys()
                            .filter( k => 
                                    val src = k._1
                                    val dst = k._2
                                    networkState.get(k).exists(m => m.tag == "S0")).oneOf()
            val sender = s0channel._1
            val receiver = s0channel._2
            val receiverState = nodeState.get(receiver)
            nondet s0msg = networkState.get(s0channel).filter(m => m.tag == "S0").oneOf()
            AssignTimestamp(sender, receiver, s0msg).then(
                all {
                    networkState.get((receiver, sender)).exists(
                        msg => all {
                            msg.id == 0,
                            msg.tag == "S1"
                        }
                    ),
                    unchanged_all
                }
            )
        )
    }
}
