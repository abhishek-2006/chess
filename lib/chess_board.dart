import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess;

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
  }

  void _resetBoard() {
    setState(() {
      game = chess.Chess();
      selectedSquare = null;
    });
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
              _promotionOption(context, 'q', game.turn == chess.Color.WHITE ? '♕' : '♛'),
              _promotionOption(context, 'r', game.turn == chess.Color.WHITE ? '♖' : '♜'),
              _promotionOption(context, 'b', game.turn == chess.Color.WHITE ? '♗' : '♝'),
              _promotionOption(context, 'n', game.turn == chess.Color.WHITE ? '♘' : '♞'),
            ],
          ),
        );
      },
    );
  }

  Widget _promotionOption(BuildContext context, String pieceCode, String unicode) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(pieceCode),
      child: Text(unicode, style: const TextStyle(fontSize: 40)),
    );
  }

  void _showGameOverDialog() {
    String message = "Game Over";
    if (game.in_checkmate) {
      message = "Checkmate! ${game.turn == chess.Color.WHITE ? 'Black' : 'White'} wins.";
    } else if (game.in_draw) {
      message = "Draw!";
    }

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

  String _getPieceUnicode(chess.Piece? piece) {
    if (piece == null) return '';
    if (piece.color == chess.Color.WHITE) {
      switch (piece.type) {
        case chess.PieceType.PAWN: return '♙';
        case chess.PieceType.KNIGHT: return '♘';
        case chess.PieceType.BISHOP: return '♗';
        case chess.PieceType.ROOK: return '♖';
        case chess.PieceType.QUEEN: return '♕';
        case chess.PieceType.KING: return '♔';
      }
    } else {
      switch (piece.type) {
        case chess.PieceType.PAWN: return '♟';
        case chess.PieceType.KNIGHT: return '♞';
        case chess.PieceType.BISHOP: return '♝';
        case chess.PieceType.ROOK: return '♜';
        case chess.PieceType.QUEEN: return '♛';
        case chess.PieceType.KING: return '♚';
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chess Game'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetBoard,
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          Text(
            "Turn: ${game.turn == chess.Color.WHITE ? 'White' : 'Black'}${game.in_check ? ' (CHECK!)' : ''}",
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Column(
                    children: [
                      _buildFileLabels(),
                      Expanded(
                        child: Row(
                          children: [
                            _buildRankLabels(),
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.brown[900]!, width: 2),
                                ),
                                child: GridView.builder(
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

                                    bool isPossibleMove = false;
                                    if (selectedSquare != null) {
                                      var moves = game.moves({'square': selectedSquare, 'verbose': true});
                                      isPossibleMove = moves.any((m) => m['to'] == square);
                                    }

                                    return GestureDetector(
                                      onTap: () => _onSquareTap(row, col),
                                      child: Container(
                                        color: isSelected
                                            ? Colors.yellow.withValues(alpha: 0.7)
                                            : (isPossibleMove
                                                ? Colors.green.withValues(alpha: 0.4)
                                                : (isDark ? Colors.brown[700] : Colors.brown[200])),
                                        child: Center(
                                          child: Text(
                                            _getPieceUnicode(game.get(square)),
                                            style: const TextStyle(fontSize: 32),
                                          ),
                                        ),
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
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Status: ${game.in_checkmate ? 'Checkmate' : game.in_draw ? 'Draw' : game.in_check ? 'Check' : 'Playing'}",
                  style: const TextStyle(fontSize: 16),
                ),
                Text(
                  "Moves: ${game.history.length}",
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildFileLabels() {
    return Row(
      children: [
        const SizedBox(width: 20),
        ...List.generate(8, (i) => Expanded(
          child: Center(
            child: Text(
              String.fromCharCode('A'.codeUnitAt(0) + i),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        )),
        const SizedBox(width: 20),
      ],
    );
  }

  Widget _buildRankLabels() {
    return SizedBox(
      width: 20,
      child: Column(
        children: List.generate(8, (i) => Expanded(
          child: Center(
            child: Text(
              '${8 - i}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        )),
      ),
    );
  }
}
