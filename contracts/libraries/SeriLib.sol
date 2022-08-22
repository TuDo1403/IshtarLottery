// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

library SeriLib {
    // EMBEDED_INFO = EXPIRED_PERIOD + INIT_PRIZE + POST_PRIZE + MAX_2_SALE + PRICE
    uint256 private constant _N_BIT = 51;
    uint256 private constant _MAX = 2251799813685247;

    uint256 private constant _POST_PRICE_SHIFT = 102;
    uint256 private constant _INIT_PRIZE_SHIFT = 153;
    uint256 private constant _EXPIRED_PERIOD_SHIFT = 204;

    uint256 private constant _MAX_2_SALE_MASK = 5070602400912917605986812821503;
    uint256 private constant _POST_PRICE_MASK =
        11417981541647679048466287755595961091061972991;
    uint256 private constant _INIT_PRIZE_MASK =
        25711008708143844408671393477458601640355247900524685364822015;

    function encode(
        uint256 price_,
        uint256 max2Sale_,
        uint256 postPrice_,
        uint256 initPrize_,
        uint256 expiredPeriod_
    ) internal pure returns (uint256) {
        require(
            _MAX >= price_ &&
                _MAX >= max2Sale_ &&
                _MAX >= postPrice_ &&
                _MAX >= initPrize_ &&
                _MAX >= expiredPeriod_,
            "OVERFLOW"
        );
        unchecked {
            return
                price_ |
                (max2Sale_ << _N_BIT) |
                (postPrice_ << _POST_PRICE_SHIFT) |
                (initPrize_ << _INIT_PRIZE_SHIFT) |
                (expiredPeriod_ << _EXPIRED_PERIOD_SHIFT);
        }
    }

    function price(uint256 embededInfo_) internal pure returns (uint256) {
        return embededInfo_ & _MAX;
    }

    function postPrice(uint256 embededInfo_) internal pure returns (uint256) {
        unchecked {
            return
                ((embededInfo_ & _POST_PRICE_MASK) >> _POST_PRICE_SHIFT) & _MAX;
        }
    }

    function initPrize(uint256 embededInfo_) internal pure returns (uint256) {
        unchecked {
            return
                ((embededInfo_ & _INIT_PRIZE_MASK) >> _INIT_PRIZE_SHIFT) & _MAX;
        }
    }

    function max2Sale(uint256 embededInfo_) internal pure returns (uint256) {
        unchecked {
            return ((embededInfo_ & _MAX_2_SALE_MASK) >> _N_BIT) & _MAX;
        }
    }

    function expiredPeriod(uint256 embededInfo_)
        internal
        pure
        returns (uint256)
    {
        unchecked {
            return embededInfo_ >> _EXPIRED_PERIOD_SHIFT;
        }
    }
}
