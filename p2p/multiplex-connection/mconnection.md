# Multiplex Connection

A multiplex connection implements multiple abstract communication channels
along a single network connection.

A node maintains a `MConnection` instance for exchanging messages with each
connected `Peer`.

## Channels

A `Channel` implements an abstract communication channel with a peer.

- A globally unique byte id
- A priority

The implementation consists of:

- `sendQueue`: a queue of pending messages to send, with a configured capacity
- `sending`: a buffer storing an outgoing message, which is a pointer to the
  head of the send queue
- `recving`: a buffer storing an incoming message, with a configured maximum
  capacity

The send and receive buffers are necessary because messages are split into
packets, with a maximum size, that are transported by the underlying network
connection.
The send buffer is a pointer to the portion of a message that was not yet sent,
while the receive buffer stores received packets until a message is fully received.

## Send methods

A multiplexed connection provides two send methods: `Send` and `TrySend`.

Both methods receive a channel id (byte) and message (byte array) to send to
the provided channel.

The methods attempt to add the message to the send queue of the provided
channel.
In case of success, their operation is identical:

1. The destination `channel` is retrieved from the provided channel id. Invalid
   channel ids are ignored.
1. The message is enqueued to the `channel`'s send queue. Send queues have a
   capacity, configured by the associated reactor, and may not accept new messages.
1. If the message has been enqueued, the send routine is signaled (awaken) and
   the method returns `true`.
1. If the message is not enqueued because the `channel`'s send queue is full:
   - The `TrySend` method immediately returns `false`.  It is therefore a
     non-blocking method.
   - The `Send` method blocks until the message is enqueued.  It is therefore a
     blocking method. But if the message could not be enqueued after
     `defaultSendTimeout = 10s`, the method returns `false`.

The send methods do not return errors.

The helper `CanSend` method is a heuristic to inform whether a channel accepts
new messages.
It returns whether the channel's send queue has length lower than
`defaultSendQueueCapacity = 1`, i.e., whether it is _empty_.


## Receive method

The multiplexed transport does not provide API methods to receive messages.

Instead, an `onReceive` method is passed to its constructor.
Whenever a full message is received by the transport, this method is invoked
with channel id (byte) to which the message was sent and the received message
(byte array).


## Channels

TODO:


## Send packets

The `sendSomePacketMsgs` method blocks until the `sendMonitor` allows bytes to
be sent, provided the configured send rate (`config.SendRate`).

Then it repeatedly invokes the `sendPacketMsg` method to send a package, until
there are no channels with pending data to send, or `numBatchPacketMsgs = 10`
packets have been sent.  It returns whether the data to sent was exhausted; a
`false` return indicates that the method should be invoked again soon.

The `sendPacketMsg` method selects, among the channels with pending data to
sent, the next channel allowed to send a package, and writes one package from
this channel (`channel.writePacketMsgTo`) to the send buffer. The number of
written bytes is added to the `sendMonitor`, and the flush timer is reset.

In case of send errors, the `stopForError` method is called to stop the
connection.

### Prioritization

The `sendPacketMsg` method selects the next channel that should send a message
based on the priority and the number of bytes recently sent by each channel.

The number of bytes recently sent by a channel is an exponential moving average
of bytes sent by that channel.
It is a counter incremented by the size of each packet sent by the channel
(`channel.writePacketMsgTo` method)
and periodically (`channel.updateStats()`, called every 2s) amortized by a 0.8 factor.

The next channel to send a message is the channel whose ratio
`channel.recentlySent` / `channel.Priority` is the lowest.
Only channels with outstanding data to send are considered when computing the
least ratio.


## Send routine

Processes the following events:

- `flushTimer`: flushes the send buffer periodically (every 100ms), or upon
  writes to the send buffer,  on `sendPacketMsg` method
- `chStatsTimer`: periodic (every 2s) update of records of bytes sent per
  channel, used to implement channel priorities
- `pingTimer`: send a `Ping` packet and start the pong timer
- `pongTimeout`: pong timer has expired, which produces an error, or `Pong`
  message has been received
- `pong`: send a `Pong` packet, as a response to a received `Ping` message, and
  flush the channel
- `quitSendRoutine`: signal to quit the send loop
- `send`: signal to send packets using `sendSomePacketMsgs` method.
  The signal is produced by the `Send` and `TrySend` methods, or repeated by
  this same procedure, when there still are data to send.

Any error produced when processing events causes the connection to be stopped
(`stopForError` method).


## Receive routine

The receive routine is an infinite loop with the following steps:

1. Blocks until `recvMonitor` allows packets to be received, given the
   configured rate `config.RecvRate`
1. Read a single `Packet` and adds the number of bytes read to `recvMonitor` 
1. Process the received packet, depending on its type:
   - `Ping` packets are signaled to the send routine, which should send a
     response, via `pong` channel
   - `Pong` packets cause the associated timer to be stopped, using the
     `pongTimeout` channel
   - `Msg` packets are appended (copied) to the receive buffer of the
     associated `channel`. Messages can be split into multiple packets; if the
     received packet is the last one of a message, the message is delivered.

Errors when reading a packet from the connection, packets with unknown type,
and `Msg` packets with invalid channel ID or aggregated message size cause the
connection to be stopped (`stopForError` method).
