pragma solidity ^0.4.11;

import "./RareCoin.sol";
import "./SafeMath.sol";

/**
 * @title Auction contract for RareCoin
 */
contract RareCoinAuction {
    using SafeMath for uint256;

    //  Block number for the end of the auction
    uint internal _auctionEnd;

    //  Toggles the auction from allowing bids to allowing withdrawals
    bool internal _ended;

    //  Address of auction beneficiary
    address internal _beneficiary;

    //  Used to only allow the beneficiary to withdraw once
    bool internal _beneficiaryWithdrawn;

    //  Value of bid #100
    uint internal _lowestBid;

    //  Used for details of the top 100 bids
    struct Bidder {
        uint bid;
        address bidderAddress;
    }

    //  Used for details of every bid
    struct BidDetails {
        uint value;
        uint lastTime;
    }

    //  Contains details of every bid
    mapping(address => BidDetails) internal _bidders;

    //  Static array recording highest 100 bidders in sorted order
    Bidder[100] internal _topBids;

    //  Address of coin contract
    address internal _rcContract;
    bool[100] internal _coinWithdrawn;

    event NewBid(address bidder, uint amount);

    event TopThreeChanged(
        address first, uint firstBid,
        address second, uint secondBid,
        address third, uint thirdBid
    );

    event AuctionEnded(
        address first, uint firstBid,
        address second, uint secondBid,
        address third, uint thirdBid
    );

  /**
   * @notice Constructor
   * @param biddingTime Number of blocks auction should last for
   */
    function RareCoinAuction(uint biddingTime) public {
        _auctionEnd = block.number + biddingTime;
        _beneficiary = msg.sender;
    }

  /**
   * @notice Connect the auction contract to the RareCoin contract
   * @param rcContractAddress Address of RareCoin contract
   */
    function setRCContractAddress(address rcContractAddress) public {
        require(msg.sender == _beneficiary);
        require(_rcContract == address(0));

        _rcContract = rcContractAddress;
    }

  /**
   * @notice Bid `(msg.value)` ether for a chance of winning a RareCoin
   * @dev This will be rejected if the bid will not end up in the top 100
   */
    function bid() external payable {
        require(block.number < _auctionEnd);

        uint proposedBid = _bidders[msg.sender].value.add(msg.value);

        //  No point in accepting a bid if it isn't going to result in a chance of a RareCoin
        require(proposedBid > _lowestBid);

        //  Check whether the bidder is already in the top 100.  Note, not enough to check currentBid > _lowestBid
        //  since there can be multiple bids of the same value
        uint startPos = 99;
        if (_bidders[msg.sender].value >= _lowestBid) {
            //  Note: loop condition relies on overflow
            for (uint i = 99; i < 100; --i) {
                if (_topBids[i].bidderAddress == msg.sender) {
                    startPos = i;
                    break;
                }
            }
        }

        //  Do one pass of an insertion sort to maintain _topBids in order
        uint endPos;
        for (uint j = startPos; j < 100; --j) {
            if (j != 0 && proposedBid > _topBids[j - 1].bid) {
                _topBids[j] = _topBids[j - 1];
            } else {
                _topBids[j].bid = proposedBid;
                _topBids[j].bidderAddress = msg.sender;
                endPos = j;
                break;
            }
        }

        //  Update _bidders with new information
        _bidders[msg.sender].value = proposedBid;
        _bidders[msg.sender].lastTime = now;

        //  Record bid of 100th place bidder for next time
        _lowestBid = _topBids[99].bid;

        //  If top 3 bidders changes, log event to blockchain
        if (endPos < 3) {
            TopThreeChanged(
                _topBids[0].bidderAddress, _topBids[0].bid,
                _topBids[1].bidderAddress, _topBids[1].bid,
                _topBids[2].bidderAddress, _topBids[2].bid
            );
        }

        NewBid(msg.sender, _bidders[msg.sender].value);

    }

  /**
   * @notice Withdraw the total of the top 100 bids into the beneficiary account
   */
    function beneficiaryWithdraw() external {
        require(msg.sender == _beneficiary);
        require(_ended);
        require(!_beneficiaryWithdrawn);

        uint total = 0;
        for (uint i = 0; i < 100; ++i) {
            total = total.add(_topBids[i].bid);
        }

        _beneficiaryWithdrawn = true;

        _beneficiary.transfer(total);
    }

  /**
   * @notice Withdraw your deposit at the end of the auction
   * @return Whether the withdrawal succeeded
   */
    function withdraw() external returns (bool) {
        require(_ended);

        //  The user should not be able to withdraw if they are in the top 100 bids
        //  Cannot simply require(proposedBid > _lowestBid) since bid #100 can be
        //  the same value as bid #101
        for (uint i = 0; i < 100; ++i) {
            require(_topBids[i].bidderAddress != msg.sender);
        }

        uint amount = _bidders[msg.sender].value;
        if (amount > 0) {
            _bidders[msg.sender].value = 0;
            msg.sender.transfer(amount);
        }
        return true;
    }

  /**
   * @notice Withdraw your RareCoin if you are in the top 100 bidders at the end of the auction
   * @dev This function creates the RareCoin token in the corresponding address.  Can be called
   * by anyone.  Note that it is the coin number (1 based) not array index that is supplied
   * @param tokenNumber The number of the RareCoin to withdraw.
   * @return Whether The auction succeeded
   */
    function withdrawToken(uint tokenNumber) external returns (bool) {
        require(_ended);
        require(!_coinWithdrawn[tokenNumber - 1]);

        _coinWithdrawn[tokenNumber - 1] = true;

        RareCoin(_rcContract).CreateToken(_topBids[tokenNumber - 1].bidderAddress, tokenNumber);

        return true;
    }

  /**
   * @notice End the auction, allowing the withdrawal of ether and tokens
   */
    function endAuction() external {
        require(block.number >= _auctionEnd);
        require(!_ended);

        _ended = true;
        AuctionEnded(
            _topBids[0].bidderAddress, _topBids[0].bid,
            _topBids[1].bidderAddress, _topBids[1].bid,
            _topBids[2].bidderAddress, _topBids[2].bid
        );
    }

  /**
   * @notice Returns the value of `(_addr)`'s bid and the time it occurred
   * @param _addr Address to query for balance
   * @return Tuple (value, bidTime)
   */
    function getBidDetails(address _addr) external view returns (uint, uint) {
        return (_bidders[_addr].value, _bidders[_addr].lastTime);
    }

  /**
   * @notice Returns a sorted array of the top 100 bidders
   * @return The top 100 bidders, sorted by bid
   */
    function getTopBidders() external view returns (address[100]) {
        address[100] memory tempArray;

        for (uint i = 0; i < 100; ++i) {
            tempArray[i] = _topBids[i].bidderAddress;
        }

        return tempArray;
    }

  /**
   * @notice Get the block the auction ends on
   * @return The block the auction ends on
   */
    function getAuctionEnd() external view returns (uint) {
        return _auctionEnd;
    }

  /**
   * @notice Get whether the auction has ended
   * @return Whether the auction has ended
   */
    function getEnded() external view returns (bool) {
        return _ended;
    }

  /**
   * @notice Get the address of the RareCoin contract
   * @return The address of the RareCoin contract
   */
    function getRareCoinAddress() external view returns (address) {
        return _rcContract;
    }
}
