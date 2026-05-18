import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess;
import 'package:firebase_analytics/firebase_analytics.dart';

class ChessBoardPage extends StatefulWidget {
  const ChessBoardPage({super.key});

  @override
  State<ChessBoardPage> createState() => _ChessBoardPageState();
}

class _ChessBoardPageState extends State<ChessBoardPage> with TickerProviderStateMixin {
  late chess.Chess game;

  String? selectedSquare;
  String? lastFrom;
  String? lastTo;

  final List<chess.Chess> _undoStack = [];

  AnimationController? _glowController;
  AnimationController? _boardInController;

  @override
  void initState() {
    super.initState();
    game = chess.Chess();
    FirebaseAnalytics.instance.logEvent(name: 'game_start');

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _boardInController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
  }

  @override
  void dispose() {
    _glowController?.dispose();
    _boardInController?.dispose();
    super.dispose();
  }

  String sq(int r, int c) => '${String.fromCharCode(97 + c)}${8 - r}';

  void tap(int r, int c) async {
    if (game.game_over) return;

    final s = sq(r, c);

    if (selectedSquare == null) {
      final p = game.get(s);
      if (p != null && p.color == game.turn) {
        setState(() => selectedSquare = s);
      }
      return;
    }

    await move(selectedSquare!, s);
  }

  Future<void> move(String from, String to) async {
    final piece = game.get(from);
    bool promo = false;

    if (piece != null && piece.type == chess.PieceType.PAWN) {
      if ((piece.color == chess.Color.WHITE && to.endsWith('8')) ||
          (piece.color == chess.Color.BLACK && to.endsWith('1'))) {
        promo = true;
      }
    }

    String promotion = 'q';
    if (promo) {
      promotion = await showPromotion() ?? 'q';
    }

    final chess.Chess gameClone = chess.Chess();
    gameClone.load(game.fen);

    final ok = game.move({
      'from': from,
      'to': to,
      'promotion': promotion,
    });

    if (ok) {
      setState(() {
        _undoStack.add(gameClone);
        lastFrom = from;
        lastTo = to;
        selectedSquare = null;
      });

      FirebaseAnalytics.instance.logEvent(
        name: 'piece_moved',
        parameters: {
          'from': from,
          'to': to,
          'promotion': promo ? 'true' : 'false',
        },
      );

      if (game.game_over) {
        showGameOver();
      }
    } else {
      var targetPiece = game.get(to);
      if (targetPiece != null && targetPiece.color == game.turn) {
        setState(() => selectedSquare = to);
      } else {
        setState(() => selectedSquare = null);
      }
    }
  }

  void _handleUndo() {
    if (_undoStack.isEmpty) return;
    setState(() {
      game = _undoStack.removeLast();
      selectedSquare = null;
      lastFrom = null;
      lastTo = null;
    });
    FirebaseAnalytics.instance.logEvent(name: 'game_undo');
  }

