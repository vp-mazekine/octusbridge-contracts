pragma ton-solidity ^0.39.0;
pragma AbiHeader expire;


interface IUserData {
    struct UserDataDetails {
        uint256 token_balance;
        uint256 reward_debt;
        uint256 reward_balance;
        address root;
        address user;
        uint32 current_version;
    }

    event UserDataCodeUpgraded(uint32 code_version);
    event RelayMembershipRequested(uint128 round_num, uint128 tokens, uint256 ton_pubkey, uint256 eth_address);

    // dao
    event VoteCast(uint32 proposal_id, bool support, uint128 votes, string reason);
    event UnlockVotes(uint32 proposal_id, uint128 value);
    event UnlockCastedVotes(uint32 proposal_id);
    event ProposalCreationRejected(uint128 votes_available, uint128 threshold);
    event ProposalCodeUpgraded(uint128 votes_available, uint128 threshold);

    function lockedTokens() external view responsible returns(uint128);
    function canWithdrawVotes() external view responsible returns (bool);

    function castVote(uint32 proposal_id, bool support) external;
    function castVoteWithReason(uint32 proposal_id, bool support, string reason) external;
    function rejectVote(uint32 proposal_id) external;
    function voteCasted(uint32 proposal_id) external;

    function propose(TvmCell proposal_data, uint128 threshold) external;
    function onProposalDeployed(uint32 nonce, uint32 proposal_id, uint32 answer_id) external;
    function tryUnlockVoteTokens(uint32 proposal_id) external view;
    function unlockVoteTokens(uint32 proposal_id, bool success) external;
    function tryUnlockCastedVotes(uint32[] proposalIds) external view;
    function unlockCastedVote(uint32 proposalId, bool success) external;


    function getDetails() external responsible view returns (UserDataDetails);
    function processLinkRelayAccounts(uint256 ton_pubkey, uint256 eth_address, address send_gas_to, uint32 user_data_code_version) external;
    function processConfirmEthAccount(uint256 eth_address, address send_gas_to) external;
    function processDeposit(uint64 nonce, uint128 _amount, uint256 _accTonPerShare, uint32 code_version) external;
    function processWithdraw(uint128 _amount, uint256 _accTonPerShare, address send_gas_to, uint32 code_version) external;
    function processBecomeRelay(
        uint128 round_num,
        uint128 lock_time,
        address send_gas_to,
        uint32 user_data_code_version,
        uint32 election_code_version
    ) external;
    function relayMembershipRequestAccepted(uint128 round_num, uint128 tokens, uint256 ton_pubkey, uint256 eth_addr, address send_gas_to) external;
}
