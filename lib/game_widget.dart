import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'nova_blaster_game.dart';

/// Full-screen immersive wrapper for NOVA BLASTER.
/// Forces landscape-excluded portrait, hides system UI overlays.
class GameWidget extends StatefulWidget {
  final VoidCallback? onExit;
  const GameWidget({super.key, this.onExit});
  @override
  State<GameWidget> createState() => _GameWidgetState();
}

class _GameWidgetState extends State<GameWidget> {
  @override
  void initState() {
    super.initState();
    // Enter full immersive mode (hide status + nav bars)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // Restore normal UI when leaving game
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020509),
      body: NovaBlasterGame(
        onExit: widget.onExit ?? () => Navigator.pop(context),
      ),
    );
  }
}