  void _showResetConfirmation() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF161A24) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Reset Match?", style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text("Are you sure you want to clear the match progress and start fresh?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel", style: TextStyle(color: isDark ? Colors.white60 : Colors.black54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  game = chess.Chess();
                  _undoStack.clear();
                  selectedSquare = null;
                  lastFrom = null;
                  lastTo = null;
                });
                FirebaseAnalytics.instance.logEvent(name: 'game_reset');
              },
              child: const Text("Reset Match"),
            ),
          ],
        );
      },
    );
  }

  Future<String?> showPromotion() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF161A24) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "PAWN PROMOTION",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: isDark ? Colors.white54 : Colors.brown[700]!.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: ['q', 'r', 'b', 'n']
                    .map((e) => Expanded(child: _promo(e)))
                    .toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _promo(String code) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final img = '${game.turn == chess.Color.WHITE ? 'w' : 'b'}$code';

    return GestureDetector(
      onTap: () => Navigator.pop(context, code),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.brown[50],
        ),
        child: Image.asset(
          'assets/pieces/$img.png',
          width: 48,
          height: 48,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  void showGameOver() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final textThemeColor = isDark ? const Color(0xFFF5F5F7) : const Color(0xFF2B1810);

    String statusTitle = "MATCH SETTLED";
    String outcomeSubtitle = "The battlefield has reached an equilibrium.";
    IconData statusIcon = Icons.handshake_rounded;
    Color thematicColor = Colors.blueGrey;

    if (game.in_checkmate) {
      statusTitle = "CHECKMATE • VICTORY";
      String winner = game.turn == chess.Color.WHITE ? 'Black' : 'White';
      outcomeSubtitle = "Flawless endgame execution! The $winner forces have claimed the board.";
      statusIcon = Icons.emoji_events_rounded;
      thematicColor = const Color(0xFFD4AF37);
    } else if (game.in_draw) {
      statusIcon = Icons.hourglass_empty_rounded;
      thematicColor = Colors.blueGrey;

      if (game.in_stalemate) {
        statusTitle = "DRAW • STALEMATE";
        outcomeSubtitle = "Stalemate! Side to move has no possible legal moves and is not in check.";
      } else if (game.in_threefold_repetition) {
        statusTitle = "DRAW • REPETITION";
        outcomeSubtitle = "Draw by Threefold Repetition. This exact layout occurred three times.";
      } else if (game.insufficient_material) {
        statusTitle = "DRAW • INSUFFICIENT PIECES";
        outcomeSubtitle = "Dead position. Neither side has enough material left to force a mate.";
      } else {
        statusTitle = "DRAW MATCH";
        outcomeSubtitle = "The game is drawn by consensus or technical fifty-move rule limits.";
      }
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "ChessGameOverModal",
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, __, ___) {
        return Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161A24) : Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.06) : Colors.brown[900]!.withOpacity(0.06),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.5 : 0.18),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: thematicColor.withOpacity(0.08),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: thematicColor.withOpacity(0.24),
                        width: 2,
                      ),
                    ),
                    child: Icon(statusIcon, size: 48, color: thematicColor),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    statusTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2, color: thematicColor),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    outcomeSubtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: textThemeColor.withOpacity(0.6), height: 1.4, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.02) : Colors.brown[900]!.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isDark ? Colors.white.withOpacity(0.04) : Colors.brown[900]!.withOpacity(0.04)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Total Move Count", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textThemeColor.withOpacity(0.4), letterSpacing: 0.5)),
                        Text("${(game.history.length / 2).ceil()} Full Moves", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textThemeColor)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: primaryColor,
                              side: BorderSide(color: primaryColor.withOpacity(0.4), width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              setState(() {
                                game = chess.Chess();
                                _undoStack.clear();
                                selectedSquare = null;
                                lastFrom = null;
                                lastTo = null;
                              });
                            },
                            icon: const Icon(Icons.replay_rounded, size: 20),
                            label: const Text("New Match", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.pop(context); // Safely pops back to HomeScreen
                            },
                            child: const Text("Main Menu", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, a, __, child) {
        return Transform.scale(
          scale: Curves.easeOutBack.transform(a.value),
          child: Opacity(opacity: a.value, child: child),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_glowController == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final backgroundColors = isDark
        ? [const Color(0xFF0F1115), const Color(0xFF1A1D24), const Color(0xFF0A0B0D)]
        : [const Color(0xFFF7F4F0), const Color(0xFFEFEBE4), Colors.white];

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: AnimatedBuilder(
        animation: _glowController!,
        builder: (_, __) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(backgroundColors[0], backgroundColors[1], _glowController!.value)!,
                  backgroundColors[2],
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  _topBar(),
                  _buildPlayerHeader(isWhite: false),

                  Expanded(
                    child: Center(
                      child: _buildCleanBoard(),
                    ),
                  ),

                  _buildPlayerHeader(isWhite: true),
                  const SizedBox(height: 4),
                  _buildActionBar(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _topBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFF5F5F7) : const Color(0xFF2B1810);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: textColor),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          Text(
            "LOCAL MULTIPLAYER",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: textColor),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.04) : Colors.brown[900]!.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "Moves: ${game.history.length}",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: textColor.withOpacity(0.8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerHeader({required bool isWhite}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    // Check pass-and-play turn orientation signatures
    bool isCurrentTurn = (game.turn == chess.Color.WHITE) == isWhite;

    String headerName = isWhite ? "White Player" : "Black Player";

    bool isCurrentColorInCheck = game.in_check && ((game.turn == chess.Color.WHITE) == isWhite);
    bool isCurrentColorMated = game.in_checkmate && ((game.turn == chess.Color.WHITE) == isWhite);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isCurrentColorMated
              ? Colors.red.withOpacity(0.2)
              : (isCurrentColorInCheck
              ? Theme.of(context).colorScheme.error.withOpacity(0.12)
              : (isCurrentTurn ? (isDark ? Colors.white.withOpacity(0.03) : Colors.white) : Colors.transparent)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isCurrentColorMated
                ? Colors.red
                : (isCurrentColorInCheck
                ? Theme.of(context).colorScheme.error.withOpacity(0.5)
                : (isCurrentTurn ? primaryColor.withOpacity(0.2) : Colors.transparent)),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: isWhite ? Colors.white : const Color(0xFF2C2E33),
              child: Icon(
                Icons.person_rounded,
                color: isWhite ? const Color(0xFF8B94A6) : Colors.white,
                size: 14,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              headerName,
              style: TextStyle(fontSize: 13, fontWeight: isCurrentTurn ? FontWeight.bold : FontWeight.w600),
            ),
            const Spacer(),
            if (isCurrentColorMated)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                child: const Text("DEFEAT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.5)),
              )
            else if (isCurrentColorInCheck)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.error, borderRadius: BorderRadius.circular(4)),
                child: const Text("CHECK", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
              )
            else if (isCurrentTurn && !game.game_over)
                Text(
                  "Your Turn",
                  style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 10),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildCleanBoard() {
    return ScaleTransition(
      scale: _boardInController ?? const AlwaysStoppedAnimation(1.0),
      child: Padding(
        padding: EdgeInsets.zero,
        child: AspectRatio(
          aspectRatio: 1,
          child: _board(),
        ),
      ),
    );
  }

  Widget _board() {
    final moves = <String>{};
    if (selectedSquare != null) {
      for (var m in game.moves({'square': selectedSquare, 'verbose': true})) {
        moves.add(m['to']);
      }
    }

    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 64,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
      itemBuilder: (_, i) {
        final s = sq(i ~/ 8, i % 8);

        final r = i ~/ 8;
        final c = i % 8;
        final darkSquare = (r + c) % 2 == 1;

        final piece = game.get(s);
        final selected = s == selectedSquare;
        final last = s == lastFrom || s == lastTo;
        final hint = moves.contains(s);
        final isCapture = hint && piece != null;

        Color base = darkSquare ? const Color(0xFFB58863) : const Color(0xFFF0D9B5);
        if (last) base = const Color(0xFFBAC146).withOpacity(0.6);
        if (selected) base = const Color(0xFFBAC146);

        return GestureDetector(
          onTap: () => tap(r, c),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            color: base,
            child: Stack(
              children: [
                if (hint && !isCapture)
                  Center(
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withOpacity(0.15)),
                    ),
                  ),
                if (hint && isCapture)
                  Center(
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black.withOpacity(0.18), width: 4),
                      ),
                    ),
                  ),
                if (piece != null)
                  Center(
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 180),
                      scale: selected ? 1.05 : 1,
                      child: Padding(
                        padding: EdgeInsets.zero,
                        child: Image.asset(_img(piece), fit: BoxFit.contain),
                      ),
                    ),
                  )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.03) : Colors.brown[900]!.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.06) : Colors.brown[900]!.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: const Icon(Icons.undo_rounded, size: 24),
            color: _undoStack.isNotEmpty ? primaryColor : Colors.grey.withOpacity(0.4),
            tooltip: 'Undo Move',
            onPressed: _undoStack.isNotEmpty ? _handleUndo : null,
          ),
          Container(width: 1, height: 20, color: isDark ? Colors.white12 : Colors.black12),
          IconButton(
            icon: Icon(Icons.restart_alt_rounded, size: 24, color: Theme.of(context).colorScheme.error),
            tooltip: 'Reset Board',
            onPressed: _showResetConfirmation,
          ),
        ],
      ),
    );
  }

  String _img(chess.Piece p) {
    final c = p.color == chess.Color.WHITE ? 'w' : 'b';
    final t = {
      chess.PieceType.PAWN: 'p',
      chess.PieceType.ROOK: 'r',
      chess.PieceType.KNIGHT: 'n',
      chess.PieceType.BISHOP: 'b',
      chess.PieceType.QUEEN: 'q',
      chess.PieceType.KING: 'k',
    }[p.type]!;
    return 'assets/pieces/$c$t.png';
  }
}