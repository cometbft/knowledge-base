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
            ProcIds.size().reps(i => AssignTimestamp)
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
}