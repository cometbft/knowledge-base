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
}