// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @title ArcSplit
/// @notice Pull-based USDC revenue splits. One deposit, many payees, each payee
///         withdraws on their own. The contract never pushes funds in a loop, so a
///         payee that reverts cannot block the others, and rounding dust is
///         returned to the creator instead of being stranded.
contract ArcSplit {
    uint96 public constant BPS = 10_000;

    struct Split {
        address creator;
        uint64 createdAt;
        bool swept;
        uint256 total;
        uint256 allocated;
        address[] payees;
        uint96[] shares;
    }

    IERC20 public immutable usdc;

    mapping(bytes32 => Split) private _splits;
    mapping(bytes32 => mapping(address => uint256)) public claimable;
    mapping(bytes32 => mapping(address => bool)) public isPayee;

    event SplitCreated(bytes32 indexed id, address indexed creator, uint256 amount, uint256 payeeCount);
    event Claimed(bytes32 indexed id, address indexed payee, uint256 amount);
    event DustSwept(bytes32 indexed id, address indexed creator, uint256 amount);

    error SplitExists(bytes32 id);
    error UnknownSplit(bytes32 id);
    error LengthMismatch();
    error BadShares(uint256 sum);
    error ZeroPayee();
    error DuplicatePayee(address payee);
    error NothingToClaim();
    error NothingToSweep();
    error NotCreator();

    constructor(IERC20 usdc_) {
        usdc = usdc_;
    }

    /// @param id        caller-chosen id, e.g. keccak256("invoice-2026-10")
    /// @param payees    distinct addresses, no zero address
    /// @param shares    basis points, must sum to exactly 10000
    /// @param amount    USDC amount pulled from msg.sender
    function createSplit(bytes32 id, address[] calldata payees, uint96[] calldata shares, uint256 amount) external {
        if (_splits[id].creator != address(0)) revert SplitExists(id);
        uint256 n = payees.length;
        if (n == 0 || n != shares.length) revert LengthMismatch();
        if (amount == 0) revert BadShares(0);

        uint256 sum;
        for (uint256 i; i < n; ++i) {
            address p = payees[i];
            if (p == address(0)) revert ZeroPayee();
            if (isPayee[id][p]) revert DuplicatePayee(p);
            isPayee[id][p] = true;
            sum += shares[i];
        }
        if (sum != BPS) revert BadShares(sum);

        require(usdc.transferFrom(msg.sender, address(this), amount), "transferFrom failed");

        Split storage s = _splits[id];
        s.creator = msg.sender;
        s.createdAt = uint64(block.timestamp);
        s.total = amount;
        s.payees = payees;
        s.shares = shares;

        uint256 allocated;
        for (uint256 i; i < n; ++i) {
            uint256 slice = (amount * shares[i]) / BPS;
            claimable[id][payees[i]] = slice;
            allocated += slice;
        }
        s.allocated = allocated;

        emit SplitCreated(id, msg.sender, amount, n);
    }

    /// @notice payees pull their share whenever they want
    function claim(bytes32 id) external returns (uint256 amount) {
        if (_splits[id].creator == address(0)) revert UnknownSplit(id);
        amount = claimable[id][msg.sender];
        if (amount == 0) revert NothingToClaim();
        claimable[id][msg.sender] = 0;
        require(usdc.transfer(msg.sender, amount), "transfer failed");
        emit Claimed(id, msg.sender, amount);
    }

    /// @notice rounding dust goes back to the creator; unclaimed payee balances stay claimable
    function sweepDust(bytes32 id) external returns (uint256 refund) {
        Split storage s = _splits[id];
        if (s.creator == address(0)) revert UnknownSplit(id);
        if (msg.sender != s.creator) revert NotCreator();
        if (s.swept) revert NothingToSweep();
        refund = s.total - s.allocated;
        s.swept = true;
        if (refund > 0) {
            s.allocated = s.total;
            require(usdc.transfer(s.creator, refund), "refund failed");
        }
        emit DustSwept(id, msg.sender, refund);
    }

    function splitOf(bytes32 id)
        external
        view
        returns (address creator, uint256 total, uint256 allocated, bool swept, address[] memory payees, uint96[] memory shares)
    {
        Split storage s = _splits[id];
        return (s.creator, s.total, s.allocated, s.swept, s.payees, s.shares);
    }
}
