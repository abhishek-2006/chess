import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess;
import 'package:firebase_analytics/firebase_analytics.dart';

class ChessBoardPage extends StatefulWidget {
  const ChessBoardPage({super.key});

  @override
  State<ChessBoardPage> createState() => _ChessBoardPageState();
}

class _ChessBoardPageState extends State<ChessBoardPage> {
  late chess.Chess game;
  String? selectedSquare; // e.g., 'e2'

  @override
  void initState() {
    super.initState();
    game = chess.Chess();
    FirebaseAnalytics.instance.logEvent(name: 'game_start');
  }

  void _resetBoard() {
    setState(() {
      game = chess.Chess();
      selectedSquare = null;
    });
    FirebaseAnalytics.instance.logEvent(name: 'game_reset');
  }

  String _coordsToSquare(int row, int col) {
    String file = String.fromCharCode('a'.codeUnitAt(0) + col);
    int rank = 8 - row;
    return '$file$rank';
  }

  void _onSquareTap(int row, int col) async {
    String square = _coordsToSquare(row, col);
    setState(() {
      if (selectedSquare == null) {
        var piece = game.get(square);
        if (piece != null && piece.color == game.turn) {
          selectedSquare = square;
        }
      } else {
        _handleMove(selectedSquare!, square);
      }
    });
  }

  void _handleMove(String from, String to) async {
    var piece = game.get(from);
    bool isPromotion = false;
    if (piece != null && piece.type == chess.PieceType.PAWN) {
      if ((piece.color == chess.Color.WHITE && to[1] == '8') ||
          (piece.color == chess.Color.BLACK && to[1] == '1')) {
        isPromotion = true;
      }
    }

    String promotionPiece = 'q';
    if (isPromotion) {
      var moves = game.moves({'square': from, 'verbose': true});
      bool isValidDestination = moves.any((m) => m['to'] == to);
      if (isValidDestination) {
        promotionPiece = await _showPromotionDialog() ?? 'q';
      }
    }

    setState(() {
      var move = {
        'from': from,
        'to': to,
        'promotion': promotionPiece
      };

      bool success = game.move(move);
      if (success) {
        selectedSquare = null;
        FirebaseAnalytics.instance.logEvent(
          name: 'piece_moved',
          parameters: {
            'from': from,
            'to': to,
            'promotion': isPromotion ? 'true' : 'false',
          },
        );
        if (game.game_over) {
          _showGameOverDialog();
        }
      } else {
        var targetPiece = game.get(to);
        if (targetPiece != null && targetPiece.color == game.turn) {
          selectedSquare = to;
        } else {
          selectedSquare = null;
        }
      }
    });
  }

