pragma solidity 0.6.4;
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract NoArgument {
    event NoArgumentCalled();

    function noArgument() external {
        emit NoArgumentCalled();
    }
}

contract OneArgument {
    event OneArgumentCalled(uint256 indexed argumentOne);

    function oneArgument(uint256 argumentOne) external {
        emit OneArgumentCalled(argumentOne);
    }
}

contract TwoArguments {
    event TwoArgumentsCalled(address[] argumentOne, bytes4 argumentTwo);

    function twoArguments(address[] calldata argumentOne, bytes4 argumentTwo) external {
        emit TwoArgumentsCalled(argumentOne, argumentTwo);
    }
}

contract ThreeArguments {
    event ThreeArgumentsCalled(string argumentOne, int8 argumentTwo, bool argumentThree);

    function threeArguments(string calldata argumentOne, int8 argumentTwo, bool argumentThree) external {
        emit ThreeArgumentsCalled(argumentOne, argumentTwo, argumentThree);
    }
}

contract TestERC721Receiver is IERC721Receiver {
    event ERC721Received(address operator, address from, uint256 tokenId, bytes data);

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external override returns (bytes4) {
        emit ERC721Received(operator, from, tokenId, data);
        return this.onERC721Received.selector;
    }
}
