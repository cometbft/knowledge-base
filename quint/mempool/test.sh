#!/bin/sh

# consensus
echo "
proposeTwiceError
decideNonProposedError
decideProposedSuccess
" | quint -r Consensus.qnt::ConsensusTests
quint run --main ConsensusTests --invariant invariant Consensus.qnt 

# ledger
echo "
submitTwiceError
commitNonSubmittedError
commitSubmittedSuccess
" | quint -r Ledger.qnt::LedgerTests
quint run --main LedgerTests --invariant invariant Ledger.qnt 

# mempool
echo "moveHeightOnce" | quint -r Mempool.qnt::MempoolTests
quint run --verbosity 3 --main MempoolTests --invariant allInv Mempool.qnt 
