# @version ^0.2.8

############################################################
MAX_WALLETS: constant(uint256) = 5

V_MASK: constant(uint256) = 255

PREFIX: constant(Bytes[28]) = 0x19457468657265756d205369676e6564204d6573736167653a0a3634

INITIAL_PONCE: constant(bytes32) = 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef

############################################################
#region internalProperties

############################################################
relevantWallets: public(HashMap[address, bool])
relevantVotes: public(uint256)
ponce: public(bytes32) # pattern used once

#endregion

############################################################
@external
# def __init__(_relevantWallets: address[4]): #TODO implement
def __init__():
    self.relevantVotes = 1
    self.relevantWallets[msg.sender] = True
    self.ponce = INITIAL_PONCE

############################################################
#region exposedFunctions

############################################################
#region readOnlyFunctions
@external
@view
def getMaxWallets() -> uint256:
    return MAX_WALLETS


############################################################
@external
@view
def recoverAddress(_hash:bytes32, _signature:Bytes[65]) -> address:
    _v: uint256 = 0
    _r: uint256 = 0
    _s: uint256 = 0
    
    ########################################################
    _r = extract32(_signature, 0, output_type=uint256)
    _s = extract32(_signature, 32, output_type=uint256)
    _v = extract32(_signature, 33, output_type=uint256)
    _v = bitwise_and(_v, V_MASK)
    return ecrecover(_hash, _v, _r, _s)

@external
@view
def getETHMessage64Hash(_message:Bytes[64]) -> bytes32:
    _ethMessageHash: bytes32 = keccak256(concat(PREFIX, _message))
    return _ethMessageHash

############################################################
@external
@view
def extractAddress(_message: Bytes[64]) -> address:
    _address: address = extract32(_message, 0, output_type=address)
    return _address

############################################################
@external
@view
def getWalletActionMessage(_wallet:address) -> Bytes[64]:
    _addressBytes32: bytes32 = convert(_wallet, bytes32)
    _messageBytes: Bytes[64] = concat(_addressBytes32, self.ponce)
    return _messageBytes

@external
@view
def getSendEtherMessage(_amount:uint256) -> Bytes[64]:
    _amountBytes32: bytes32 = convert(_amount, bytes32)
    _messageBytes: Bytes[64] = concat(_amountBytes32, self.ponce)
    return _messageBytes

@external
@view
def getTransactionMessage(_transaction: Bytes[1024]) -> Bytes[64]:
    _transactionHash: bytes32 = keccak256(_transaction)
    _messageBytes: Bytes[64] = concat(_transactionHash, self.ponce)
    return _messageBytes



#endregion

############################################################
#region writeFunctions

############################################################
#region add/remove wallets
@external
def addRelevantWallet(_wallet:address, _signatures: Bytes[325]) -> bool:
    if self.relevantWallets[_wallet]:
        return True
    assert _wallet != ZERO_ADDRESS
    _requiredVotes: uint256 = self.relevantVotes
    assert _requiredVotes < MAX_WALLETS 

    _approvers: address[5] = [ZERO_ADDRESS,ZERO_ADDRESS,ZERO_ADDRESS,ZERO_ADDRESS,ZERO_ADDRESS]
    _approvals: uint256 = 0
    
    _hash: bytes32 = keccak256(concat(PREFIX, convert(_wallet, bytes32), self.ponce))
    self.ponce = _hash

    _v: uint256 = 0
    _r: uint256 = 0
    _s: uint256 = 0

    _addr: address = ZERO_ADDRESS
    _len: int128 = convert(len(_signatures), int128)

    if self.relevantWallets[msg.sender]:
        self.relevantWallets[msg.sender] = False # no double vote!
        _approvers[_approvals] = msg.sender
        _approvals += 1
    
    ########################################################
    for i in [0,65,130,195,260]:
        if _len < i+65:
            break
        _r = extract32(_signatures, i, output_type=uint256)
        _s = extract32(_signatures, i+32, output_type=uint256)
        _v = extract32(_signatures, i+33, output_type=uint256)
        _v = bitwise_and(_v, V_MASK)
        _addr = ecrecover(_hash, _v, _r, _s)
        if self.relevantWallets[_addr]: # on ZERO_ADDRESS this will never be True
            self.relevantWallets[_addr] = False # no double vote!
            _approvers[_approvals] = _addr
            _approvals += 1

    ########################################################
    assert _approvals == _requiredVotes
    #  Hurray! Everybody approved!    
    
    ########################################################
    # give back vote privilege to relevant Voters
    for _approver in _approvers:
        if _approver == ZERO_ADDRESS:
            break
        else:
            self.relevantWallets[_approver] = True
    
    ########################################################
    self.relevantWallets[_wallet] = True
    self.relevantVotes = _requiredVotes + 1
    return True

@external
def removeRelevantWallet(_wallet: address, _signatures: Bytes[325]) -> bool:
    if not self.relevantWallets[_wallet]:
        return True
    assert _wallet != ZERO_ADDRESS
    _requiredVotes: uint256 = self.relevantVotes
    assert _requiredVotes > 2 
    # we don't want a single wallet to be able to remove the other

    _approvers: address[5] = [ZERO_ADDRESS,ZERO_ADDRESS,ZERO_ADDRESS,ZERO_ADDRESS,ZERO_ADDRESS]
    _approvals: uint256 = 0
    
    _hash: bytes32 = keccak256(concat(PREFIX, convert(_wallet, bytes32), self.ponce))
    self.ponce = _hash
    
    _v: uint256 = 0
    _r: uint256 = 0
    _s: uint256 = 0

    _addr: address = ZERO_ADDRESS
    _len: int128 = convert(len(_signatures), int128)

    ########################################################
    # preemptive exclusion from this vote
    self.relevantWallets[_wallet] = False
    _requiredVotes -= 1
    # self.relevantVotes = _requiredVotes - 1

    ########################################################
    if self.relevantWallets[msg.sender]:
        self.relevantWallets[msg.sender] = False # no double vote!
        _approvers[_approvals] = msg.sender
        _approvals += 1
    
    ########################################################
    for i in [0,65,130,195]:
        if _len < i+65:
            break
        _r = extract32(_signatures, i, output_type=uint256)
        _s = extract32(_signatures, i+32, output_type=uint256)
        _v = extract32(_signatures, i+33, output_type=uint256)
        _v = bitwise_and(_v, V_MASK)
        _addr = ecrecover(_hash, _v, _r, _s)
        if self.relevantWallets[_addr]: # on ZERO_ADDRESS this will never be True
            self.relevantWallets[_addr] = False # no double vote!
            _approvers[_approvals] = _addr
            _approvals += 1

    ########################################################
    assert _approvals == _requiredVotes
    #  Hurray! Everybody approved!    
    
    ########################################################
    # give back vote privilege to relevant Voters
    for _approver in _approvers:
        if _approver == ZERO_ADDRESS:
            break
        else:
            self.relevantWallets[_approver] = True    
    return True

#endregion




#endregion


# Events ###################################################
############################################################
event EtherSent:
    _wallet: indexed(address)
    _amount: uint256
    _nonce: indexed(bytes32)

event WalletAdded:
    _wallet: indexed(address)
    _nonce: indexed(bytes32)

event WalletRemoved:
    _wallet: indexed(address)
    _nonce: indexed(bytes32)

event TransactionExecuted:
    _nonce: indexed(bytes32)
