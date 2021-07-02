pragma ton-solidity ^0.39.0;

import "./IBasicEvent.sol";


interface ITonEvent is IBasicEvent {
    struct TonEventVoteData {
        uint eventTransaction;
        uint64 eventTransactionLt;
        uint32 eventTimestamp;
        uint32 eventIndex;
        TvmCell eventData;
    }

    struct TonEventInitData {
        TonEventVoteData voteData;
        address configuration;
        TvmCell meta;
        address staking;
        uint32 chainId;
    }

    event Confirm(uint relay, bytes signature);
}
