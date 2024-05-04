// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./Bridge2.t.sol";

contract TestRecallableSender is IRecallableSender, IERC165 {
    IBridge private bridge;
    IBridge.Context public ctx;

    constructor(IBridge _bridge) {
        bridge = _bridge;
    }

    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return _interfaceId == type(IRecallableSender).interfaceId
            || _interfaceId == type(IERC165Upgradeable).interfaceId;
    }

    function onMessageRecalled(
        IBridge.Message calldata _message,
        bytes32 _msgHash
    )
        external
        payable
    {
        ctx = bridge.context();
    }
}

contract BridgeTest2_recallMessage is BridgeTest2 {
    function test_bridge2_recallMessage_1() public transactedBy(Carol) {
        IBridge.Message memory message;
        message.srcOwner = Alice;
        message.destOwner = Bob;
        message.destChainId = remoteChainId;
        message.value = 1 ether;

        vm.expectRevert(Bridge.B_INVALID_CHAINID.selector);
        bridge.recallMessage(message, fakeProof);

        message.srcChainId = uint64(block.chainid);
        vm.expectRevert(Bridge.B_MESSAGE_NOT_SENT.selector);
        bridge.recallMessage(message, fakeProof);

        uint256 aliceBalance = Alice.balance;
        uint256 carolBalance = Carol.balance;
        uint256 bridgeBalance = address(bridge).balance;

        (, IBridge.Message memory m) = bridge.sendMessage{ value: 1 ether }(message);
        assertEq(Alice.balance, aliceBalance);
        assertEq(Carol.balance, carolBalance - 1 ether);
        assertEq(address(bridge).balance, bridgeBalance + 1 ether);

        bridge.recallMessage(m, fakeProof);
        assertEq(Alice.balance, aliceBalance + 1 ether);
        assertEq(Carol.balance, carolBalance - 1 ether);
        assertEq(address(bridge).balance, bridgeBalance);

        // recall the same message again
        vm.expectRevert(Bridge.B_INVALID_STATUS.selector);
        bridge.recallMessage(m, fakeProof);
    }

    function test_bridge2_recallMessage_missing_local_signal_service() public {
        vm.deal(Carol, 100 ether);

        IBridge.Message memory message;
        message.srcOwner = Alice;
        message.destOwner = Bob;
        message.destChainId = remoteChainId;
        message.value = 1 ether;
        message.srcChainId = uint64(block.chainid);

        vm.prank(Carol);
        (, IBridge.Message memory m) = bridge.sendMessage{ value: 1 ether }(message);

        vm.prank(owner);
        addressManager.setAddress(uint64(block.chainid), "signal_service", address(0));

        vm.prank(Carol);
        vm.expectRevert();
        bridge.recallMessage(m, fakeProof);
    }

    function test_bridge2_recallMessage_callable_sender() public {
        TestRecallableSender callableSender = new TestRecallableSender(bridge);

        vm.deal(address(callableSender), 100 ether);

        vm.deal(Carol, 100 ether);

        IBridge.Message memory message;
        message.srcOwner = Alice;
        message.destOwner = Bob;
        message.destChainId = remoteChainId;
        message.value = 1 ether;
        message.srcChainId = uint64(block.chainid);

        vm.prank(address(callableSender));
        (bytes32 mhash, IBridge.Message memory m) = bridge.sendMessage{ value: 1 ether }(message);

        vm.prank(address(callableSender));
        bridge.recallMessage(m, fakeProof);

        (bytes32 msgHash, address from, uint64 srcChainId) = callableSender.ctx();
        assertEq(msgHash, mhash);
        assertEq(from, address(bridge));
        assertEq(srcChainId, block.chainid);
    }
}
