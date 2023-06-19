# p2p interface for reactors

List of methods used by each of the standard reactors - consensus, block sync,
state sync, mempool, evidence and PEX reactor - from the `Switch` type and `Peer` interface.


## Switch

| Method                                     | consensus | block sync | state sync | mempool | evidence  | PEX   |
|--------------------------------------------|-----------|------------|------------|---------|-----------|-------|
| `Broadcast(Envelope) chan bool`            | x         | x          | x          |         |           |       |
| `MarkPeerAsGood(Peer)`                     | x         |            |            |         |           |       |
| `StopPeerForError(Peer, reason)`           | x         | x          | x          | x       | x         | x     |
| `StopPeerGracefully(Peer)`                 |           |            |            |         |           | x     |
| `Peers() IPeerSet`                         | x         | x          |            |         |           | x     |
| `NumPeers() (out, in, dialing int)`        |           | x          |            |         |           | x     |
| `Reactor() Reactor`                        |           | x          |            |         |           |       |
| `Logger.Error()`                           |           |            |            |         |           | x     |
| `IsPeerPersistent(*NetAddr) bool`          |           |            |            |         |           | x     |
| `MaxNumOutboundPeers() int`                |           |            |            |         |           | x     |
| `DialPeerWithAddress(*NetAddr) error`      |           |            |            |         |           | x     |
| `IsDialingOrExistingAddress(*NetAddr) bool`|           |            |            |         |           | x     |

### Consensus

Broadcast

- broadcastNewRoundStepMessage
- broadcastNewValidBlockMessage
- broadcastHasVoteMessage

StopPeerForError:

- msg, err := MsgFromProto(e.Message)
- err = msg.ValidateBasic();
- err = msg.ValidateHeight(initialHeight) for NewRoundStepMessage
- err := votes.SetPeerMaj23() for VoteSetMaj23Message

MarkPeerAsGood in peerStatsRoutine:

- numVotes := ps.RecordVote(); numVotes%votesToContributeToBecomeGoodPeer == 0
- numParts := ps.RecordBlockPart(); numParts%blocksToContributeToBecomeGoodPeer == 0

Peers():

- peer := conR.Switch.Peers().Get(msg.PeerID): peerStatsRoutine
- for _, peer := range conR.Switch.Peers().List(): StringIndented

### Block sync

Broadcast:

- BroadcastStatusRequest

StopPeerForError:

- err = err := ValidateMsg(e.Message)
- peer := bcR.Switch.Peers().Get(err.peerID); if peer != nil on poolRoutine (x3)

Peers():

- peer := bcR.Switch.Peers().Get(request.PeerID) on poolRoutine
- peer := bcR.Switch.Peers().Get(err.peerID) on poolRoutine
- peer := bcR.Switch.Peers().Get(peerID)
- peer2 := bcR.Switch.Peers().Get(peerID2)

NumPeers():

- outbound, inbound, _ := bcR.Switch.NumPeers() on poolRoutine

Reactor():

- conR, ok := bcR.Switch.Reactor("CONSENSUS").(consensusReactor) on poolRoutine

### State sync

Broadcast:

- Sync() method

StopPeerForError:

- err := validateMsg(e.Message)

### Mempool

StopPeerForError:

- Receive with unknown message type

### Evidence

StopPeerForError:

- evis, err := evidenceListFromProto(e.Message)
- err := evR.evpool.AddEvidence(ev); case err.(type) == *types.ErrInvalidEvidence:


### PEX

StopPeerGracefully:

- after e.Src.FlushStop() for replying to a node in seed mode
- r.Switch.StopPeerGracefully(peer) on attemptDisconnects

StopPeerForError:

- err := r.receiveRequest(e.Src); err != nil for a tmp2p.PexRequest
- addrs, err := p2p.NetAddressesFromProto(msg.Addrs); err != nil for tmp2p.PexAddrs
- err = r.ReceiveAddrs(addrs, e.Src); err != nil for tmp2p.PexAddrs

Peers():

- peers := r.Switch.Peers().List() on ensurePeers
- peer := r.Switch.Peers().Get(addr.ID) on crawlPeers
- for peer := range r.Switch.Peers().List() on attemptDisconnects

NumPeers():

- out, in, dial = r.Switch.NumPeers() on ensurePeers
- out, in, dial := r.Switch.NumPeers() on nodeHasSomePeersOrDialingAny

IsPeerPersistent():

- if !r.Switch.IsPeerPersistent(addr) && attempts > maxAttemptsToDial on dialPeer
- r.Switch.IsPeerPersistent(addr) on maxBackoffDurationForPeer

IsDialingOrExistingAddress:

- r.Switch.IsDialingOrExistingAddress(try) on ensurePeers

DialPeerWithAddress:

- err := r.Switch.DialPeerWithAddress(addr) on dialPeer
- err := r.Switch.DialPeerWithAddress(seedAddr) on dialSeeds

MaxNumOutboundPeers:

- numToDial     = r.Switch.MaxNumOutboundPeers() - (out + dial) on ensurePeers

Logger:

- r.Switch.Logger.Error() on dialSeeds
- r.Switch.Logger.Error() on dialSeeds


## Peer


