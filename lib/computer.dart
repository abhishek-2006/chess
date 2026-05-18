import 'dart:math';
import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess;
import 'package:firebase_analytics/firebase_analytics.dart';

class ComputerGamePage extends StatefulWidget {
  const ComputerGamePage({super.key});

  @override
  State<ComputerGamePage> createState() => _ComputerGamePageState();
}

class _ComputerGamePageState extends State<ComputerGamePage> with TickerProviderStateMixin {
  late chess.Chess game;

  String? selectedSquare;
  String? lastFrom;
  String? lastTo;

  // Track match settings
  bool _hasChosenSide = false;
  chess.Color _userColor = chess.Color.WHITE;
  bool _isAiThinking = false;

  // --- UNIQUE ID TRACKER FOR SERIALIZING BUFFER QUEUES ---
  // Increments on resets/undos to cancel obsolete asynchronous AI callbacks completely
  int _currentExecutionSessionId = 0;

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
    // Safely invalidate any active execution contexts
    _currentExecutionSessionId++;
    _glowController?.dispose();
    _boardInController?.dispose();
    super.dispose();
  }

  String _indexToSquare(int index) {
    int fileIndex = index % 8;
    int rankIndex = index ~/ 8;

    if (_userColor == chess.Color.BLACK) {
      fileIndex = 7 - fileIndex;
      rankIndex = 7 - rankIndex;
    }

    String file = String.fromCharCode(97 + fileIndex);
    int rank = 8 - rankIndex;
    return '$file$rank';
  }

  List<int> _squareToCoords(String square) {
    int col = square.codeUnitAt(0) - 97;
    int row = 8 - int.parse(square[1]);
    if (_userColor == chess.Color.BLACK) {
      col = 7 - col;
      row = 7 - row;
    }
    return [row, col];
  }

  void tap(int r, int c) async {
    // Block execution if AI is calculating or match state is finalized
    if (_isAiThinking || game.game_over || game.turn != _userColor) return;

    int correctedIndex = r * 8 + c;
    final s = _indexToSquare(correctedIndex);

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
    if (_isAiThinking || game.game_over) return;

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
        name: 'vs_computer_player_moved',
        parameters: {'from': from, 'to': to},
      );

      if (game.game_over) {
        showGameOver();
      } else {
        _triggerAiMove();
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

  // --- HARDENED ASYNCHRONOUS COMPILING AI EXECUTION ---
  void _triggerAiMove() async {
    if (game.game_over) return;

    // Capture the exact context token when this step initiated
    final int sessionIdAtStart = _currentExecutionSessionId;

    setState(() => _isAiThinking = true);

    await Future.delayed(Duration(milliseconds: 600 + Random().nextInt(400)));

    // PROTECTION CRITICAL: Verify context stability before updating variables
    if (!mounted || _currentExecutionSessionId != sessionIdAtStart || game.game_over) {
      return;
    }

    var legalMoves = game.moves({'verbose': true});
    if (legalMoves.isEmpty) {
      setState(() => _isAiThinking = false);
      return;
    }

    Map<String, dynamic>? selectedMove;
    int highestScore = -9999;

    final Map<String, int> pieceWeights = {
      'p': 10,
      'n': 30,
      'b': 30,
      'r': 50,
      'q': 90,
      'k': 900,
    };

    legalMoves.shuffle();

    for (var move in legalMoves) {
      int score = 0;

      if (move['captured'] != null) {
        score += pieceWeights[move['captured'].toString()]! * 10;
      }

      if (move['promotion'] != null) {
        score += 80;
      }

      String toSq = move['to'].toString();
      if (toSq.contains('d4') || toSq.contains('d5') || toSq.contains('e4') || toSq.contains('e5')) {
        score += 3;
      } else if (toSq.contains('c3') || toSq.contains('f3') || toSq.contains('c6') || toSq.contains('f6')) {
        score += 1;
      }

      final tempGame = chess.Chess();
      tempGame.load(game.fen);
      tempGame.move(move);
      if (tempGame.in_check) {
        score += 5;
      }

      if (score > highestScore) {
        highestScore = score;
        selectedMove = move;
      }
    }

    selectedMove ??= legalMoves.first;

    // Final security check loop check before committing states
    if (_currentExecutionSessionId != sessionIdAtStart) return;

    String aiFrom = selectedMove!['from'].toString();
    String aiTo = selectedMove['to'].toString();

    game.move(selectedMove);

    setState(() {
      lastFrom = aiFrom;
      lastTo = aiTo;
      _isAiThinking = false;
    });

    FirebaseAnalytics.instance.logEvent(name: 'vs_computer_ai_moved');

    if (game.game_over) {
      showGameOver();
    }
  }

  void _handleUndo() {
    if (_undoStack.isEmpty || _isAiThinking) return;
    setState(() {
      _currentExecutionSessionId++; // Invalidate stale calculation calls immediately
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
          content: const Text("Are you sure you want to clear your current progress vs Computer?"),
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
                  _currentExecutionSessionId++; // Flush out execution queues completely
                  game = chess.Chess();
                  _undoStack.clear();
                  selectedSquare = null;
                  lastFrom = null;
                  lastTo = null;
                  _isAiThinking = false;
                  _hasChosenSide = false;
                });
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
      if (game.turn == _userColor) {
        statusTitle = "CHECKMATE • DEFEAT";
        outcomeSubtitle = "Your King has been trapped. The computer AI claims the board.";
        statusIcon = Icons.gavel_rounded;
        thematicColor = Theme.of(context).colorScheme.error;
      } else {
        statusTitle = "CHECKMATE • VICTORY";
        outcomeSubtitle = "Flawless endgame execution! You have successfully mated the CPU.";
        statusIcon = Icons.emoji_events_rounded;
        thematicColor = const Color(0xFFD4AF37);
      }
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
                        Text("Match Game Duration", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textThemeColor.withOpacity(0.4), letterSpacing: 0.5)),
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
                                _currentExecutionSessionId++;
                                game = chess.Chess();
                                _undoStack.clear();
                                selectedSquare = null;
                                lastFrom = null;
                                lastTo = null;
                              });
                              if (_userColor == chess.Color.BLACK) {
                                _triggerAiMove();
                              }
                            },
                            icon: const Icon(Icons.replay_rounded, size: 20),
                            label: const Text("Play Again", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
                              setState(() {
                                _currentExecutionSessionId++;
                                game = chess.Chess();
                                _undoStack.clear();
                                selectedSquare = null;
                                lastFrom = null;
                                lastTo = null;
                                _hasChosenSide = false;
                              });
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
    if (!_hasChosenSide) {
      return _buildSideSelectionScreen();
    }

    if (_glowController == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final backgroundColors = isDark
        ? [const Color(0xFF0F1115), const Color(0xFF1A1D24), const Color(0xFF0A0B0D)]
        : [const Color(0xFFF7F4F0), const Color(0xFFEFEBE4), Colors.white];

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: AnimatedBuilder(
        animation: _glowController!,
        builder: (context, __) {
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
                  _buildPlayerHeader(isCpuHeader: true),
                  const SizedBox(height: 6),

                  Expanded(
                    child: Center(
                      child: _buildCleanBoard(),
                    ),
                  ),

                  const SizedBox(height: 6),
                  _buildPlayerHeader(isCpuHeader: false),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: _buildActionBar(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSideSelectionScreen() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentTextColor = isDark ? const Color(0xFFF5F5F7) : const Color(0xFF2B1810);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F1115) : const Color(0xFFF7F4F0),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: accentTextColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "CHOOSE YOUR SIDE",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 3, color: accentTextColor),
              ),
              const SizedBox(height: 8),
              Text(
                "AI Level: Medium Intellect",
                style: TextStyle(fontSize: 13, color: accentTextColor.withOpacity(0.5), fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 48),

              _buildSideCard(
                title: "Play as White",
                subtitle: "Command light forces. Moves first.",
                isWhitePiece: true,
                onTap: () {
                  setState(() {
                    _userColor = chess.Color.WHITE;
                    _hasChosenSide = true;
                  });
                },
              ),
              const SizedBox(height: 20),

              _buildSideCard(
                title: "Play as Black",
                subtitle: "Command dark forces. Counter strategy.",
                isWhitePiece: false,
                onTap: () {
                  setState(() {
                    _userColor = chess.Color.BLACK;
                    _hasChosenSide = true;
                  });
                  _triggerAiMove();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSideCard({
    required String title,
    required String subtitle,
    required bool isWhitePiece,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textThemeColor = isDark ? Colors.white : const Color(0xFF2B1810);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.brown[900]!.withOpacity(0.08),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 15,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.26),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 24,
                backgroundColor: isWhitePiece ? Colors.white : const Color(0xFF2C2E33),
                child: Icon(Icons.shield_rounded, color: isWhitePiece ? const Color(0xFF8B94A6) : Colors.white, size: 24),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: textThemeColor)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: textThemeColor.withOpacity(0.6))),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: textThemeColor.withOpacity(0.3)),
          ],
        ),
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
            "VS COMPUTER",
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

  Widget _buildPlayerHeader({required bool isCpuHeader}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    bool isCpuTurn = game.turn != _userColor;
    bool isActiveTurn = isCpuHeader ? isCpuTurn : !isCpuTurn;

    String headerName = isCpuHeader ? "Computer" : "Player";
    bool renderingWhiteIndicator = isCpuHeader ? (_userColor == chess.Color.BLACK) : (_userColor == chess.Color.WHITE);

    bool isCurrentColorInCheck = game.in_check && (isCpuHeader ? isCpuTurn : !isCpuTurn);
    bool isCurrentColorMated = game.in_checkmate && (isCpuHeader ? isCpuTurn : !isCpuTurn);

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
              : (isActiveTurn ? (isDark ? Colors.white.withOpacity(0.03) : Colors.white) : Colors.transparent)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isCurrentColorMated
                ? Colors.red
                : (isCurrentColorInCheck
                ? Theme.of(context).colorScheme.error.withOpacity(0.5)
                : (isActiveTurn ? primaryColor.withOpacity(0.2) : Colors.transparent)),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: renderingWhiteIndicator ? Colors.white : const Color(0xFF2C2E33),
              child: Icon(
                isCpuHeader ? Icons.memory_rounded : Icons.person_rounded,
                color: renderingWhiteIndicator ? const Color(0xFF8B94A6) : Colors.white,
                size: 14,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              headerName,
              style: TextStyle(fontSize: 13, fontWeight: isActiveTurn ? FontWeight.bold : FontWeight.w600),
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
            else if (isActiveTurn && !game.game_over)
                Text(
                  isCpuHeader ? "Processing..." : "Your Turn",
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
        final s = _indexToSquare(i);

        List<int> coords = _squareToCoords(s);
        final darkSquare = (coords[0] + coords[1]) % 2 == 1;

        final piece = game.get(s);
        final selected = s == selectedSquare;
        final last = s == lastFrom || s == lastTo;
        final hint = moves.contains(s);
        final isCapture = hint && piece != null;

        Color base = darkSquare ? const Color(0xFFB58863) : const Color(0xFFF0D9B5);
        if (last) base = const Color(0xFFBAC146).withOpacity(0.6);
        if (selected) base = const Color(0xFFBAC146);

        return GestureDetector(
          onTap: () => tap(coords[0], coords[1]),
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
            color: _undoStack.isNotEmpty && !_isAiThinking ? primaryColor : Colors.grey.withOpacity(0.4),
            tooltip: 'Undo Move',
            onPressed: _undoStack.isNotEmpty && !_isAiThinking ? _handleUndo : null,
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