  Future<String?> _showPromotionDialog() async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Choose Promotion Piece'),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _promotionOption(context, 'q', game.turn == chess.Color.WHITE ? 'wq' : 'bq'),
              _promotionOption(context, 'r', game.turn == chess.Color.WHITE ? 'wr' : 'br'),
              _promotionOption(context, 'b', game.turn == chess.Color.WHITE ? 'wb' : 'bb'),
              _promotionOption(context, 'n', game.turn == chess.Color.WHITE ? 'wn' : 'bn'),
            ],
          ),
        );
      },
    );
  }

  Widget _promotionOption(BuildContext context, String pieceCode, String imageName) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(pieceCode),
      child: Image.asset(
        'assets/pieces/$imageName.png',
        width: 60,
        height: 60,
      ),
    );
  }

  void _showGameOverDialog() {
    String message = "Game Over";
    String resultStatus = "unknown";
    if (game.in_checkmate) {
      message = "Checkmate! ${game.turn == chess.Color.WHITE ? 'Black' : 'White'} wins.";
      resultStatus = "checkmate_${game.turn == chess.Color.WHITE ? 'black' : 'white'}_wins";
    } else if (game.in_draw) {
      message = "Draw!";
      resultStatus = "draw";
    }

    FirebaseAnalytics.instance.logEvent(
      name: 'game_over',
      parameters: {'result': resultStatus},
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Game Over"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _resetBoard();
            },
            child: const Text("Restart"),
          ),
        ],
      ),
    );
  }

  String _getPieceImageAsset(chess.Piece? piece) {
    if (piece == null) return '';
    String prefix = piece.color == chess.Color.WHITE ? 'w' : 'b';
    String type = '';
    switch (piece.type) {
      case chess.PieceType.PAWN: type = 'p'; break;
      case chess.PieceType.KNIGHT: type = 'n'; break;
      case chess.PieceType.BISHOP: type = 'b'; break;
      case chess.PieceType.ROOK: type = 'r'; break;
      case chess.PieceType.QUEEN: type = 'q'; break;
      case chess.PieceType.KING: type = 'k'; break;
    }
    return 'assets/pieces/$prefix$type.png';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Chess', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _resetBoard,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),
            // Player Top (Black)
            _buildPlayerInfo(isWhite: false),
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 30,
                            offset: const Offset(0, 15),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: _buildBoardLayout(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Player Bottom (White)
            _buildPlayerInfo(isWhite: true),
            const SizedBox(height: 20),
            _buildStatusCard(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerInfo({required bool isWhite}) {
    bool isTurn = (game.turn == chess.Color.WHITE) == isWhite;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isWhite ? Colors.white : Colors.grey[800],
              shape: BoxShape.circle,
              border: Border.all(
                color: isTurn ? Theme.of(context).colorScheme.primary : Colors.transparent,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              Icons.person,
              color: isWhite ? Colors.grey[400] : Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isWhite ? "White" : "Black",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (isTurn && game.in_check)
                Text(
                  "CHECK!",
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          const Spacer(),
          if (isTurn)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                "Thinking...",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    String status = "Playing";
    if (game.in_checkmate) {
      status = "Checkmate";
    } else if (game.in_draw) {
      status = "Draw";
    } else if (game.in_check) {
      status = "Check";
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                status,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              "Moves: ${game.history.length}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoardLayout() {
    List<String> possibleMoveDestinations = [];
    if (selectedSquare != null) {
      var moves = game.moves({'square': selectedSquare, 'verbose': true});
      for (var m in moves) {
        possibleMoveDestinations.add(m['to']);
      }
    }

    return Column(
      children: [
        _buildFileLabels(),
        Expanded(
          child: Row(
            children: [
              _buildRankLabels(),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
                  ),
                  child: GridView.builder(
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 8,
                    ),
                    itemCount: 64,
                    itemBuilder: (context, index) {
                      int row = index ~/ 8;
                      int col = index % 8;
                      String square = _coordsToSquare(row, col);
                      bool isDark = (row + col) % 2 == 1;
                      bool isSelected = selectedSquare == square;

                      bool isPossibleMove = possibleMoveDestinations.contains(square);

                      var piece = game.get(square);
                      bool isCapture = isPossibleMove && piece != null;

                      Color squareColor = isDark ? const Color(0xFFB58863) : const Color(0xFFF0D9B5);
                      if (isSelected) {
                        squareColor = const Color(0xFFCDD26A).withValues(alpha: 0.8);
                      }

                      return GestureDetector(
                        onTap: () => _onSquareTap(row, col),
                        child: Stack(
                          children: [
                            Container(color: squareColor),
                            if (isPossibleMove && isCapture)
                              Center(
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.black.withValues(alpha: 0.2), width: 5),
                                  ),
                                ),
                              ),
                            if (isPossibleMove && !isCapture)
                              Center(
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            if (piece != null)
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(2.0),
                                  child: Image.asset(
                                    _getPieceImageAsset(piece),
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              _buildRankLabels(),
            ],
          ),
        ),
        _buildFileLabels(),
      ],
    );
  }

  Widget _buildFileLabels() {
    return Container(
      color: const Color(0xFF2C2C2C),
      height: 20,
      child: Row(
        children: [
          const SizedBox(width: 20),
          ...List.generate(8, (i) => Expanded(
            child: Center(
              child: Text(
                String.fromCharCode('A'.codeUnitAt(0) + i),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white70),
              ),
            ),
          )),
          const SizedBox(width: 20),
        ],
      ),
    );
  }

  Widget _buildRankLabels() {
    return Container(
      color: const Color(0xFF2C2C2C),
      width: 20,
      child: Column(
        children: List.generate(8, (i) => Expanded(
          child: Center(
            child: Text(
              '${8 - i}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white70),
            ),
          ),
        )),
      ),
    );
  }
}
