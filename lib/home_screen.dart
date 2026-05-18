import 'package:flutter/material.dart';
import 'multiplayer.dart';
import 'computer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late final AnimationController _entranceController;

  // Staggered Component Entrance Animations
  late final Animation<double> _logoScale;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _menuFade;
  late final Animation<Offset> _menuSlide;
  late final Animation<double> _footerFade;
  late final Animation<double> _bgScale;

  @override
  void initState() {
    super.initState();

    // --- ENTRANCE ANIMATION CONFIGURATION ---
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    // --- STAGGERED INTERVAL INTERPOLATION ---

    // Background soft scaling on entrance
    _bgScale = Tween<double>(begin: 0.85, end: 1.0).animate(CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOutCubic),
    ));

    // Logo pop-in spring curve
    _logoScale = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.1, 0.6, curve: Curves.elasticOut),
    );

    // Title text slide & fade
    _titleFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.3, 0.7, curve: Curves.easeOut),
    );
    _titleSlide = Tween<Offset>(begin: const Offset(0.0, 0.25), end: Offset.zero).animate(CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.3, 0.7, curve: Curves.easeOutBack),
    ));

    // Interactive action menu cards slide & fade
    _menuFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.5, 0.9, curve: Curves.easeOut),
    );
    _menuSlide = Tween<Offset>(begin: const Offset(0.0, 0.35), end: Offset.zero).animate(CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.5, 0.9, curve: Curves.easeOutBack),
    ));

    // Elegant footer brand reveal
    _footerFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
    );

    // Start entrance stagger pipeline
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  /// Spatial Page Transition Pipeline Engine
  void _navigateToPage(BuildContext context, Widget destinationPage) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => destinationPage,
        transitionDuration: const Duration(milliseconds: 550),
        reverseTransitionDuration: const Duration(milliseconds: 450),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final fadeCurve = CurvedAnimation(parent: animation, curve: Curves.easeInOut);

          final exitScale = Tween<double>(begin: 1.0, end: 1.05).animate(
            CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeInOutCubic),
          );

          final entryScale = Tween<double>(begin: 0.94, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          );

          return FadeTransition(
            opacity: Tween<double>(begin: 0.0, end: 1.0).animate(fadeCurve),
            child: ScaleTransition(
              scale: animation.isCompleted ? exitScale : entryScale,
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const accentColor = Color(0xFFC19A6B);
    const darkBg = Color(0xFF0F1115);

    const goldPrimary = Color(0xFFD4AF37);
    const goldHighlight = Color(0xFFF6E27A);
    const goldShadow = Color(0xFF8C6A1F);
    const goldGlow = Color(0xFFFFD76A);

    return Scaffold(
      backgroundColor: darkBg,
      body: Stack(
        children: [
          // --- BACKGROUND DECORATION (PULSE REMOVED, NOW STABLE) ---
          Positioned(
            top: -100,
            right: -100,
            child: ScaleTransition(
              scale: _bgScale,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor.withValues(alpha: 0.04),
                ),
              ),
            ),
          ),

          // --- CORE VIEWPORT LAYOUT SHEET ---
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 60),

                      // --- HERO SECTION (PULSE REMOVED, NOW STABLE) ---
                      Center(
                        child: ScaleTransition(
                          scale: _logoScale,
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: accentColor.withValues(alpha: 0.2), width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: accentColor.withValues(alpha: 0.06),
                                  blurRadius: 35,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(60),
                              child: Image.asset(
                                'assets/logo.png',
                                width: 110,
                                height: 110,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) => const Icon(
                                  Icons.grid_4x4_rounded,
                                  size: 80,
                                  color: accentColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 40),

                      // --- TYPOGRAPHY HERO TITLE SECTION ---
                      FadeTransition(
                        opacity: _titleFade,
                        child: SlideTransition(
                          position: _titleSlide,
                          child: Column(
                            children: [
                              Text(
                                'CHESS',
                                style: TextStyle(
                                  fontSize: 56,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 12,
                                  height: 0.9,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black.withValues(alpha: 0.5),
                                      offset: const Offset(0, 4),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                'MASTER',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w300,
                                  color: goldPrimary,
                                  letterSpacing: 18,
                                  shadows: [
                                    Shadow(
                                      color: goldGlow.withValues(alpha: 0.3),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const Spacer(),

                      // --- SYSTEM INTERACTIVE ACTION MENU BLOCK ---
                      FadeTransition(
                        opacity: _menuFade,
                        child: SlideTransition(
                          position: _menuSlide,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                            child: Column(
                              children: [
                                _buildModernButton(
                                  context,
                                  label: 'PLAY VS COMPUTER',
                                  icon: Icons.computer_rounded,
                                  isPrimary: true,
                                  onPressed: () => _navigateToPage(context, const ComputerGamePage()),
                                ),
                                const SizedBox(height: 20),
                                _buildModernButton(
                                  context,
                                  label: 'LOCAL MULTIPLAYER',
                                  icon: Icons.people_alt_rounded,
                                  isPrimary: false,
                                  onPressed: () => _navigateToPage(context, const ChessBoardPage()),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const Spacer(),

                      // --- REFINED SHADER METADATA FOOTER ---
                      FadeTransition(
                        opacity: _footerFade,
                        child: Column(
                          children: [
                            Text(
                              'MADE BY',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withValues(alpha: 0.3),
                                  letterSpacing: 4),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 1,
                              width: 40,
                              color: accentColor.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'ABHISHEK SHAH',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 3,
                                foreground: Paint()
                                  ..shader = const LinearGradient(
                                    colors: [
                                      goldShadow,
                                      goldPrimary,
                                      goldHighlight,
                                      goldPrimary,
                                      goldShadow,
                                    ],
                                    stops: [0.0, 0.25, 0.5, 0.75, 1.0],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ).createShader(
                                    const Rect.fromLTWH(0.0, 0.0, 300.0, 70.0),
                                  ),
                                shadows: [
                                  Shadow(
                                    color: goldGlow.withValues(alpha: 0.2),
                                    offset: const Offset(0, 2),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernButton(
      BuildContext context, {
        required String label,
        required IconData icon,
        required bool isPrimary,
        required VoidCallback onPressed,
      }) {
    const goldPrimary = Color(0xFFD4AF37);
    const goldHighlight = Color(0xFFF6E27A);
    const goldShadow = Color(0xFF8C6A1F);

    return _InteractiveLiftCard(
      isPrimary: isPrimary,
      goldPrimary: goldPrimary,
      goldHighlight: goldHighlight,
      goldShadow: goldShadow,
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            Icon(
              icon,
              color: isPrimary ? Colors.white : goldPrimary,
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isPrimary ? Colors.white : Colors.white.withValues(alpha: 0.9),
                  letterSpacing: 1.5,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isPrimary ? Colors.white.withValues(alpha: 0.5) : goldPrimary.withValues(alpha: 0.5),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _InteractiveLiftCard extends StatefulWidget {
  final Widget child;
  final bool isPrimary;
  final Color goldPrimary;
  final Color goldHighlight;
  final Color goldShadow;
  final VoidCallback onPressed;

  const _InteractiveLiftCard({
    required this.child,
    required this.isPrimary,
    required this.goldPrimary,
    required this.goldHighlight,
    required this.goldShadow,
    required this.onPressed,
  });

  @override
  State<_InteractiveLiftCard> createState() => _InteractiveLiftCardState();
}

class _InteractiveLiftCardState extends State<_InteractiveLiftCard> with SingleTickerProviderStateMixin {
  AnimationController? _pressController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _elevationGlow;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.965).animate(
      CurvedAnimation(parent: _pressController!, curve: Curves.easeOutCubic),
    );

    _elevationGlow = Tween<double>(begin: 1.0, end: 0.4).animate(
      CurvedAnimation(parent: _pressController!, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _pressController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_pressController == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _pressController!,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            width: double.infinity,
            height: 65,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: widget.isPrimary
                  ? LinearGradient(
                colors: [widget.goldShadow, widget.goldPrimary, widget.goldHighlight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
                  : null,
              border: !widget.isPrimary ? Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.5) : null,
              boxShadow: widget.isPrimary
                  ? [
                BoxShadow(
                  color: widget.goldPrimary.withValues(alpha: 0.3 * _elevationGlow.value),
                  blurRadius: 18 * _elevationGlow.value,
                  offset: Offset(0, 8 * _elevationGlow.value),
                )
              ]
                  : [],
            ),
            child: child,
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTapDown: (_) => _pressController?.forward(),
          onTapCancel: () => _pressController?.reverse(),
          onTap: () async {
            if (_pressController != null) {
              await _pressController!.forward();
              _pressController!.reverse();
            }
            widget.onPressed();
          },
          borderRadius: BorderRadius.circular(16),
          child: widget.child,
        ),
      ),
    );
  }
}