// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./interfaces/ILottoV2.sol";

import "./libraries/SeriLib.sol";

contract LottoV2 is Ownable, ILottoV2 {
    using SeriLib for uint256;
    using SafeERC20 for IERC20;

    string private constant _SERI_NOT_WINNER = "NOT_WINNER";
    string private constant _INVALID_SIGNATURE = "INVALID_SIG";
    string private constant _INVALID_PERCENT = "INVALID_PERCENT";
    string private constant _INVALID_TIMESTAMP = "INVALID_TIMESTAMP";

    Config private _config; //  slot 0 -> 8

    string[] private _supportTokens;

    mapping(uint256 => uint256[]) private _winners;
    mapping(uint256 => uint256[]) private _prizeTaked;
    mapping(uint256 => uint256[]) private _assetIndices;

    mapping(string => Asset) private _assets;
    mapping(uint256 => Seri) private _series;
    // seriId => userAddr => Ticket
    mapping(uint256 => mapping(address => string[])) private _userTickets;
    // seriId => assetIdx => AssetBalance
    mapping(uint256 => mapping(uint256 => AssetBalance)) private _balances;

    mapping(uint256 => mapping(address => mapping(uint256 => uint256)))
        public userTicketsWon; // seri => user => ticket id => token id
    mapping(uint256 => mapping(address => mapping(uint256 => uint256)))
        public userTicketsWonb; // seri => user => token id => ticket id

    constructor() payable {
        Config memory cfg;
        cfg.verifier = 0xaF94Cfc93cf22a5d92c828A659299777540b9505;
        cfg.initCOAssetAddr = 0x55d398326f99059fF775485246999027B3197955;
        cfg.nft = INFT(0x3E5b39625eE9934Db40Bb601f95EEf841687BF21);
        cfg.expiredPeriod = 7776000;

        _config = cfg;
    }

    function takePrize(
        uint256 nftId_ //whenNotPaused //nonReentrant
    ) external override {
        address sender = _msgSender();
        //__onlyEOA(sender);
        Seri memory seri;
        uint256 _seri;
        uint256 _winTickets;
        uint256 _buyTickets;
        {
            INFT _nft = _config.nft;
            (_seri, , , , , _winTickets, , _buyTickets, ) = _nft.metadatas(
                nftId_
            );

            seri = _series[_seri];
            require(seri.status == 2, _SERI_NOT_WINNER);
            unchecked {
                require(
                    seri.endTime + seri.embededInfo.expiredPeriod() >
                        block.timestamp,
                    "EXPIRED"
                );
            }
            _nft.safeTransferFrom(sender, address(this), nftId_, "");
            _nft.burn(nftId_);
            _prizeTaked[_seri].push(nftId_);
        }

        address addrThis = address(this);
        {
            uint256 takeAmt;
            uint256 remain;
            uint256[] memory assetIndices = _assetIndices[_seri];
            uint256 length = assetIndices.length;
            uint256 assetIdx;
            AssetBalance memory assetBalance;
            for (uint256 i; i < length; ) {
                assetIdx = assetIndices[i];
                assetBalance = _balances[_seri][assetIdx];
                remain = assetBalance.remain;
                if (remain > 0) {
                    takeAmt = assetBalance.winAmt;

                    if (takeAmt == 0) {
                        takeAmt = (remain * _buyTickets) / _winTickets;
                        assetBalance.winAmt = takeAmt;
                    }
                    _balances[_seri][assetIdx].remain -= takeAmt;

                    __transfer(
                        _assets[_supportTokens[assetIdx]].asset,
                        addrThis,
                        sender,
                        takeAmt
                    );
                }
                unchecked {
                    ++i;
                }
            }
        }
        
        if (seri.seriType) {
            uint64 takeAssetInitAmt = seri.winInitPrice;
            if (takeAssetInitAmt == 0) {
                _series[_seri].winInitPrice = uint64(
                    (seri.embededInfo.initPrize() * _buyTickets) / _winTickets
                );
            }
            _series[_seri].initPrizeTaken += takeAssetInitAmt;
            __transfer(
                _config.initCOAssetAddr,
                addrThis,
                sender,
                takeAssetInitAmt
            );
            
        }        
    }

    function buy(
        uint256 seri_,
        string calldata numberInfo_,
        uint256 assetIdx_,
        uint256 totalTicket_
    ) external payable override {
        address sender = _msgSender();
        //__onlyEOA(sender);
        _userTickets[seri_][sender].push((numberInfo_));

        bool seriType;
        uint256 postAmt;
        uint256 assetAmt;
        {
            Seri memory seri = _series[seri_];
            seriType = seri.seriType;
            uint256 embededInfo = seri.embededInfo;
            unchecked {
                require(
                    seri.numSold + totalTicket_ <= embededInfo.max2Sale(),
                    "EXCEED_MAX_TO_SALE"
                );
            }

            assetAmt =
                ((_series[seri_].embededInfo.price() * 1 ether) /
                    getLatestPrice(_supportTokens[assetIdx_])) *
                totalTicket_;
            postAmt =
                (assetAmt * embededInfo.postPrice()) /
                embededInfo.price();
            _series[seri_].numSold += uint32(totalTicket_);
        }

        uint256 stakeAmt;
        uint256 purchaseAmt;
        uint256 affiliateAmt;
        uint256 takeTokenAmt;
        {
            Config memory cfg = _config;
            if (!seriType) {
                stakeAmt = (postAmt * cfg.stakeAmt) / 1e6;
                purchaseAmt = (postAmt * cfg.purchaseAmt) / 1e6;
                takeTokenAmt = (postAmt * cfg.operatorAmt) / 1e6;
                affiliateAmt = (postAmt * cfg.affiliateAmt) / 1e6;
            } else {
                takeTokenAmt = (postAmt * cfg.operatorCOAmt) / 1e6;
                affiliateAmt = (postAmt * cfg.affiliateCOAmt) / 1e6;
            }

            {
                address addrThis = address(this);
                address asset = _assets[_supportTokens[assetIdx_]].asset;
                __transfer(asset, sender, addrThis, assetAmt);
                __transfer(asset, addrThis, cfg.stakeAddr, stakeAmt);
                __transfer(asset, addrThis, cfg.postAddr, assetAmt - postAmt);
                __transfer(asset, addrThis, cfg.purchaseAddr, purchaseAmt);
                __transfer(asset, addrThis, cfg.operatorAddr, takeTokenAmt);
                __transfer(asset, addrThis, cfg.affiliateAddr, affiliateAmt);
            }
        }

        if (_balances[seri_][assetIdx_].remain == 0)
            _assetIndices[seri_].push(assetIdx_);

        if (!seriType) {
            _balances[seri_][assetIdx_].remain +=
                postAmt -
                affiliateAmt -
                takeTokenAmt;
        } else {
            _balances[seri_][assetIdx_].remain +=
                postAmt -
                affiliateAmt -
                takeTokenAmt -
                stakeAmt -
                purchaseAmt;
        }

        emit BuyTicket(getLatestPrice(_supportTokens[assetIdx_]), assetAmt);
    }

    function configSigner(address _signer) external override {
        require(_msgSender() == _config.verifier, "UNAUTHORIZED");
        _config.verifier = _signer;
    }

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
    ) external override onlyOwner {
        {
            Seri memory seri = _series[seri_];
            require(seri.nonce != turn_, "ALREADY_PAID");
            require(seri.status == 2, _SERI_NOT_WINNER);
            unchecked {
                require(
                    seri.totalWin >= _winners[seri_].length + totalTicket_,
                    "INVALID_WINNERS"
                );
            }
        }

        {
            Config memory cfg = _config;
            require(timestamp_ > cfg.currentSignTime, _INVALID_TIMESTAMP);

            require(
                ECDSA.recover(
                    keccak256(
                        abi.encodePacked(
                            "\x19Ethereum Signed Message:\n32",
                            keccak256(
                                abi.encodePacked(
                                    timestamp_,
                                    abi.encode(
                                        seri_,
                                        winners_,
                                        buyTickets_,
                                        totalTicket_,
                                        assets_,
                                        turn_
                                    )
                                )
                            )
                        )
                    ),
                    v,
                    r,
                    s
                ) == cfg.verifier,
                _INVALID_SIGNATURE
            );
            _sendNFT(
                cfg.nft,
                seri_,
                startTime_,
                winners_,
                assets_,
                buyTickets_
            );
        }

        _config.currentSignTime = uint96(timestamp_);
        _series[seri_].nonce = uint40(turn_);

        emit SetWinners(seri_, turn_);
    }

    function takePrizeExpired(uint256 seri_) external override onlyOwner {
        Seri memory seri = _series[seri_];

        require(!seri.takeAssetExpired, "TAKED");
        unchecked {
            require(
                block.timestamp >
                    seri.endTime + seri.embededInfo.expiredPeriod(),
                "NOT_EXPIRED"
            );
        }

        _series[seri_].takeAssetExpired = true;

        Config memory cfg = _config;
        __transferRemainAsset(seri_, cfg, _assetIndices[seri_]);
        if (seri.seriType) {
            unchecked {
                __transfer(
                    cfg.initCOAssetAddr,
                    address(this),
                    cfg.carryOverAddr,
                    seri.embededInfo.initPrize() - seri.initPrizeTaken
                );
            }
        }
    }

    function config(
        uint256 expiredPeriod_,
        uint256 share2Stake_,
        uint256 share2Purchase_,
        uint256 share2Affiliate_,
        uint256 share2Operator_,
        uint256 share2AffiliateCO_,
        uint256 share2OperatorCO_
    ) external override onlyOwner {
        require(share2AffiliateCO_ + share2OperatorCO_ < 1e6, _INVALID_PERCENT);
        require(
            share2Stake_ +
                share2Purchase_ +
                share2Affiliate_ +
                share2Operator_ <
                1e6,
            _INVALID_PERCENT
        );
        Config memory cfg = _config;

        cfg.stakeAmt = uint96(share2Stake_);
        cfg.purchaseAmt = uint96(share2Purchase_);
        cfg.operatorAmt = uint96(share2Operator_);
        cfg.expiredPeriod = uint96(expiredPeriod_);
        cfg.affiliateAmt = uint96(share2Affiliate_);
        cfg.operatorCOAmt = uint96(share2OperatorCO_);
        cfg.affiliateCOAmt = uint96(share2AffiliateCO_);

        _config = cfg;
    }

    function configAddress(
        address stake_,
        address purchase_,
        address affiliate_,
        address operator_,
        address post_,
        address carryOver_,
        address initCOAsset_,
        address nft_
    ) external override onlyOwner {
        Config memory cfg = _config;

        cfg.nft = INFT(nft_);
        cfg.stakeAddr = stake_;
        cfg.postAddr = post_;
        cfg.purchaseAddr = purchase_;
        cfg.operatorAddr = operator_;
        cfg.carryOverAddr = carryOver_;
        cfg.affiliateAddr = affiliate_;
        cfg.initCOAssetAddr = initCOAsset_;

        _config = cfg;
    }

    function setAssets(
        string[] calldata symbols_,
        address[] calldata erc20s_,
        AggregatorV3Interface[] calldata priceFeeds_
    ) external override onlyOwner {
        uint256 length = erc20s_.length;
        require(
            !(length != erc20s_.length || length != priceFeeds_.length),
            "LENGTH_MISMATCH"
        );
        string memory symbol;
        for (uint256 i; i < length; ) {
            symbol = symbols_[i];
            _supportTokens[i] = symbol;
            _assets[symbol] = Asset(erc20s_[i], priceFeeds_[i]);

            unchecked {
                ++i;
            }
        }
    }

    function openSeri(
        uint256 seri_,
        uint256 price_,
        uint256 postPrice_,
        uint256 max2sale_,
        uint256 initPrize_
    ) external override onlyOwner {
        require(price_ >= postPrice_, "INVALID_PARAMS");

        Seri memory seri = _series[seri_];
        require(seri.embededInfo == 0, "EXISTED");

        Config memory cfg = _config;

        if (initPrize_ != 0) {
            uint256 currentCOSeri = cfg.currentCOSeriId;
            require(
                currentCOSeri == 0 || _series[currentCOSeri].status != 0,
                "CO_OPENING"
            );
            __transfer(
                cfg.initCOAssetAddr,
                _msgSender(),
                address(this),
                initPrize_
            );
            seri.seriType = true;
            _config.currentCOSeriId = uint96(seri_);
        }
        seri.embededInfo = SeriLib.encode(
            price_,
            max2sale_,
            postPrice_,
            initPrize_,
            cfg.expiredPeriod
        );

        _series[seri_] = seri;

        emit OpenSeri(seri_, seri.seriType ? 2 : 1);
    }

    function openResult(
        uint256 seri_,
        bool isWin_,
        uint256 _totalWin,
        uint256 timestamp_,
        string calldata result_,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override onlyOwner {
        Seri memory seri = _series[seri_];
        require(seri.status == 1, "NOT_CLOSE");
        Config memory cfg = _config;
        require(timestamp_ > cfg.currentSignTime, _INVALID_TIMESTAMP);
        require(
            ECDSA.recover(
                keccak256(
                    abi.encodePacked(
                        "\x19Ethereum Signed Message:\n32",
                        keccak256(abi.encodePacked(timestamp_, result_))
                    )
                ),
                v,
                r,
                s
            ) == cfg.verifier,
            _INVALID_SIGNATURE
        );

        if (isWin_) {
            seri.status = 2;
            seri.totalWin = uint32(_totalWin);
        } else {
            seri.status = 3;
            __transferRemainAsset(seri_, cfg, _assetIndices[seri_]);
            if (seri.seriType)
                __transfer(
                    cfg.initCOAssetAddr,
                    address(this),
                    cfg.carryOverAddr,
                    seri.embededInfo.initPrize()
                );
        }
        seri.endTime = block.timestamp;
        seri.result = result_;

        _series[seri_] = seri;
        _config.currentSignTime = uint96(timestamp_);

        emit OpenResult(seri_, isWin_);
    }

    function closeSeri(uint256 seri_) external override onlyOwner {
        Seri memory seri = _series[seri_];
        require(seri.status == 0, "NOT_OPEN");
        require(seri.numSold == seri.embededInfo.max2Sale(), "NOT_SOLD_OUT");
        delete _series[seri_];
        emit CloseSeri(seri_, block.timestamp);
    }

    // function ticket2Asset(uint256 seri_, string memory _symbol)
    //     internal
    //     view
    //     returns (uint256)
    // {
    //     return
    //         (_series[seri_].embededInfo.price() * 1 ether) /
    //         getLatestPrice(_symbol);
    // }

    // function asset2USD(string memory symbol_, uint256 amount_)
    //     internal
    //     view
    //     returns (uint256)
    // {
    //     return (amount_ * getLatestPrice(symbol_)) / 1 ether;
    // }

    // function asset2USD(string memory _symbol) internal view returns (uint256) {
    //     return getLatestPrice(_symbol);
    // }

    function getLatestPrice(string memory symbol_)
        internal
        view
        returns (uint256)
    {
        (, int256 _price, , , ) = _assets[symbol_].priceFeed.latestRoundData();
        return uint256(_price * 1e10);
    }

    function seriAssetRemain(uint256 _seri, uint256 _asset)
        external
        view
        override
        returns (uint256)
    {
        return _balances[_seri][_asset].remain;
    }

    function getUserTickets(uint256 _seri, address _user)
        external
        view
        override
        returns (string[] memory)
    {
        return _userTickets[_seri][_user];
    }

    function getSeriWinners(uint256 _seri)
        external
        view
        override
        returns (uint256[] memory)
    {
        return _winners[_seri];
    }

    function getSeriesAssets(uint256 _seri)
        external
        view
        override
        returns (uint256[] memory)
    {
        return _assetIndices[_seri];
    }

    function getAsset(string memory _symbol)
        external
        view
        override
        returns (
            string memory,
            address,
            AggregatorV3Interface
        )
    {
        Asset memory _asset = _assets[_symbol];
        return (_symbol, _asset.asset, _asset.priceFeed);
    }

    function getPriceFeeds() external view override returns (string[] memory) {
        return _supportTokens;
    }

    function currentSignTime() external view override returns (uint256) {
        return _config.currentSignTime;
    }

    function currentCarryOverSeri() external view override returns (uint256) {
        return _config.currentCOSeriId;
    }

    function signer() external view override returns (address) {
        return _config.verifier;
    }

    function postAddress() external view override returns (address payable) {
        return payable(_config.postAddr);
    }

    function stake() external view override returns (address payable) {
        return payable(_config.stakeAddr);
    }

    function purchase() external view override returns (address payable) {
        return payable(_config.purchaseAddr);
    }

    function affiliateAddress()
        external
        view
        override
        returns (address payable)
    {
        return payable(_config.purchaseAddr);
    }

    function operator() external view override returns (address payable) {
        return payable(_config.operatorAddr);
    }

    function carryOver() external view override returns (address payable) {
        return payable(_config.carryOverAddr);
    }

    function initCarryOverAsset() external view override returns (IERC20) {
        return IERC20(_config.initCOAssetAddr);
    }

    function nft() external view override returns (INFT) {
        return _config.nft;
    }

    function share2Stake() external view override returns (uint256) {
        return _config.stakeAmt;
    }

    function share2Purchase() external view override returns (uint256) {
        return _config.purchaseAmt;
    }

    function share2Affiliate() external view override returns (uint256) {
        return _config.affiliateAmt;
    }

    function share2Operator() external view override returns (uint256) {
        return _config.operatorAmt;
    }

    function share2AffiliateCO() external view override returns (uint256) {
        return _config.affiliateCOAmt;
    }

    function share2OperatorCO() external view override returns (uint256) {
        return _config.operatorCOAmt;
    }

    function expiredPeriod() external view override returns (uint256) {
        return _config.expiredPeriod;
    }

    function seriExpiredPeriod(uint256 seri_)
        external
        view
        override
        returns (uint256)
    {
        return _series[seri_].embededInfo.expiredPeriod();
    }

    function postPrices(uint256 seri_)
        external
        view
        override
        returns (uint256)
    {
        return _series[seri_].embededInfo.postPrice();
    }

    function currentTurn(uint256 seri_)
        external
        view
        override
        returns (uint256)
    {
        return _series[seri_].nonce;
    }

    function series(uint256 seri_)
        external
        view
        override
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
        )
    {
        Seri memory seri = _series[seri_];
        price = seri.embededInfo.price();
        soldTicket = seri.numSold;
        result = seri.result;
        status = seri.status;
        endTime = seri.endTime;
        takeAssetExpired = seri.takeAssetExpired;
        max2sale = seri.embededInfo.max2Sale();
        totalWin = seri.totalWin;
        seriType = seri.seriType ? 2 : 1;
        initPrize = seri.embededInfo.initPrize();
        initPrizeTaken = seri.initPrizeTaken;
        winInitPrize = seri.winInitPrice;
    }

    function totalPrize(uint256 seri_)
        external
        view
        override
        returns (uint256 _prize)
    {
        uint256[] memory assetIndices = _assetIndices[seri_];
        uint256 length = assetIndices.length;
        AssetBalance memory assetBalance;
        for (uint256 i = 0; i < length; ) {
            assetBalance = _balances[seri_][assetIndices[i]];
            if (assetBalance.remain > 0) {
                //string memory symbol = _supportTokens[assetIndices[i]];
                _prize +=
                    (assetBalance.remain *
                        getLatestPrice(_supportTokens[assetIndices[i]])) /
                    1 ether;
            }
            unchecked {
                ++i;
            }
        }
    }

    function _sendNFT(
        INFT nft_,
        uint256 seri_,
        uint256 startTime_,
        address[] memory winners_,
        string[] memory assets_,
        uint256[][] memory buyTickets_
    ) private {
        uint256 winnerLength = winners_.length;
        require(100 >= winnerLength, "MAX_LOOP");

        uint256 tokenID;
        uint256 totalWin = _series[seri_].totalWin;
        string memory result = _series[seri_].result;
        address winner;
        for (uint256 i; i < winnerLength; ) {
            winner = winners_[i];
            for (uint256 j; j < buyTickets_[i].length; ) {
                tokenID = __mintNFT(
                    nft_,
                    winner,
                    seri_,
                    startTime_,
                    totalWin,
                    result,
                    assets_[i]
                );
                _winners[seri_].push(tokenID);

                userTicketsWon[seri_][winner][buyTickets_[i][j]] = tokenID;
                userTicketsWonb[seri_][winner][tokenID] = buyTickets_[i][j];
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    function __mintNFT(
        INFT nft_,
        address to_,
        uint256 seri_,
        uint256 startTime_,
        uint256 winTickets_,
        string memory result_,
        string memory asset_
    ) private returns (uint256) {
        return
            nft_.mint(
                to_,
                seri_,
                startTime_,
                block.timestamp,
                result_,
                2,
                winTickets_,
                to_,
                1,
                asset_
            );
    }

    function __transferRemainAsset(
        uint256 seri_,
        Config memory cfg_,
        uint256[] memory assetIndices_
    ) private {
        uint256 assetIdx;
        uint256 length = assetIndices_.length;
        uint256 remain;
        for (uint256 i; i < length; ) {
            assetIdx = assetIndices_[i];
            remain = _balances[seri_][assetIdx].remain;
            delete _balances[seri_][assetIdx].remain;
            __transfer(
                _assets[_supportTokens[assetIdx]].asset,
                address(this),
                cfg_.carryOverAddr,
                remain
            );

            unchecked {
                ++i;
            }
        }
    }

    function __transfer(
        address asset_,
        address from_,
        address to_,
        uint256 amount_
    ) private {
        if (amount_ == 0) return;
        if (asset_ == address(0)) {
            (bool ok, ) = payable(to_).call{value: amount_}("");
            require(ok, "INSUFICIENT_BALANCE");
        } else IERC20(asset_).safeTransferFrom(from_, to_, amount_);
    }
}