| Method                                     | consensus | block sync | state sync | mempool | evidence  | PEX   |
|--------------------------------------------|-----------|------------|------------|---------|-----------|-------|
| `ID() ID`                                  | x         | x          | x          | x       | x         | x     |
| `IsRunning() bool`                         | x         |            |            | x       | x         |       |
| `Get(string) interface{}`                  | x         |            |            | x       | x         |       |
| `Set(string, interface{})`                 | x         |            |            |         |           |       |
| `Send(Envelope) bool`                      | x         | x          | x          | x       | x         | x     |
| `TrySend(Envelope) bool`                   | x         | x          |            |         |           |       |
| `Quit() <-chan struct{}`                   |           |            |            | x       | x         |       |
| `FlushStop()`                              |           |            |            |         |           | x     |
| `IsOutbound() bool`                        |           |            |            |         |           | x     |
| `IsPersistent() bool`                      |           |            |            |         |           | x     |
| `NodeInfo() NodeInfo`                      |           |            |            |         |           | x     |
| `Status() ConnectionStatus`                |           |            |            |         |           | x     |
| `SocketAddr() *NetAddress`                 |           |            |            |         |           | x     |

### Consensus

ID():

- err := votes.SetPeerMaj23(msg.Round, msg.Type, ps.peer.ID(), msg.BlockID) on Receive
- ps.peer.ID() on StringIndented

IsRunning() from Service interface:

- gossipDataRoutine
- gossipVotesRoutine
- queryMaj23Routine

Get():

- peerState, ok := peer.Get(types.PeerStateKey).(*PeerState) on AddPeer
- ps, ok := peer.Get(types.PeerStateKey).(*PeerState) on peerStatsRoutine
- ps, ok := peer.Get(types.PeerStateKey).(*PeerState) on StringIndented

Set():

- peer.Set(types.PeerStateKey, peerState) on InitPeer

Send:

- gossipDataRoutine for &cmtcons.BlockPart
- gossipDataRoutine for &cmtcons.Proposal
- gossipDataRoutine for &cmtcons.ProposalPOL
- gossipDataForCatchup for &cmtcons.BlockPart
- PickSendVote for &cmtcons.Vote from gossipVotesForHeight and gossipVotesRoutine
- sendNewRoundStepMessage for cmtcons.NewRoundStep

TrySend:

- queryMaj23Routine for &cmtcons.VoteSetMaj23

### Block sync

ID():

- bcR.pool.RemovePeer(peer.ID()) on RemovePeer
- if err := bcR.pool.AddBlock(e.Src.ID(), bi, extCommit, msg.Block.Size()) on Receive
- bcR.pool.SetPeerRange(e.Src.ID(), msg.Base, msg.Height) on Receive
- bcR.Logger.Debug("Send queue is full, drop block request", "peer", peer.ID(), "height", request.Height) on poolRoutine

Send:

- AddPeer for &bcproto.StatusResponse

TrySend:

- respondToPeer for &bcproto.NoBlockResponse
- respondToPeer for &bcproto.BlockResponse
- Receive for &bcproto.StatusResponse
- poolRoutine for &bcproto.BlockRequest

### State sync

ID():

- s.logger.Debug("Requesting snapshots from peer", "peer", peer.ID()) on syncer.AddPeer
- s.snapshots.RemovePeer(peer.ID()) on syncer.RemovePeer
- snapshot.Format, "peer", e.Src.ID()) on Receive
- p.snapshotPeers[key][peer.ID()] = peer on snapshotPool.Add (multiple)
- return peers[a].ID() < peers[b].ID() on snapshotPool.GetPeers

Send:

- syncer.AddPeer for &ssproto.SnapshotsRequest{}
- Receive for &ssproto.SnapshotsResponse
- Receive for &ssproto.ChunkResponse
- syncer.requestChunk for &ssproto.ChunkRequest

### Mempool

ID():

- ids.peerMap[peer.ID()] = curID on mempoolIDs.ReserveForPeer
- delete(ids.peerMap, peer.ID()) on mempoolIDs.Reclaim
- return ids.peerMap[peer.ID()] on mempoolIDs.GetForPeer
- txInfo.SenderP2PID = e.Src.ID() on Receive


IsRunning():

- if !memR.IsRunning() || !peer.IsRunning() on broadcastTxRoutine

Quit():

- case <-peer.Quit(): on broadcastTxRoutine

Get():

- peerState, ok := peer.Get(types.PeerStateKey).(PeerState) on Receive

Send:

- Receive for &protomem.Txs

### Evidence

Quit():

- case <-peer.Quit(): on broadcastEvidenceRoutine

IsRunning():

- if !memR.IsRunning() || !peer.IsRunning() on broadcastEvidenceRoutine

Get():

- peerState, ok := peer.Get(types.PeerStateKey).(PeerState) on prepareEvidenceMessage

Send:

- broadcastEvidenceRoutine for &cmtproto.EvidenceList (build by evidenceListToProto)

### PEX

ID():

- id := string(p.ID()) on RequestAddrs
- id := string(p.ID()) on RemovePeer
- id := string(src.ID()) on receiveRequest
- id := string(e.Src.ID()) on Receive

NodeInfo():

- addr, err := p.NodeInfo().NetAddress() on AddPeer
- srcAddr, err := src.NodeInfo().NetAddress() on ReceiveAddrs

IsOutbound():

- p.IsOutbound() on AddPeer
- if r.config.SeedMode && !e.Src.IsOutbound() on Receive

IsPersistent():

- if peer.IsPersistent() on attemptDisconnects

Others:

- e.Src.FlushStop() on Receive for nodes in seed mode
- r.book.MarkBad(e.Src.SocketAddr(), defaultBanTime) on Receive
- if peer.Status().Duration < r.config.SeedDisconnectWaitPeriod on attemptDisconnects

Send:

- RequestAddrs for &tmp2p.PexRequest{}
- SendAddrs for  &tmp2p.PexAddrs
