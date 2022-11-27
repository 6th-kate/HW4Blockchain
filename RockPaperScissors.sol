// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

contract RockPaperScissors {

    uint constant public BET_MIN = 1 wei;
    uint constant public REVEAL_TIMEOUT = 10 minutes;  // Max delay of revelation phase
    uint private firstReveal;                          // Moment of first reveal

    enum Move {
        None,
        Rock,
        Paper,
        Scissors
    }

    enum Outcome {
        None,
        FirstPlayerWin,
        SecondPlayerWin,
        Draw
    }

    struct Commit {
        bytes32 commit;
        uint64 commitBlock;
        bool revealed;
    }

    // Players' addresses
    address payable firstPlayer;
    address payable secondPlayer;

    uint public firstPlayerBet;
    uint public secondPlayerBet;

    // Hashed moves
    Commit private firstPlayerCommit;
    Commit private secondPlayerCommit;

    // Clear moves set only after both players have committed their encrypted moves
    Move private firstPlayerMove;
    Move private secondPlayerMove;

    event CommitHash(address sender, bytes32 dataHash, uint64 block);
    event Reveal(address player, Move move);
    event Result(address player, Outcome outcome);
    event Payout(address player, uint amount);
    
    // Phases modifiers
    modifier RegisterPhase {
        require(msg.sender != firstPlayer && msg.sender != secondPlayer);
        require(msg.value >= BET_MIN);
        _;
    }

    modifier CommitPhase {
        require (msg.sender == firstPlayer || msg.sender == secondPlayer);
        _;
    }

    modifier RevealPhase {
        require (msg.sender == firstPlayer || msg.sender == secondPlayer);
        require(firstPlayerCommit.commit != 0x0 && secondPlayerCommit.commit != 0x0);
        _;
    }

    modifier ResultPhase {
        require((firstPlayerCommit.revealed && secondPlayerCommit.revealed) ||
                (firstReveal != 0 && block.timestamp > firstReveal + REVEAL_TIMEOUT));
        _;
    }

    // Register a player.
    // Return player's ID upon successful registration.
    function register() public payable RegisterPhase returns (uint) {
        if (firstPlayer == address(0x0)) {
            firstPlayer = payable(msg.sender);
            firstPlayerBet = msg.value;
            return 1;
        } else if (secondPlayer == address(0x0)) {
            secondPlayer = payable(msg.sender);
            secondPlayerBet = msg.value;
            return 2;
        }
        return 0;
    }

    // Save player's encrypted move.
    // Return 'true' if move was valid, 'false' otherwise.
    function commit(bytes32 dataHash) public CommitPhase {
        if (msg.sender == firstPlayer && firstPlayerCommit.commit == 0x0) {
            firstPlayerCommit.commit = dataHash;
            firstPlayerCommit.commitBlock = uint64(block.number);
            firstPlayerCommit.revealed = false;
            emit CommitHash(msg.sender, firstPlayerCommit.commit, firstPlayerCommit.commitBlock);
        } else if (msg.sender == secondPlayer && secondPlayerCommit.commit == 0x0) {
            secondPlayerCommit.commit = dataHash;
            secondPlayerCommit.commitBlock = uint64(block.number);
            secondPlayerCommit.revealed = false;
            emit CommitHash(msg.sender, secondPlayerCommit.commit, secondPlayerCommit.commitBlock);
        }
    }

    // Compare clear move given by the player with saved encrypted move.
    // Return clear move upon success, 'Moves.None' otherwise.
    function reveal(Move move, bytes32 salt) public RevealPhase {
        require(move == Move.Rock || move == Move.Paper || move == Move.Scissors, "invalid choice");

        if (msg.sender == firstPlayer) {
            require(firstPlayerCommit.revealed == false);
            require(getSaltedHash(move, salt) == firstPlayerCommit.commit);
            firstPlayerMove = move;
            firstPlayerCommit.revealed = true;
        } else if (msg.sender == secondPlayer) {
            require(secondPlayerCommit.revealed == false);
            require(getSaltedHash(move, salt) == secondPlayerCommit.commit);
            secondPlayerMove = move;
            secondPlayerCommit.revealed = true;
        }

        // Timer starts after first revelation from one of the player
        if (firstReveal == 0) {
            firstReveal = block.timestamp;
        }

        emit Reveal(msg.sender, move);
    }

    // Compute the outcome and pay the winner(s).
    // Return the outcome.
    function getOutcome() public ResultPhase {
        Outcome outcome;

        if (firstPlayerMove == secondPlayerMove) {
            outcome = Outcome.Draw;
        } else if ((firstPlayerMove == Move.Rock     && secondPlayerMove == Move.Scissors) ||
                   (firstPlayerMove == Move.Paper    && secondPlayerMove == Move.Rock)     ||
                   (firstPlayerMove == Move.Scissors && secondPlayerMove == Move.Paper)    ||
                   (firstPlayerMove != Move.None     && secondPlayerMove == Move.None)) {
            outcome = Outcome.FirstPlayerWin;
        } else {
            outcome = Outcome.SecondPlayerWin;
        }

        address payable firstAddr = firstPlayer;
        address payable secondAddr = secondPlayer;
        uint firstBet = firstPlayerBet;
        uint secondBet = secondPlayerBet;
        reset();  // Reset game before paying to avoid reentrancy attacks
        pay(firstAddr, secondAddr, firstBet, secondBet, outcome);

        emit Result(msg.sender, outcome);
    }

    // Pay the winner(s).
    function pay(address payable firstAddr, address payable secondAddr,
                 uint firstBet, uint secondBet, Outcome outcome) private {
        // Uncomment lines below if you need to adjust the gas limit
        if (outcome == Outcome.FirstPlayerWin) {
            (bool success, ) = firstAddr.call{value: address(this).balance, gas:2300}("");
            require(success, "call failed");
            emit Payout(firstAddr, firstBet + secondBet);
        } else if (outcome == Outcome.SecondPlayerWin) {
            (bool success, ) = secondAddr.call{value: address(this).balance, gas:2300}("");
            require(success, "call failed");
            emit Payout(secondAddr, firstBet + secondBet);
        } else {
            firstAddr.transfer(firstPlayerBet);
            secondAddr.transfer(secondPlayerBet);
        }
    }

    // Reset the game.
    function reset() private {
        firstPlayerBet = 0;
        secondPlayerBet = 0;
        firstReveal = 0;
        firstPlayer = payable(address(0x0));
        secondPlayer = payable(address(0x0));
        firstPlayerCommit.revealed = false;
        firstPlayerCommit.commit = 0x0;
        firstPlayerCommit.commitBlock = 0x0;
        secondPlayerCommit.revealed = false;
        secondPlayerCommit.commit = 0x0;
        secondPlayerCommit.commitBlock = 0x0;
        firstPlayerMove = Move.None;
        secondPlayerMove = Move.None;
    }
    
    function getSaltedHash(Move move, bytes32 salt) public view returns(bytes32) {
        return keccak256(abi.encodePacked(address(this), move, salt));
    }
}