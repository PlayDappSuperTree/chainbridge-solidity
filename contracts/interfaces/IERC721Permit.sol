pragma solidity 0.6.4;

import "@openzeppelin/contracts/introspection/IERC165.sol";

interface IERC721Permit is IERC165 {
    function permit(
        address spender,
        uint256 tokenId,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function nonces(uint256 tokenId) external view returns (uint256);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
}


