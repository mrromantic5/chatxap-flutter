import 'dart:math';
import 'package:flutter/material.dart';

class Particle {
  double x, y, vx, vy, size, life, maxLife;
  Color color;
  bool glowing;
  
  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    this.size = 3,
    this.color = Colors.cyan,
    this.life = 1.0,
    this.maxLife = 1.0,
    this.glowing = false,
  });
  
  bool update(double delta) {
    x += vx * delta;
    y += vy * delta;
    life -= delta / maxLife;
    size *= (1 - delta / maxLife * 0.3);
    return life > 0;
  }
  
  void draw(Canvas canvas) {
    final alpha = (life * 255).toInt().clamp(0, 255);
    final paint = Paint()
      ..color = color.withAlpha(alpha)
      ..style = PaintingStyle.fill;
    
    if (glowing) {
      final glowPaint = Paint()
        ..color = color.withAlpha((alpha * 0.3).toInt())
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(Offset(x, y), size * 2, glowPaint);
    }
    
    canvas.drawCircle(Offset(x, y), size, paint);
  }
}

class ParticleSystem {
  List<Particle> _particles = [];
  final Random _random = Random();
  
  void emitExplosion(double x, double y, {int count = 30, Color? color}) {
    for (int i = 0; i < count; i++) {
      final angle = _random.nextDouble() * 2 * pi;
      final speed = 50 + _random.nextDouble() * 200;
      _particles.add(Particle(
        x: x + _random.nextDouble() * 10 - 5,
        y: y + _random.nextDouble() * 10 - 5,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        size: 2 + _random.nextDouble() * 6,
        color: color ?? Colors.orangeAccent,
        life: 0.5 + _random.nextDouble() * 0.5,
        maxLife: 0.5 + _random.nextDouble() * 0.5,
        glowing: true,
      ));
    }
  }
  
  void emitTrail(double x, double y, {Color? color}) {
    _particles.add(Particle(
      x: x + _random.nextDouble() * 4 - 2,
      y: y + _random.nextDouble() * 4 - 2,
      vx: _random.nextDouble() * 10 - 5,
      vy: _random.nextDouble() * 10 - 5,
      size: 1 + _random.nextDouble() * 3,
      color: color ?? Colors.cyan,
      life: 0.2 + _random.nextDouble() * 0.3,
      maxLife: 0.2 + _random.nextDouble() * 0.3,
      glowing: false,
    ));
  }
  
  void update(double delta) {
    _particles.removeWhere((p) => !p.update(delta));
  }
  
  void draw(Canvas canvas) {
    for (final particle in _particles) {
      particle.draw(canvas);
    }
  }
  
  void clear() {
    _particles.clear();
  }
}
