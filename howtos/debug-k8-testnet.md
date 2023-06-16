# Local testnet debug

## Remote app

1. Build the docker debug image

    ```bash
    make build-linux
    cd test/e2e
    make docker-debug generator runner
    ```

2. Generate your manifest normally.
3. Start your run

    ```bash
    ./build/runner -f networks/testnet.toml setup
    ./build/runner -f networks/testnet.toml start
    ```

4. Figure out the ports exported by docker on each container

    ```bash
    docker container ls --format "table {{.ID}}\t{{.Names}}\t{{.Ports}}" -a
    ```

    In the following example, on `validator01` the app debugger is listening on 51600 `(0.0.0.0:51600->2345/tcp)` and Comet will listen on 51601 `(0.0.0.0:51601->2346/tcp)`.

    ```bash
    CONTAINER ID   NAMES         PORTS
f87ebb9ab8d8   validator01   26660/tcp, 0.0.0.0:51600->2345/tcp, 0.0.0.0:51601->2346/tcp, 0.0.0.0:51603->6060/tcp, 0.0.0.0:51602->26656/tcp, 0.0.0.0:5703->26657/tcp
1973cd2be79a   validator02   26660/tcp, 0.0.0.0:51598->2345/tcp, 0.0.0.0:51599->2346/tcp, 0.0.0.0:51597->6060/tcp, 0.0.0.0:51596->26656/tcp, 0.0.0.0:5704->26657/tcp
a213c8e53b90   validator03   26660/tcp, 0.0.0.0:51605->2345/tcp, 0.0.0.0:51606->2346/tcp, 0.0.0.0:51608->6060/tcp, 0.0.0.0:51607->26656/tcp, 0.0.0.0:5701->26657/tcp
    ```

5. Connect with a debugger to the app.
    - Beware that once you let the app run, it will try to connect to the signer service for a few seconds, so quickly move to the next step.

6. Connect to CometBFT

## Built-in app

1. Use the Dockerfile.debug-builtin
...
