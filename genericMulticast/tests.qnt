module tests {
    import gmcast0.* from "./gmcast0"

    run GMSendTest: bool = {
        init.then(
            GMSend(1, "nada", Groups)
        ).then(
            all {
                Groups.flatten().forall(p => networkState
                                                .msgsSent
                                                .exists(m => m.channel == (1,p))),
                unchanged_all
            }
        )
    }
}