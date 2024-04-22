pragma solidity ^0.6.4;

struct PermitSignature {
    uint deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
}
