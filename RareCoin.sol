pragma solidity ^0.4.10;
import "./ERC721Token.sol";

contract RareCoin is ERC721Token("RareCoin", "XRC") {
    bool[100] internal _initialized;
    address _auctionContract;

    function RareCoin(address auctionContract) public {
        _auctionContract = auctionContract;
    }

  /**
   * @notice Creates a RareCoin token.  Only callable by the RareCoin auction contract
   * @dev This will fail if not called by the auction contract
   * @param i Coin number
   */
    function CreateToken(address owner, uint i) public {
        require(msg.sender == _auctionContract);
        require(!_initialized[i - 1]);

        _initialized[i - 1] = true;

        _mint(owner, i);
    }
}
