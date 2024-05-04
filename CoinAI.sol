// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CoinAI is IERC20 {

    string public constant name = "CoinAI";
    string public constant symbol = "CAI";
    uint8 public constant decimals = 18;
    uint256 public totalSupply; 
    uint256 public maxSupply = 1000000000 ether; //1b
    address private _owner;

    mapping(address => uint256) balances;
    mapping(address => mapping (address => uint256)) allowed;

    constructor() {
        _owner = msg.sender;
    }

    /**
    * @dev Throws if called by any account other than the owner.
    */
    modifier onlyOwner() {
        require(_owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }


    function balanceOf(address tokenOwner) public override view returns (uint256) {
        return balances[tokenOwner];
    }

    function transfer(address receiver, uint256 numTokens) public override returns (bool) {
        require(numTokens <= balances[msg.sender]);
        balances[msg.sender] = balances[msg.sender]-numTokens;
        balances[receiver] = balances[receiver]+numTokens;
        emit Transfer(msg.sender, receiver, numTokens);
        return true;
    }

    function approve(address delegate, uint256 numTokens) public override returns (bool) {
        allowed[msg.sender][delegate] = numTokens;
        emit Approval(msg.sender, delegate, numTokens);
        return true;
    }

    function allowance(address owner, address delegate) public override view returns (uint) {
        return allowed[owner][delegate];
    }

    function transferFrom(address owner, address buyer, uint256 numTokens) public override returns (bool) {
        require(numTokens <= balances[owner]);
        require(numTokens <= allowed[owner][msg.sender]);

        balances[owner] = balances[owner]-numTokens;
        allowed[owner][msg.sender] = allowed[owner][msg.sender]-numTokens;
        balances[buyer] = balances[buyer]+numTokens;
        emit Transfer(owner, buyer, numTokens);
        return true;
    }

    function transferOwnership(address newOwner) public onlyOwner {                
        _owner = newOwner;
    }

    function mint(uint256 amount) public onlyOwner {
        require(totalSupply + amount <= maxSupply, "total supply exceeds max supply");
        totalSupply += amount;
        balances[msg.sender] += amount;
        emit Transfer(address(0), msg.sender, amount);
    }

    function getOwner() external view returns (address) {
        return _owner;
    }
}
