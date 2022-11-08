// SPDX-License_Identifier: MIT

pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Context.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeMath.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


contract Presale is Context, ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // The token being sold
    IERC20 private _token;

    IERC20 private _usdt;
    IERC20 private _bnb;

    AggregatorV3Interface internal priceFeedEth;
    AggregatorV3Interface internal priceFeedUsdt;
    AggregatorV3Interface internal priceFeedBnb;

    // Address where funds are collected
    address payable private _wallet;

    address private _tokenWallet;


    // How many token units a buyer gets per wei.
    // The rate is the conversion between wei and the smallest and indivisible token unit.
    // So, if you are using a rate of 1 with a ERC20Detailed token with 3 decimals called TOK
    // 1 wei will give you 1 unit, or 0.001 TOK.
    uint256 private _rate;

    // Amount of wei raised
    uint256 private _weiRaised;

    uint256 private _usdtRaised;

    uint256 private _bnbRaised;

    bool private _finalized = false;

    mapping(address => uint256) public contribution; 

    /**
     * Event for token purchase logging
     * @param purchaser who paid for the tokens
     * @param beneficiary who got the tokens
     * @param value weis paid for purchase
     * @param amount amount of tokens purchased
     */
    event TokensPurchased(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);

    /**
     * @param rate Number of token units a buyer gets per wei
     * @dev The rate is the conversion between wei and the smallest and indivisible
     * token unit. So, if you are using a rate of 1 with a ERC20Detailed token
     * with 3 decimals called TOK, 1 wei will give you 1 unit, or 0.001 TOK.
     * @param wallet Address where collected funds will be forwarded to
     * @param token Address of the token being sold
     */
    constructor (
        uint256 rate, 
        address payable wallet, 
        IERC20 token, 
        address tokenWallet, 
        IERC20 usdt, 
        IERC20 bnb
        ) public {
        require(rate > 0, "Presale: rate is 0");
        require(wallet != address(0), "Presale: wallet is the zero address");
        require(address(token) != address(0), "Presale: token is the zero address");
        require(tokenWallet != address(0), "Presale: token wallet is the zero address");

        _rate = rate;
        _wallet = wallet;
        _token = token;
        _tokenWallet = tokenWallet;
        _usdt = usdt;
        _bnb = bnb;
        priceFeedEth = AggregatorV3Interface(0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e);
        priceFeedUsdt = AggregatorV3Interface(0xAb5c49580294Aff77670F839ea425f5b78ab3Ae7);
        priceFeedBnb = AggregatorV3Interface(0xAb5c49580294Aff77670F839ea425f5b78ab3Ae7);
    }

    /**
     * @dev fallback function ***DO NOT OVERRIDE***
     * Note that other contracts will transfer funds with a base gas stipend
     * of 2300, which is not enough to call buyTokens. Consider calling
     * buyTokens directly when purchasing tokens from a contract.
     */
    function () external payable {
        buyTokens(_msgSender());
    }

    /**
     * @return the token being sold.
     */
    function token() public view returns (IERC20) {
        return _token;
    }

    /**
     * @return the address where funds are collected.
     */
    function wallet() public view returns (address payable) {
        return _wallet;
    }

    /**
     * @return the number of token units a buyer gets per wei.
     */
    function rate() public view returns (uint256) {
        return _rate;
    }

    function isFinalized() public view returns (bool) {
        return _finalized;
    }

    /**
     * @return the amount of wei raised.
     */
    function weiRaised() public view returns (uint256) {
        return _weiRaised;
    }

    function usdtRaised() public view returns (uint256) {
        return _usdtRaised;
    }

    function bnbRaised() public view returns (uint256) {
        return _bnbRaised;
    }

    /**
     * @dev low level token purchase ***DO NOT OVERRIDE***
     * This function has a non-reentrancy guard, so it shouldn't be called by
     * another `nonReentrant` function.
     * @param beneficiary Recipient of the token purchase
     */
    function buyTokens(address beneficiary) public nonReentrant payable {
        uint256 weiAmount = msg.value;
        _preValidatePurchase(beneficiary, weiAmount);

        // calculate token amount to be created
        uint256 tokens = _getTokenAmount(weiAmount);

        // update state
        _weiRaised = _weiRaised.add(weiAmount);

        contribution[_msgSender()] = tokens;

        emit TokensPurchased(_msgSender(), beneficiary, weiAmount, tokens);

        _forwardFunds();
    }

    function buyTokensFromUsdt(address beneficiary, uint256 amount) public nonReentrant {
        uint256 weiAmount = amount;
        _preValidatePurchase(beneficiary, weiAmount);
        require(_usdt.transferFrom(_msgSender(), _wallet, weiAmount), 'USDT Transfer Failed');

        // calculate token amount to be created
        uint256 tokens = _getTokenFromUsdt(weiAmount);

        // update state
        _usdtRaised = _usdtRaised.add(weiAmount);

        contribution[_msgSender()] = tokens;

        emit TokensPurchased(_msgSender(), beneficiary, weiAmount, tokens);

    }

    function buyTokensFromBnb(address beneficiary, uint256 amount) public nonReentrant {
        uint256 weiAmount = amount;
        _preValidatePurchase(beneficiary, weiAmount);
        require(_bnb.transferFrom(_msgSender(), _wallet, weiAmount), 'USDT Transfer Failed');

        // calculate token amount to be created
        uint256 tokens = _getTokenFromBnb(weiAmount);

        // update state
        _bnbRaised = _bnbRaised.add(weiAmount);

        contribution[_msgSender()] = tokens;

        emit TokensPurchased(_msgSender(), beneficiary, weiAmount, tokens);

    }


    function claimTokens() external nonReentrant {
        require(isFinalized(), 'Presale: Presale is not finished yet');
        uint256 claimedTokens = contribution[_msgSender()];
        contribution[_msgSender()] = 0;
        _token.transferFrom(_tokenWallet, _msgSender(), claimedTokens);
    }

    /**
     * @dev Validation of an incoming purchase. Use require statements to revert state when conditions are not met.
     * Use `super` in contracts that inherit from Crowdsale to extend their validations.
     * Example from CappedCrowdsale.sol's _preValidatePurchase method:
     *     super._preValidatePurchase(beneficiary, weiAmount);
     *     require(weiRaised().add(weiAmount) <= cap);
     * @param beneficiary Address performing the token purchase
     * @param weiAmount Value in wei involved in the purchase
     */
    function _preValidatePurchase(address beneficiary, uint256 weiAmount) internal view {
        require(beneficiary != address(0), "Crowdsale: beneficiary is the zero address");
        require(weiAmount != 0, "Crowdsale: weiAmount is 0");
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
    }

    /**
     * @dev Override to extend the way in which ether is converted to tokens.
     * @param weiAmount Value in wei to be converted into tokens
     * @return Number of tokens that can be purchased with the specified _weiAmount
     */
    function _getTokenAmount(uint256 weiAmount) internal view returns (uint256) {
        return weiAmount.mul(_rate);
    }

    function _getTokenFromUsdt(uint256 weiAmount) internal view returns (uint256) {
        return weiAmount.mul(_rate);
    }

    function _getTokenFromBnb(uint256 weiAmount) internal view returns (uint256) {
        return weiAmount.mul(_rate);
    }

    /**
     * @dev Determines how ETH is stored/forwarded on purchases.
     */
    function _forwardFunds() internal {
        _wallet.transfer(msg.value);
    }

    function tokenWallet() public view returns (address) {
        return _tokenWallet;
    }

    function remainingTokens() public view returns (uint256) {
        return Math.min(token().balanceOf(_tokenWallet), token().allowance(_tokenWallet, address(this)));
    }

    function finalizePresale() external onlyOwner {
        _finalized = true;
    }

    function getLatestPriceEth() public view returns (int) {
        (
            /*uint80 roundID*/,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeedEth.latestRoundData();
        return price;
    }

    function getLatestPriceUsdt() public view returns (int) {
        (
            /*uint80 roundID*/,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeedUsdt.latestRoundData();
        return price;
    }

    function getLatestPriceBnb() public view returns (int) {
        (
            /*uint80 roundID*/,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeedBnb.latestRoundData();
        return price;
    }


}
