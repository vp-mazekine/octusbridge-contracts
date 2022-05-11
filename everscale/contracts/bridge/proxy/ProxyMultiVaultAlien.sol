pragma ton-solidity >= 0.39.0;
pragma AbiHeader time;
pragma AbiHeader expire;
pragma AbiHeader pubkey;


import "./../interfaces/IProxyExtended.sol";
import "./../interfaces/multivault/IProxyMultiVaultAlien.sol";
import "./../interfaces/event-configuration-contracts/IEverscaleEventConfiguration.sol";

import "./../../utils/ErrorCodes.sol";
import "./../../utils/TransferUtils.sol";

import "./../alien-token/TokenRootAlienEVM.sol";
import "./../alien-token-merge/MergePool.sol";
import "./../alien-token-merge/MergeRouter.sol";

import "ton-eth-bridge-token-contracts/contracts/interfaces/IAcceptTokensBurnCallback.sol";

import '@broxus/contracts/contracts/access/InternalOwner.sol';
import '@broxus/contracts/contracts/utils/CheckPubKey.sol';
import '@broxus/contracts/contracts/utils/RandomNonce.sol';
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";


contract ProxyMultiVaultAlien is
    InternalOwner,
    TransferUtils,
    CheckPubKey,
    RandomNonce,
    IAcceptTokensBurnCallback,
    IProxyExtended,
    IProxyMultiVaultAlien
{
    uint128 constant MIN_CONTRACT_BALANCE = 1 ton;

    Configuration config;
    uint8 api_version = 2;

    address public manager;

    constructor(
        address owner_
    ) public checkPubKey {
        tvm.accept();

        tvm.rawReserve(MIN_CONTRACT_BALANCE, 0);

        setOwnership(owner_);

        owner_.transfer({
            value: 0,
            bounce: false,
            flag: MsgFlag.ALL_NOT_RESERVED
        });
    }

    modifier onlyMergePool(uint nonce) {
        require(deriveMergePool(nonce) == msg.sender);

        _;
    }

    /// @notice Get current contract API version.
    /// Each time contract is upgraded, API version is incremented.
    /// @return Current API version
    function apiVersion() external override view responsible returns(uint8) {
        return{value: 0, bounce: false, flag: MsgFlag.REMAINING_GAS} api_version;
    }

    /// @notice Handles token burn.
    /// Initializes alien transfer (eg BSC CAKE or ETH AAVE).
    /// @param amount Tokens amount
    /// @param remainingGasTo Address to send remaining gas to
    /// @param payload TvmCell encoded (uint160 recipient)
    function onAcceptTokensBurn(
        uint128 amount,
        address,
        address,
        address remainingGasTo,
        TvmCell payload
    ) public override reserveMinBalance(MIN_CONTRACT_BALANCE) {
        (uint160 recipient) = abi.decode(payload, (uint160));

        TvmCell eventData = abi.encode(
            address(this), // Proxy address, used in event contract for validating token root
            msg.sender, // Everscale token root address
            remainingGasTo, // Remaining gas receiver (on event contract destroy)
            amount, // Amount of tokens to withdraw
            recipient // Recipient address in EVM network
        );

        IEverscaleEvent.EverscaleEventVoteData eventVoteData = IEverscaleEvent.EverscaleEventVoteData(
            tx.timestamp,
            now,
            eventData
        );

        IEverscaleEventConfiguration(config.everscaleConfiguration).deployEvent{
            value: 0,
            bounce: false,
            flag: MsgFlag.ALL_NOT_RESERVED
        }(eventVoteData);
    }

    /// @notice Handles alien token transfer from EVM. Token address is derived automatically and MUST
    /// be deployed before. See note on `deployAlienToken`
    /// @param remainingGasTo Gas back address
    function onEventConfirmedExtended(
        IEthereumEvent.EthereumEventInitData,
        TvmCell meta,
        address remainingGasTo
    ) external override reserveMinBalance(MIN_CONTRACT_BALANCE) {
        require(_isArrayContainsAddress(config.evmConfigurations, msg.sender));

        (
            address token,
            uint128 amount,
            address recipient
        ) = abi.decode(
            meta,
            (address, uint128, address)
        );

        _mintTokens(
            token,
            amount,
            recipient,
            remainingGasTo
        );
    }

    /// @notice Handles mint request from merge pool
    /// Mints `amount` in `token` to `recipient`
    /// @param nonce Merge pool nonce
    /// @param token Token address
    /// @param amount Amount to mint
    /// @param recipient Token recipient
    /// @param remainingGasTo Remaining gas to
    function mintTokensByMergePool(
        uint nonce,
        address token,
        uint128 amount,
        address recipient,
        address remainingGasTo
    ) external override onlyMergePool(nonce) reserveMinBalance(MIN_CONTRACT_BALANCE) {
        _mintTokens(
            token,
            amount,
            recipient,
            remainingGasTo
        );
    }

    function _mintTokens(
        address token,
        uint128 amount,
        address recipient,
        address remainingGasTo
    ) internal {
        TvmCell empty;

        ITokenRoot(token).mint{value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false}(
            amount,
            recipient,
            config.deployWalletValue,
            remainingGasTo,
            true,
            empty
        );
    }

    /// @notice Derives root address for alien token, without deploying it
    /// @param chainId EVM network chain ID
    /// @param token EVM token address
    /// @param name Token name
    /// @param symbol Token symbol
    /// @param decimals Token decimals
    function deriveAlienTokenRoot(
        uint256 chainId,
        uint160 token,
        string name,
        string symbol,
        uint8 decimals
    ) public override responsible returns (address) {
        TvmCell stateInit = _buildAlienTokenRootInitState(
            chainId,
            token,
            name,
            symbol,
            decimals
        );

        // TODO: check all responsible returns
        return{value: 0, bounce: false, flag: MsgFlag.REMAINING_GAS} address(tvm.hash(stateInit));
    }

    /// @notice Deploys Everscale token for any EVM token
    /// @param chainId EVM network chain ID
    /// @param token EVM token address
    /// @param name Token name
    /// @param symbol Token symbol
    /// @param decimals Token decimals
    /// @param remainingGasTo Remaining gas to
    function deployAlienToken(
        uint256 chainId,
        uint160 token,
        string name,
        string symbol,
        uint8 decimals,
        address remainingGasTo
    ) external override reserveMinBalance(MIN_CONTRACT_BALANCE) {
        TvmCell stateInit = _buildAlienTokenRootInitState(
            chainId,
            token,
            name,
            symbol,
            decimals
        );

        new TokenRootAlienEVM {
            stateInit: stateInit,
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED
        }(
            address(this), // Initial supply recipient
            0, // Initial supply
            config.deployWalletValue, // Deploy wallet value
            false, // Mint disabled
            false, // Burn by root disabled
            false, // Burn paused
            remainingGasTo // Remaining gas receiver
        );
    }

    function deriveMergeRouter(
        address token
    ) external override responsible returns (address router) {
        TvmCell stateInit = _buildMergeRouterInitState(token);

        return{value: 0, bounce: false, flag: MsgFlag.REMAINING_GAS} address(tvm.hash(stateInit));
    }

    function deployMergeRouter(
        address token
    ) external override reserveMinBalance(MIN_CONTRACT_BALANCE) {
        TvmCell stateInit = _buildMergeRouterInitState(token);

        new MergeRouter{
            stateInit: stateInit,
            value: 0,
            bounce: false,
            flag: MsgFlag.ALL_NOT_RESERVED
        }(owner, manager);
    }

    function deriveMergePool(
        uint256 nonce
    ) public override responsible returns (address pool) {
        TvmCell stateInit = _buildMergePoolInitState(nonce);

        return{value: 0, bounce: false, flag: MsgFlag.REMAINING_GAS} address(tvm.hash(stateInit));
    }

    function deployMergePool(
        uint256 nonce,
        address[] tokens,
        uint256 canonId
    ) external override reserveMinBalance(MIN_CONTRACT_BALANCE) {
        require(msg.sender == owner || msg.sender == manager);

        TvmCell stateInit = _buildMergePoolInitState(nonce);

        new MergePool{
            stateInit: stateInit,
            value: 0,
            bounce: false,
            flag: MsgFlag.ALL_NOT_RESERVED
        }(tokens, canonId, owner, manager);
    }

    /// @notice Proxies arbitrary message to any contract.
    /// Should be used for interacting with `onlyOwner` alien token root methods.
    /// This can be called only by `owner`.
    /// @param recipient Recipient address
    /// @param message TvmCell message, eg function call
    function sendMessage(
        address recipient,
        TvmCell message
    ) external override onlyOwner reserveMinBalance(MIN_CONTRACT_BALANCE) {
        recipient.transfer({
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED,
            body: message
        });
    }

    function getConfiguration()
        override
        external
        view
        responsible
        returns (Configuration)
    {
        return{value: 0, bounce: false, flag: MsgFlag.REMAINING_GAS} config;
    }

    function setConfiguration(
        Configuration _config,
        address remainingGasTo
    ) override external onlyOwner cashBackTo(remainingGasTo) {
        config = _config;
    }

    function _buildAlienTokenRootInitState(
        uint256 chainId,
        uint160 token,
        string name,
        string symbol,
        uint8 decimals
    ) internal view returns (TvmCell) {
        return tvm.buildStateInit({
            contr: TokenRootAlienEVM,
            varInit: {
                randomNonce_: 0,
                deployer_: address(this),
                rootOwner_: address(this),

                base_chainId_: chainId,
                base_token_: token,

                name_: name,
                symbol_: symbol,
                decimals_: decimals,

                walletCode_: config.alienTokenWalletCode,
                platformCode_: config.alienTokenWalletPlatformCode
            },
            pubkey: 0,
            code: config.alienTokenRootCode
        });
    }

    function _buildMergeRouterInitState(
        address token
    ) internal view returns (TvmCell) {
        return tvm.buildStateInit({
            contr: MergeRouter,
            varInit: {
                token: token,
                proxy: address(this)
            },
            pubkey: 0,
            code: config.mergeRouter
        });
    }

    function _buildMergePoolInitState(
        uint256 nonce
    ) internal view returns (TvmCell) {
        return tvm.buildStateInit({
            contr: MergePool,
            varInit: {
                proxy: address(this),
                _randomNonce: nonce
            },
            pubkey: 0,
            code: config.mergePool
        });
    }

    /// @notice Set merge manager
    /// Can be called only by `owner`
    /// @param _manager Manager address
    function setManager(
        address _manager
    ) external override onlyOwner cashBack {
        manager = _manager;
    }

    function mint(
        address token,
        uint128 amount,
        address recipient
    ) external override onlyOwner reserveMinBalance(MIN_CONTRACT_BALANCE) {
        _mintTokens(
            token,
            amount,
            recipient,
            msg.sender
        );
    }

    function burn(
        address token,
        uint128 amount,
        address walletOwner
    ) external override onlyOwner reserveMinBalance(MIN_CONTRACT_BALANCE) {
        TvmCell empty;

        IBurnableByRootTokenRoot(token).burnTokens{
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED,
            bounce: false
        }(
            amount,
            walletOwner,
            msg.sender,
            msg.sender,
            empty
        );
    }

    function setMergeRouterCode(
        TvmCell code
    ) external override onlyOwner cashBack {
        config.mergeRouter = code;
    }

    function setMergePoolCode(
        TvmCell code
    ) external override onlyOwner cashBack {
        config.mergePool = code;
    }

    function _isArrayContainsAddress(
        address[] array,
        address searchElement
    ) private pure returns (bool){
        for (address value: array) {
            if (searchElement == value) {
                return true;
            }
        }

        return false;
    }

    function upgrade(
        TvmCell code
    ) external onlyOwner cashBack {
        TvmCell data = abi.encode(
            config,
            api_version,
            _randomNonce
        );

        tvm.setcode(code);
        tvm.setCurrentCode(code);

        onCodeUpgrade(data);
    }

    function onCodeUpgrade(TvmCell data) private {
        (Configuration config_, uint8 api_version_, uint _randomNonce_) = abi.decode(
            data,
            (Configuration, uint8, uint)
        );

        config = config_;
        api_version = api_version_ + 1;
        _randomNonce = _randomNonce_;
    }
}
