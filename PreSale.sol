// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract PreSale is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable {  
    uint256 public BASE_MULTIPLIER;
    uint256 public MONTH;    

    struct Presale {
        address saleToken;
        uint256 startTime;
        uint256 endTime;
        uint256 price;
        uint256 tokensToSell;
        uint256 baseDecimals;
        uint256 inSale;
        uint256 vestingStartTime;
        uint256 vestingPeriod;
    }

    struct Vesting {
        uint256 totalAmount;
        uint256 claimedAmount;
    }

    AggregatorV3Interface internal aggregatorInterface; // https://docs.chain.link/data-feeds/price-feeds/addresses/?network=bnb-chain&page=1 => (BNB / USD)

    uint256 public refRate; //10: 10%
    bool public paused;
    Presale public presale;
    mapping(address => Vesting) public userVesting;

    event PresaleCreated(
        uint256 _totalTokens,
        uint256 _startTime,
        uint256 _endTime
    );

    event PresaleUpdated(
        bytes32 indexed key,
        uint256 prevValue,
        uint256 newValue,
        uint256 timestamp
    );

    event TokensBought(
        address indexed user,
        uint256 tokensBought,
        uint256 amountPaid,
        uint256 timestamp
    );

    event TokensClaimed(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );

    event PresaleTokenAddressUpdated(
        address indexed prevValue,
        address indexed newValue,
        uint256 timestamp
    );

    event PresalePaused(uint256 timestamp);
    event PresaleUnpaused(uint256 timestamp);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    /**
     * @dev Initializes the contract and sets key parameters
     * @param _oracle Oracle contract to fetch ETH/USDT price
     */
    function initialize(address _oracle) external initializer {
        require(_oracle != address(0), "Zero aggregator address");
        __Ownable_init_unchained();
        __ReentrancyGuard_init_unchained();
        aggregatorInterface = AggregatorV3Interface(_oracle);        
        BASE_MULTIPLIER = (10**18);
        MONTH = (30 * 24 * 3600);
        refRate = 10;
    }

    /**
     * @dev Creates a new presale
     * @param _startTime start time of the sale
     * @param _endTime end time of the sale
     * @param _price Per token price multiplied by (10**18)
     * @param _tokensToSell No of tokens to sell without denomination. If 1 million tokens to be sold then - 1_000_000 has to be passed
     * @param _baseDecimals No of decimals for the token. (10**18), for 18 decimal token
     * @param _vestingStartTime Start time for the vesting - UNIX timestamp    
     * @param _vestingPeriod Total vesting period(after vesting _vestingStartTime) in seconds
     */
    function createPresale(
        uint256 _startTime,
        uint256 _endTime,
        uint256 _price,
        uint256 _tokensToSell,
        uint256 _baseDecimals,
        uint256 _vestingStartTime,
        uint256 _vestingPeriod
    ) external onlyOwner {
        require(  _endTime > _startTime, "Invalid time");
        require(_price > 0, "Zero price");
        require(_tokensToSell > 0, "Zero tokens to sell");
        require(_baseDecimals > 0, "Zero decimals for the token");
        require(
            _vestingStartTime >= _endTime,
            "Vesting starts before Presale ends"
        );

        presale = Presale(
            address(0),
            _startTime,
            _endTime,
            _price,
            _tokensToSell,
            _baseDecimals,
            _tokensToSell,
            _vestingStartTime,
            _vestingPeriod
        );

        emit PresaleCreated(_tokensToSell, _startTime, _endTime);
    }

    /**
     * @dev To update the sale times
     * @param _startTime New start time
     * @param _endTime New end time
     */
    function changeSaleTimes(
        uint256 _startTime,
        uint256 _endTime
    ) external onlyOwner {
        require(_startTime > 0 || _endTime > 0, "Invalid parameters");
        if (_startTime > 0) {
            uint256 prevValue = presale.startTime;
            presale.startTime = _startTime;
            emit PresaleUpdated(
                bytes32("START"),
                prevValue,
                _startTime,
                block.timestamp
            );
        }

        if (_endTime > 0) {            
            uint256 prevValue = presale.endTime;
            presale.endTime = _endTime;
            emit PresaleUpdated(
                bytes32("END"),
                prevValue,
                _endTime,
                block.timestamp
            );
        }
    }

    /**
     * @dev To update the vesting start time
     * @param _vestingStartTime New vesting start time
     */
    function changeVestingStartTime(uint256 _vestingStartTime)
        external
        onlyOwner
    {
        uint256 prevValue = presale.vestingStartTime;
        presale.vestingStartTime = _vestingStartTime;
        emit PresaleUpdated(
            bytes32("VESTING_START_TIME"),
            prevValue,
            _vestingStartTime,
            block.timestamp
        );
    }

    /**
     * @dev To update the sale token address
     * @param _newAddress Sale token address
     */
    function changeSaleTokenAddress(address _newAddress)
        external
        onlyOwner
    {
        require(_newAddress != address(0), "Zero token address");
        address prevValue = presale.saleToken;
        presale.saleToken = _newAddress;
        emit PresaleTokenAddressUpdated(
            prevValue,
            _newAddress,
            block.timestamp
        );
    }

    /**
     * @dev To update the price
     * @param _newPrice New sale price of the token
     */
    function changePrice(uint256 _newPrice)
        external
        onlyOwner
    {
        require(_newPrice > 0, "Zero price");
        
        uint256 prevValue = presale.price;
        presale.price = _newPrice;
        emit PresaleUpdated(
            bytes32("PRICE"),
            prevValue,
            _newPrice,
            block.timestamp
        );
    }


    /**
     * @dev To pause the presale
     */
    function pausePresale() external onlyOwner {
        require(!paused, "Already paused");
        paused = true;
        emit PresalePaused(block.timestamp);
    }

    /**
     * @dev To unpause the presale
     */
    function unPausePresale()
        external
        onlyOwner
    {
        require(paused, "Not paused");
        paused = false;
        emit PresaleUnpaused(block.timestamp);
    }

    /**
     * @dev To get latest ethereum price in 10**18 format
     */
    function getLatestPrice() public view returns (uint256) {
        (, int256 price, , , ) = aggregatorInterface.latestRoundData();
        price = (price * (10**10));
        return uint256(price);
    }

    modifier checkSaleState(uint256 amount) {
        require(
            block.timestamp >= presale.startTime &&
                block.timestamp <= presale.endTime,
            "Invalid time for buying"
        );
        require(
            amount > 0 && amount <= presale.inSale,
            "Invalid sale amount"
        );
        _;
    }

    function increaseBalance(address recipient, uint256 amount) internal {        
        if (userVesting[recipient].totalAmount > 0) {
            userVesting[recipient].totalAmount += (amount * presale.baseDecimals);
        } else {
            userVesting[recipient]= Vesting(
                (amount * presale.baseDecimals),
                0
            );
        }
        
    }


    function buyWithEth(address _refer) payable public returns(bool){
        require(!paused, "Presale paused");
        
        uint256 ethAmount = msg.value;
        uint256 amount = ethAmount * getLatestPrice() / BASE_MULTIPLIER / presale.price;
        presale.inSale -= amount;
        
        increaseBalance(_msgSender(), amount);        
        payable(owner()).transfer(ethAmount);
        emit TokensBought(
            _msgSender(),
            amount,
            ethAmount,
            block.timestamp
        );
        
        //referral tokens
        if(refRate > 0 && _msgSender() != _refer && _refer != 0x0000000000000000000000000000000000000000){                        
            uint256 _refAmount = amount * refRate / 100;
            increaseBalance(_refer, _refAmount);  
        }

        return true;
    }


    /**
     * @dev Helper funtion to get ETH price for given amount
     * @param amount No of tokens to buy
     */
    function ethBuyHelper(uint256 amount)
        external
        view
        returns (uint256 ethAmount)
    {
        uint256 usdPrice = amount * presale.price;
        ethAmount = (usdPrice * BASE_MULTIPLIER) / getLatestPrice();
    }


    /**
     * @dev Helper funtion to get claimable tokens for a given presale.
     * @param user User address
     */
    function claimableAmount(address user)
        public
        view
        returns (uint256)
    {
        Vesting memory _user = userVesting[user];
        require(_user.totalAmount > 0, "Nothing to claim");
        uint256 amount = _user.totalAmount - _user.claimedAmount;
        require(amount > 0, "Already claimed");

        if (block.timestamp < presale.vestingStartTime) return 0;
        if (block.timestamp >= presale.vestingStartTime + presale.vestingPeriod) return amount;

        uint256 noOfMonthsPassed = (block.timestamp - presale.vestingStartTime) / MONTH;

        uint256 perMonthClaim = (_user.totalAmount * BASE_MULTIPLIER * MONTH) / presale.vestingPeriod;

        uint256 amountToClaim = (((noOfMonthsPassed +1) * perMonthClaim) / BASE_MULTIPLIER) - _user.claimedAmount;

        return amountToClaim;
    }

    /**
     * @dev To claim tokens from a presale
     * @param user User address
     */
    function claim(address user) public returns (bool) {
        uint256 amount = claimableAmount(user);
        require(amount > 0, "Zero claim amount");
        require(
            presale.saleToken != address(0),
            "Presale token address not set"
        );
        require(
            amount <=
                IERC20Upgradeable(presale.saleToken).balanceOf(
                    address(this)
                ),
            "Not enough tokens in the contract"
        );
        userVesting[user].claimedAmount += amount;
        bool status = IERC20Upgradeable(presale.saleToken).transfer(
            user,
            amount
        );
        require(status, "Token transfer failed");
        emit TokensClaimed(user, amount, block.timestamp);
        return true;
    }

    /**
     * @dev To claim tokens from a presale
     * @param users Array of user addresses
     */
    function claimMultiple(address[] calldata users)
        external
        returns (bool)
    {
        require(users.length > 0, "Zero users length");
        for (uint256 i; i < users.length; i++) {
            require(claim(users[i]), "Claim failed");
        }
        return true;
    }

    function withdraw() public onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
    function withdraw(IERC20Upgradeable token) public onlyOwner {        
        token.transfer(
            msg.sender,
            token.balanceOf(address(this))
        );
    }

    
}