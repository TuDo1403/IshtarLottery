// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./INFT.sol";
// import "./IBEP20.sol";
import "./AggregatorV3Interface.sol";

interface ILottoV2 {
    event OpenResult(uint256 indexed seriId, bool won);
    event SetWinners(uint256 indexed seriId, uint256 turn);
    event BuyTicket(uint256 cryptoRate, uint256 totalAmount);
    event CloseSeri(uint256 indexed seriId, uint256 endTime);
    event OpenSeri(uint256 indexed seriId, uint256 indexed seriType);

    // 8 slot
    struct Config {
        // slot #0
        INFT nft;
        uint96 affiliateAmt;
        // slot #1
        address postAddr;
        uint96 operatorCOAmt;
        // slot #2
        address stakeAddr;
        uint96 stakeAmt;
        // slot #3
        address purchaseAddr;
        uint96 purchaseAmt;
        // slot #4
        address operatorAddr;
        uint96 operatorAmt;
        // slot #5
        address carryOverAddr;
        uint96 currentSignTime;
        // slot #6
        address affiliateAddr;
        uint96 affiliateCOAmt;
        // slot #7
        address initCOAssetAddr;
        uint96 expiredPeriod;
        // slot #8
        address verifier;
        uint96 currentCOSeriId;
    }

    struct Asset {
        address asset;
        AggregatorV3Interface priceFeed;
    }

    struct AssetBalance {
        uint256 remain;
        uint256 winAmt;
    }

    struct Seri {
        // slot #0
        uint8 status;
        bool seriType;
        bool takeAssetExpired;
        uint32 numSold; //  soldTicket
        uint32 totalWin;
        uint40 nonce;
        uint64 winInitPrice;
        uint64 initPrizeTaken;
        // slot #1
        uint256 endTime;
        // slot #2
        uint256 embededInfo;
        // slot #3
        string result;
    }

    function takePrize(uint256 nftId_) external;

    function buy(
        uint256 seri_,
        string calldata numberInfo_,
        uint256 assetIdx_,
        uint256 totalTicket_
    ) external payable;

    function configSigner(address _signer) external;

    function setWinners(
        uint256 seri_,
        uint256 startTime_,
        address[] memory winners_,
        uint256[][] memory buyTickets_,
        uint256 totalTicket_,
        string[] memory assets_,
        uint256 turn_,
        uint256 timestamp_,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function takePrizeExpired(uint256 seri_) external;

    function config(
        uint256 expiredPeriod_,
        uint256 share2Stake_,
        uint256 share2Purchase_,
        uint256 share2Affiliate_,
        uint256 share2Operator_,
        uint256 share2AffiliateCO_,
        uint256 share2OperatorCO_
    ) external;

    function configAddress(
        address stake_,
        address purchase_,
        address affiliate_,
        address operator_,
        address post_,
        address carryOver_,
        address initCOAsset_,
        address nft_
    ) external;

    function setAssets(
        string[] calldata symbols_,
        address[] calldata erc20s_,
        AggregatorV3Interface[] calldata priceFeeds_
    ) external;

    function openSeri(
        uint256 seri_,
        uint256 price_,
        uint256 postPrice_,
        uint256 max2sale_,
        uint256 initPrize_
    ) external;

    function openResult(
        uint256 seri_,
        bool isWin_,
        uint256 _totalWin,
        uint256 timestamp_,
        string calldata result_,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function closeSeri(uint256 seri_) external;

    function seriAssetRemain(uint256 _seri, uint256 _asset)
        external
        view
        returns (uint256);

    function getUserTickets(uint256 _seri, address _user)
        external
        view
        returns (string[] memory);

    function getSeriWinners(uint256 _seri)
        external
        view
        returns (uint256[] memory);

    function getSeriesAssets(uint256 _seri)
        external
        view
        returns (uint256[] memory);

    function getAsset(string memory _symbol)
        external
        view
        returns (
            string memory,
            address,
            AggregatorV3Interface
        );

    function getPriceFeeds() external view returns (string[] memory);

    function currentSignTime() external view returns (uint256);

    function currentCarryOverSeri() external view returns (uint256);

    function signer() external view returns (address);

    function postAddress() external view returns (address payable);

    function stake() external view returns (address payable);

    function purchase() external view returns (address payable);

    function affiliateAddress() external view returns (address payable);

    function operator() external view returns (address payable);

    function carryOver() external view returns (address payable);

    function initCarryOverAsset() external view returns (IERC20);

    function nft() external view returns (INFT);

    function share2Stake() external view returns (uint256);

    function share2Purchase() external view returns (uint256);

    function share2Affiliate() external view returns (uint256);

    function share2Operator() external view returns (uint256);

    function share2AffiliateCO() external view returns (uint256);

    function share2OperatorCO() external view returns (uint256);

    function expiredPeriod() external view returns (uint256);

    function seriExpiredPeriod(uint256 seri_) external view returns (uint256);

    function postPrices(uint256 seri_) external view returns (uint256);

    function currentTurn(uint256 seri_) external view returns (uint256);

    function series(uint256 seri_)
        external
        view
        returns (
            uint256 price,
            uint256 soldTicket,
            string memory result,
            uint256 status,
            uint256 endTime,
            bool takeAssetExpired,
            uint256 max2sale,
            uint256 totalWin,
            uint256 seriType,
            uint256 initPrize,
            uint256 initPrizeTaken,
            uint256 winInitPrize
        );

    function totalPrize(uint256 seri_) external view returns (uint256 _prize);
}
