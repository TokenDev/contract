pragma solidity ^0.4.13;
// Max version 0.4.21 on mainnet, not set here to ease truffle use

import "./TokenStore.sol";

contract ZeroExchange {
  address public TOKEN_TRANSFER_PROXY_CONTRACT;
 
  function fillOrKillOrder(address[5] orderAddresses,uint[6] orderValues,uint fillTakerTokenAmount, uint8 v, bytes32 r, bytes32 s) public;
  function getOrderHash(address[5] orderAddresses, uint[6] orderValues) public view returns (bytes32);
  function isValidSignature(address signer,bytes32 hash,uint8 v,bytes32 r,bytes32 s)public view returns (bool);
  function getUnavailableTakerTokenAmount(bytes32 orderHash) public constant returns (uint);
}

contract WETH is Token {
  function deposit() public payable;
  function withdraw(uint wad) public;
}

contract BancorConverter {
  function quickConvert(address[], uint256, uint256) public payable returns (uint256);
  function quickConvertPrioritized(address[] _path, uint256, uint256, uint256, uint8, bytes32, bytes32) public payable returns (uint256);
  function convert(address _fromToken, address _toToken, uint256 _amount, uint256 _minReturn) public returns (uint256);
}

contract BancorNetwork {
  bytes32 public constant BANCOR_GAS_PRICE_LIMIT = "BancorGasPriceLimit"; // inherited from ContractIds
  address public registry;
    
  function convert(address[] _path, uint256 _amount, uint256 _minReturn) public payable returns (uint256);
  function convertFor(address[] _path, uint256 _amount, uint256 _minReturn, address _for) public payable returns (uint256);
  function convertForPrioritized2(
    address[] _path,
    uint256 _amount,
    uint256 _minReturn,
    address _for,
    uint256 _block,
    uint8 _v,
    bytes32 _r,
    bytes32 _s)
    public payable returns (uint256);
}

contract BancorRegistry {
  function addressOf(bytes32 _contractName) public view returns (address);
}

contract BancorGasPriceLimit {
   uint256 public gasPrice;
}

contract AirSwap {
  function fill(address makerAddress, uint makerAmount, address makerToken,
    address takerAddress, uint takerAmount, address takerToken, uint256 expiration, uint256 nonce, uint8 v, bytes32 r, bytes32 s) payable {}
}

contract Kyber {
    
  function trade(
    address src,
    uint256 srcAmount,
    address dest,
    address destAddress,
    uint256 maxDestAmount,
    uint256 minConversionRate,
    address walletId)
    public
    payable
    returns(uint) {}
        
  function swapTokenToEther(address token, uint256 srcAmount, uint256 minConversionRate) public returns(uint) {}
  function swapEtherToToken(address token, uint256 minConversionRate) public payable returns(uint) {}
}

