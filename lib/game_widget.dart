import 'package:flutter/material.dart';
import 'nova_blaster_game.dart';

class GameWidget extends StatelessWidget {
  final VoidCallback? onExit;
  
  const GameWidget({super.key, this.onExit});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1F),
      body: SafeArea(
        child: NovaBlasterGame(
          onExit: onExit ?? () => Navigator.pop(context),
        ),
      ),
    );
  }
}