contract InstantTrade is SafeMath, Ownable {

  address public wETH;
  address public etherToken;
  address public zeroX;
  address public proxyZeroX;
  address public bancorNetwork;
  address public airSwap;
  address public kyber;
  uint256 public fee = 1004; // 1004 is 0.4%  (amount * 1004 / 1000)
    
  mapping(address => bool) public allowedFallbacks; // Limit fallback to avoid accidental ETH transfers


  function InstantTrade(address _weth, address _zeroX, address _bancorNet, address _bancorEther, address _airSwap, address _kyber) Ownable() public {
    wETH = _weth;
    zeroX = _zeroX;
    proxyZeroX = ZeroExchange(zeroX).TOKEN_TRANSFER_PROXY_CONTRACT();
    etherToken = _bancorEther;
    bancorNetwork = _bancorNet;
    airSwap = _airSwap;
    kyber = _kyber;
    
    allowedFallbacks[wETH] = true;
    allowedFallbacks[etherToken] = true;
  }
   
  // Only allow incoming ETH from known contracts (Exchange and WETH withdrawals)
  function() public payable {
    require(allowedFallbacks[msg.sender]);
  }
  
  // Set whether the fallback is allowed for an address
  function allowFallback(address _contract, bool _allowed) external onlyOwner {
    allowedFallbacks[_contract] = _allowed;
  }
  

  // Return the remaining volume of a Token Store order in tokenGet
  function availableVolume(address _tokenGet, uint _amountGet, address _tokenGive, uint _amountGive,
    uint _expires, uint _nonce, address _user, uint8 _v, bytes32 _r, bytes32 _s, address _store) external view returns(uint) {
   
    return TokenStore(_store).availableVolume(_tokenGet, _amountGet, _tokenGive, _amountGive,_expires, _nonce, _user, _v, _r, _s);
  }
  
  /* End to end trading in a single call (Token Store, EtherDelta)
     Approve 100.4% tokens or send 100.4% ETH to succeed.
  */
  function instantTrade(address _tokenGet, uint _amountGet, address _tokenGive, uint _amountGive,
    uint _expires, uint _nonce, address _user, uint8 _v, bytes32 _r, bytes32 _s, uint _amount, address _store) external payable {
    
    // Reserve the fee
    uint totalValue = safeMul(_amount, fee) / 1000;
    
    // Paying with ETH or token? Deposit to the actual store
    if (_tokenGet == address(0)) {
    
      // Check amount of ETH sent to make sure it's correct
      require(msg.value == totalValue);
      // Deposit ETH
      TokenStore(_store).deposit.value(totalValue)();
    } else {
    
      // Make sure not to accept ETH when selling tokens
      require(msg.value == 0);
      
      // Assuming user already approved transfer, transfer to this contract
      require(Token(_tokenGet).transferFrom(msg.sender, this, totalValue));
      // Deposit token to the exchange
      require(Token(_tokenGet).approve(_store, totalValue)); 
      TokenStore(_store).depositToken(_tokenGet, totalValue);
    }
    

    // Wrap trade function in a call to avoid a 'throw' (EtherDelta) using up all gas, returns (bool success)
    require(
      address(_store).call(
        bytes4(0x0a19b14a), // precalculated Hash of the line below
        // bytes4(keccak256("trade(address,uint256,address,uint256,uint256,uint256,address,uint8,bytes32,bytes32,uint256)")),  
        _tokenGet, _amountGet, _tokenGive, _amountGive,_expires, _nonce, _user, _v, _r, _s, _amount
      )
    );

    // How much did we end up with
    totalValue = TokenStore(_store).balanceOf(_tokenGive, this);
    uint customerValue = safeMul(_amountGive, _amount) / _amountGet;
    
    // Double check to make sure we aren't somehow losing funds
    require(customerValue <= totalValue);
    
    // Return funds to the user
    if (_tokenGive == address(0)) {
      // Withdraw ETH
      TokenStore(_store).withdraw(totalValue);
      // Send ETH back to sender
      msg.sender.transfer(customerValue);
    } else {
      // Withdraw tokens
      TokenStore(_store).withdrawToken(_tokenGive, totalValue);
      // Send tokens back to sender
      require(Token(_tokenGive).transfer(msg.sender, customerValue));
    }
  }
  

  // Return the remaining volume of a 0x order in takerToken (orderAddresses[1])
  function availableVolume0x(address[5] _orderAddresses, uint[6] _orderValues, uint8 _v, bytes32 _r, bytes32 _s) external view returns(uint) {
    ZeroExchange zrx = ZeroExchange(zeroX);
    bytes32 orderHash = zrx.getOrderHash(_orderAddresses, _orderValues);
    
    // Check whether the order is valid and return available instead of filled tokens
    if(zrx.isValidSignature(_orderAddresses[0], orderHash, _v, _r, _s)) {
      uint filled = zrx.getUnavailableTakerTokenAmount(orderHash);
      if(filled < _orderValues[1]) {
        return (_orderValues[1] - filled);
      } else {
        return 0;
      }
    } else {
      return 0;
    }
  }

  
  /* End to end trading in a single call (0x with open orderbook and 0 ZRX fees)
     Approve 100.4% tokens or send 100.4% ETH to succeed.
  */
  function instantTrade0x(address[5] _orderAddresses, uint[6] _orderValues, uint8 _v, bytes32 _r, bytes32 _s, uint _amount) external payable {
            
    // Require an undefined taker and 0 maker and taker fee
    require(
      _orderAddresses[1] == address(0) 
      && _orderValues[2] == 0 
      && _orderValues[3] == 0
    ); 
    
    WETH wToken = WETH(wETH);
    
    // Reserve the fee
    uint totalValue = safeMul(_amount, fee) / 1000;
    
    // Paying with W-ETH or token? 
    if (/*takerToken*/ _orderAddresses[3] == wETH) {
        
      // Check amount of ETH sent to make sure it's correct
      require(msg.value == totalValue);
      
       // Convert to wrapped ETH and approve for trading
      wToken.deposit.value(msg.value)();
      require(wToken.approve(proxyZeroX, msg.value)); 
    } else {
        
      // Make sure not to accept ETH when selling tokens
      require(msg.value == 0);
      
      Token token = Token(/*takerToken*/ _orderAddresses[3]);
      
      // Assuming user already approved transfer, transfer to this contract
      require(token.transferFrom(msg.sender, this, totalValue));
      // Approve token for trading
      require(token.approve(proxyZeroX, totalValue)); 
    } 
    
    // Trade for the full amount only (revert otherwise)
    ZeroExchange(zeroX).fillOrKillOrder(_orderAddresses, _orderValues, _amount, _v, _r, _s);

    // Check how much did we get and how much should we send back
    uint customerValue = safeMul(_orderValues[0], _amount) / _orderValues[1]; // (takerTokenAmount * _amount) / makerTokenAmount
    
    // Send funds to the user
    if (/*makerToken*/ _orderAddresses[2] == wETH) {
      // Unwrap WETH
      totalValue = wToken.balanceOf(this);
      wToken.withdraw(totalValue);
      // Send ETH back to sender
      msg.sender.transfer(customerValue);
    } else {
      // Send tokens back to sender
      require(Token(_orderAddresses[2]).transfer(msg.sender, customerValue));
    }  
  } 
  
  
  // Return the maximum gas price allowed for non-prioritized Bancor
  function maxGasPriceBancor() external view returns(uint) {
    BancorNetwork bancor = BancorNetwork(bancorNetwork);
    BancorRegistry registry = BancorRegistry(bancor.registry());
    address limitAddress = registry.addressOf(bancor.BANCOR_GAS_PRICE_LIMIT());
    return BancorGasPriceLimit(limitAddress).gasPrice();
  }
  
  

   // End to end trading in a single call through the bancorNetwork contract
   // Approve 100.04% _sourceAmount tokens or send 100.04% _sourceAmount ETH
  function instantTradeBancor(address[] _path, uint _sourceAmount, uint256 _minReturn) external payable {
    
    // Reserve the fee
    uint totalValue = safeMul(_sourceAmount, fee) / 1000;
    uint customerValue;
    
    // Paying with Ethereum or token? 
    if (_path[0] == etherToken) {
    
      // Check amount of ether sent to make sure it's correct
      require(msg.value == totalValue);
     
      //Trade and let Bancor immediately transfer the resulting value to the sender
      customerValue = BancorNetwork(bancorNetwork).convertForPrioritized2.value(_sourceAmount)(_path, _sourceAmount, _minReturn, msg.sender, 0x0, 0x0, 0x0, 0x0);
      require(customerValue >= _minReturn);
      
    } else {
    
      // Make sure not to accept ETH when selling tokens
      require(msg.value == 0);
           
      // get tokens from sender, send to bancorNetwork after removing fee
      require(Token(_path[0]).transferFrom(msg.sender, this, totalValue));
      require(Token(_path[0]).transfer(bancorNetwork, _sourceAmount));
      
      //Trade and let Bancor immediately transfer the resulting value to the sender
      customerValue = BancorNetwork(bancorNetwork).convertForPrioritized2(_path, _sourceAmount, _minReturn, msg.sender, 0x0, 0x0, 0x0, 0x0);
      require(customerValue >= _minReturn);
    }
  }
  
  // End to end trading in a single call, using a Bancor prioritized trade (API approved) on a BancorConverter 
  // Approve 100.04% _sourceAmount tokens or send 100.04% _sourceAmount ETH
  // https://support.bancor.network/hc/en-us/articles/360001455772-Build-a-transaction-using-the-Convert-API
  function instantTradeBancorPrioritized(address _converter, address[] _path, uint _sourceAmount, uint256 _minReturn, uint256 _block, uint8 _v, bytes32 _r, bytes32 _s) external payable {
    
    // Reserve the fee
    uint totalValue = safeMul(_sourceAmount, fee) / 1000;
    uint customerValue;
    Token token;
    
    // Paying with Ethereum or token? 
    if (_path[0] == etherToken) {
    
      // Check amount of ether sent to make sure it's correct
      require(msg.value == totalValue);
     

      token = Token(_path[_path.length -1]);
      totalValue = token.balanceOf(address(this)); // save balance, reuse totalValue for gas savings
      
      //Trade
      customerValue = BancorConverter(_converter).quickConvertPrioritized.value(_sourceAmount)(_path, _sourceAmount, _minReturn, _block, _v, _r, _s);
      //did we receive the right amount of tokens?
      require(customerValue >= _minReturn && safeAdd(totalValue, customerValue) == token.balanceOf(address(this)));
      
      //send tokens to user
      token.transfer(msg.sender, customerValue);
    } else {
    
      // Make sure not to accept ETH when selling tokens
      require(msg.value == 0);
           
      // get tokens from sender, send to bancorNetwork after removing fee
      token = Token(_path[0]);
      
      require(token.transferFrom(msg.sender, this, totalValue));
      require(token.approve(_converter, _sourceAmount)); 
      
      //Trade
      
      totalValue = address(this).balance; // save balance, reuse totalValue for gas savings
      customerValue = BancorConverter(_converter).quickConvertPrioritized(_path, _sourceAmount, _minReturn, _block, _v, _r, _s);
      //did we receive the right amount of ETH?
      require(customerValue >= _minReturn && safeAdd(totalValue, customerValue) == address(this).balance);
      
      //send ETH to user
       msg.sender.transfer(customerValue);
    }
  }
  
  
  // End to end trading in a single call, using AirSwap. Request order from a maker using the API
  // Approve 100.04% _takerAmount tokens or send 100.04% _takerAmount ETH
   function instantTradeAirSwap(address _makerAddress, uint _makerAmount, address _makerToken,
     address _takerAddress, uint _takerAmount, address _takerToken, uint256 _expiration, uint256 _nonce, uint8 _v, bytes32 _r, bytes32 _s) external payable {
    
    // Reserve the fee
    uint totalValue = safeMul(_takerAmount, fee) / 1000;
    
    
    // Paying with Ethereum or token? Deposit to the actual store
    if (_takerToken == address(0)) {
    
      // Check amount of ether sent to make sure it's correct
      require(msg.value == totalValue);
      
      totalValue = Token(_makerToken).balanceOf(address(this)); // save balance, reuse totalValue for gas savings
      // Trade
      AirSwap(airSwap).fill.value(_takerAmount)(_makerAddress, _makerAmount, _makerToken, _takerAddress, _takerAmount, _takerToken, _expiration, _nonce, _v, _r, _s);
      //did we receive the right amount of tokens?
      require(safeAdd(totalValue, _makerAmount) == Token(_makerToken).balanceOf(address(this)));
       
      //send tokens to user
      Token(_makerToken).transfer(msg.sender, _makerAmount);
       
    } else {
    
      // Make sure not to accept ETH when selling tokens
      require(msg.value == 0 && _makerToken == wETH);
      
      WETH weth = WETH(_makerToken);
      
      // Assuming user already approved transfer, transfer to this contract
      require(Token(_takerToken).transferFrom(msg.sender, this, totalValue));
      require(Token(_takerToken).approve(airSwap, _takerAmount)); 
      
      totalValue = weth.balanceOf(address(this)); // save balance, reuse totalValue for gas savings
      
      // Trade
      AirSwap(airSwap).fill(_makerAddress, _makerAmount, _makerToken, _takerAddress, _takerAmount, _takerToken, _expiration, _nonce, _v, _r, _s);
      //did we receive the right amount of WETH?
      require(safeAdd(totalValue, _makerAmount) == weth.balanceOf(address(this)));
      
      // Unwrap WETH
      weth.withdraw(_makerAmount);
      
      //send ETH to user
      msg.sender.transfer(_makerAmount);
    }
  }
  

   /* End to end trading in a single call, using Kyber.
      Approve 100.04% _srcAmount tokens or send 100.04% _srcAmount ETH 
   */
  function instantTradeKyber(address _srcToken, uint256 _srcAmount, address _destToken, uint256 _maxDestAmount, uint _minConversionRate) external payable {
    
    // Reserve the fee
    uint totalValue = safeMul(_srcAmount, fee) / 1000;
    uint customerValue;
    Token token;

    // Paying with Ethereum or token? Deposit to the actual store
    if (_srcToken == address(0)) {

      // Check amount of ether sent to make sure it's correct
      require(msg.value == totalValue);
  
      token = Token(_destToken);
      totalValue = token.balanceOf(address(this)); // save balance, reuse totalValue for gas savings
      
      // Trade
      customerValue = Kyber(kyber).trade.value(_srcAmount)(address(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee), _srcAmount, _destToken, address(this), _maxDestAmount, _minConversionRate, 0);
  
      //did we receive the right amount of tokens?
      require(safeAdd(totalValue, customerValue) == token.balanceOf(address(this)));
   
      //send tokens to user
      token.transfer(msg.sender, customerValue);
   
    } else {

      // Make sure not to accept ETH when selling tokens
      require(msg.value == 0 && _destToken == address(0));
  
      token = Token(_srcToken);
      // Assuming user already approved transfer, transfer to this contract
      require(token.transferFrom(msg.sender, this, totalValue));
      require(token.approve(kyber, _srcAmount)); 
  
      totalValue = address(this).balance; // save balance, reuse totalValue for gas savings
  
      // Trade
      customerValue = Kyber(kyber).trade(_srcToken, _srcAmount, address(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee), address(this), _maxDestAmount, _minConversionRate, 0);
  
      //did we receive the right amount of ETH?
      require(safeAdd(totalValue, customerValue) == address(this).balance);
  
      //send ETH to user
      msg.sender.transfer(customerValue);    
    }
  }
  
  // Withdraw funds earned from fees
  function withdrawFees(address _token) external onlyOwner {
    if (_token == address(0)) {
      msg.sender.transfer(address(this).balance);
    } else {
      Token token = Token(_token);
      require(token.transfer(msg.sender, token.balanceOf(address(this))));
    }
  }
  
  // Withdraw funds that might be left in the exchange contracts
  function withdrawStore(address _token, address _store) external onlyOwner {
    TokenStore store = TokenStore(_store);
    
    if (_token == address(0)) {
      store.withdraw(store.balanceOf(_token, this));
    } else {
      store.withdrawToken(_token, store.balanceOf(_token, this));
    }
  }
  
}
