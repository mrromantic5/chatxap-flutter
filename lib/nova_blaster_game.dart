import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async'; // ADDED: For Ticker
import 'game_audio.dart';
import 'game_particles.dart';

class NovaBlasterGame extends StatefulWidget {
  final VoidCallback? onExit;
  
  const NovaBlasterGame({super.key, this.onExit});

  @override
  State<NovaBlasterGame> createState() => _NovaBlasterGameState();
}

class _NovaBlasterGameState extends State<NovaBlasterGame> with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  
  double _width = 0, _height = 0;
  bool _isPlaying = true;
  int _score = 0, _highScore = 0, _level = 1, _lives = 3;
  bool _isGameOver = false, _isPaused = false;
  
  double _playerX = 0, _playerY = 0;
  final double _playerSize = 30;
  double _playerSpeed = 300, _shootCooldown = 0;
  final double _shootDelay = 0.15; // CHANGED: Made final
  
  List<Enemy> _enemies = [];
  List<Bullet> _bullets = [], _enemyBullets = [];
  List<Powerup> _powerups = [];
  late ParticleSystem _particles;
  List<ParallaxStar> _parallaxStars = [];
  
  Offset? _touchPos;
  int _combo = 0, _maxCombo = 0, _enemiesKilled = 0;
  double _comboTimer = 0, _enemySpawnTimer = 0;
  double _enemySpawnDelay = 1.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_gameLoop);
    _ticker.start();
    _particles = ParticleSystem();
    GameAudio.initialize();
    _initParallax();
  }

  @override
  void dispose() {
    _ticker.dispose();
    GameAudio.stopBackgroundMusic();
    super.dispose();
  }

  void _initParallax() {
    final random = Random();
    for (int i = 0; i < 80; i++) {
      _parallaxStars.add(ParallaxStar(
        x: random.nextDouble() * 400,
        y: random.nextDouble() * 800,
        speed: 20 + random.nextDouble() * 80,
        size: 0.5 + random.nextDouble() * 2,
        brightness: 0.3 + random.nextDouble() * 0.7,
      ));
    }
  }

  void _gameLoop(Duration elapsed) {
    if (!_isPlaying || _isPaused || _isGameOver) return;
    
    final delta = elapsed.inMilliseconds / 1000.0;
    
    for (final star in _parallaxStars) {
      star.y += star.speed * delta;
      if (star.y > _height) {
        star.y = -2;
        star.x = Random().nextDouble() * _width;
      }
    }
    
    if (_touchPos != null) {
      final dx = _touchPos!.dx - _playerX;
      final dy = _touchPos!.dy - _playerY;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist > 5) {
        final speed = min(_playerSpeed * delta, dist);
        _playerX += dx / dist * speed;
        _playerY += dy / dist * speed;
      }
    }
    
    _playerX = _playerX.clamp(_playerSize / 2, _width - _playerSize / 2);
    _playerY = _playerY.clamp(_playerSize / 2, _height - _playerSize / 2);
    
    _shootCooldown -= delta;
    if (_shootCooldown <= 0) {
      _bullets.add(Bullet(
        x: _playerX, y: _playerY - _playerSize / 2,
        vx: 0, vy: -800, size: 4, color: Colors.cyan,
      ));
      _particles.emitTrail(_playerX, _playerY - _playerSize / 2, color: Colors.cyan);
      GameAudio.playShoot();
      _shootCooldown = _shootDelay;
    }
    
    _enemySpawnTimer -= delta;
    if (_enemySpawnTimer <= 0) {
      _spawnEnemy();
      _enemySpawnTimer = max(0.3, _enemySpawnDelay - (_level - 1) * 0.05);
    }
    
    _updateEnemies(delta);
    _updateBullets(delta);
    _particles.update(delta);
    
    if (_combo > 0) {
      _comboTimer -= delta;
      if (_comboTimer <= 0) { _combo = 0; _comboTimer = 0; }
    }
    
    if (_enemiesKilled >= _level * 10) _levelUp();
    
    setState(() {});
  }

  void _spawnEnemy() {
    final random = Random();
    final x = random.nextDouble() * (_width - 40) + 20;
    final type = random.nextDouble();
    
    Enemy enemy;
    if (type < 0.6) {
      enemy = Enemy.basic(x: x, y: -20, level: _level);
    } else if (type < 0.85) {
      enemy = Enemy.fast(x: x, y: -20, level: _level);
    } else {
      enemy = Enemy.tank(x: x, y: -20, level: _level);
    }
    _enemies.add(enemy);
  }

  void _updateEnemies(double delta) {
    for (int i = _enemies.length - 1; i >= 0; i--) {
      final enemy = _enemies[i];
      enemy.y += enemy.speed * delta;
      
      if (enemy.y > _height + 20) {
        _enemies.removeAt(i);
        _lives--;
        if (_lives <= 0) _gameOver();
        continue;
      }
      
      if (enemy.y > 50 && Random().nextDouble() < 0.02 * delta * 60) {
        _enemyBullets.add(Bullet(
          x: enemy.x, y: enemy.y + enemy.size / 2,
          vx: 0, vy: 400, size: 3, color: Colors.purple,
          isEnemy: true,
        ));
      }
      
      if ((enemy.y + enemy.size / 2 > _playerY - _playerSize / 2) &&
          (enemy.y - enemy.size / 2 < _playerY + _playerSize / 2) &&
          (enemy.x + enemy.size / 2 > _playerX - _playerSize / 2) &&
          (enemy.x - enemy.size / 2 < _playerX + _playerSize / 2)) {
        _playerHit();
        _particles.emitExplosion(enemy.x, enemy.y, count: 40, color: Colors.red);
        _enemies.removeAt(i);
      }
    }
  }

  void _updateBullets(double delta) {
    for (int i = _bullets.length - 1; i >= 0; i--) {
      final bullet = _bullets[i];
      bullet.x += bullet.vx * delta;
      bullet.y += bullet.vy * delta;
      
      if (bullet.y < -20) { _bullets.removeAt(i); continue; }
      
      bool hit = false;
      for (int j = _enemies.length - 1; j >= 0; j--) {
        final enemy = _enemies[j];
        if ((bullet.y < enemy.y + enemy.size / 2) &&
            (bullet.y > enemy.y - enemy.size / 2) &&
            (bullet.x < enemy.x + enemy.size / 2) &&
            (bullet.x > enemy.x - enemy.size / 2)) {
          enemy.health--;
          if (enemy.health <= 0) {
            _enemiesKilled++;
            _combo++;
            _comboTimer = 2.0;
            if (_combo > _maxCombo) _maxCombo = _combo;
            _score += enemy.points * (1 + _combo ~/ 5);
            _particles.emitExplosion(enemy.x, enemy.y, count: 50, color: enemy.color);
            GameAudio.playExplosion();
            if (Random().nextDouble() < 0.1) {
              _powerups.add(Powerup(
                x: enemy.x, y: enemy.y,
                type: PowerupType.values[Random().nextInt(4)],
              ));
            }
            _enemies.removeAt(j);
          } else {
            GameAudio.playHit();
            _particles.emitExplosion(bullet.x, bullet.y, count: 10, color: Colors.white);
          }
          hit = true;
          break;
        }
      }
      if (hit) _bullets.removeAt(i);
    }
    
    for (int i = _enemyBullets.length - 1; i >= 0; i--) {
      final bullet = _enemyBullets[i];
      bullet.x += bullet.vx * delta;
      bullet.y += bullet.vy * delta;
      
      if (bullet.y > _height + 20) { _enemyBullets.removeAt(i); continue; }
      
      if ((bullet.y > _playerY - _playerSize / 2) &&
          (bullet.y < _playerY + _playerSize / 2) &&
          (bullet.x > _playerX - _playerSize / 2) &&
          (bullet.x < _playerX + _playerSize / 2)) {
        _playerHit();
        _enemyBullets.removeAt(i);
      }
    }
  }

  void _playerHit() {
    _lives--;
    _particles.emitExplosion(_playerX, _playerY, count: 20, color: Colors.white);
    GameAudio.playHit();
    if (_lives <= 0) _gameOver();
  }

  void _levelUp() {
    _level++;
    _enemiesKilled = 0;
    _enemySpawnDelay = max(0.3, _enemySpawnDelay - 0.05);
    GameAudio.playLevelUp();
    _particles.emitExplosion(_width / 2, _height / 2, count: 100, color: Colors.amber); // FIXED: gold → amber
  }

  void _gameOver() {
    _isGameOver = true;
    _isPlaying = false;
    _particles.emitExplosion(_playerX, _playerY, count: 60, color: Colors.red);
    GameAudio.playGameOver();
    if (_score > _highScore) _highScore = _score;
    setState(() {});
  }

  void _restartGame() {
    setState(() {
      _isGameOver = false;
      _isPlaying = true;
      _score = 0;
      _level = 1;
      _lives = 3;
      _enemies.clear();
      _bullets.clear();
      _enemyBullets.clear();
      _powerups.clear();
      _particles.clear();
      _combo = 0;
      _maxCombo = 0;
      _enemiesKilled = 0;
      _enemySpawnTimer = 0;
      _playerSpeed = 300;
      // REMOVED: _shootDelay = 0.15; (it's final)
      _shootCooldown = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1F),
      body: GestureDetector(
        onPanDown: (details) => _touchPos = details.localPosition,
        onPanUpdate: (details) => _touchPos = details.localPosition,
        onPanEnd: (_) => _touchPos = null,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _width = constraints.maxWidth;
            _height = constraints.maxHeight;
            return Stack(
              children: [
                CustomPaint(
                  painter: GamePainter(
                    playerX: _playerX,
                    playerY: _playerY,
                    playerSize: _playerSize,
                    bullets: _bullets,
                    enemyBullets: _enemyBullets,
                    enemies: _enemies,
                    powerups: _powerups,
                    particles: _particles,
                    parallaxStars: _parallaxStars,
                    isGameOver: _isGameOver,
                  ),
                  size: Size(_width, _height),
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _hudText('Score: $_score', Colors.white),
                      _hudText('Level: $_level', Colors.cyan),
                      _hudText('Lives: ${"❤️" * _lives}', Colors.red),
                      if (_combo > 0) _hudText('Combo: ${_combo}x', Colors.amber),
                    ],
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: _hudText('HI: $_highScore', Colors.amber, 14),
                ),
                if (_isGameOver)
                  Container(
                    color: Colors.black.withOpacity(0.7),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('GAME OVER',
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            )),
                          const SizedBox(height: 20),
                          _hudText('Score: $_score', Colors.white, 24),
                          _hudText('Best: $_highScore', Colors.amber, 20),
                          const SizedBox(height: 30),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _gameBtn('Restart', Colors.cyan, _restartGame),
                              const SizedBox(width: 20),
                              _gameBtn('Exit', Colors.grey, () => widget.onExit?.call()),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: IconButton(
                    icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause,
                        color: Colors.white, size: 30),
                    onPressed: () => setState(() => _isPaused = !_isPaused),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _hudText(String text, Color color, [double size = 16]) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.bold,
        shadows: [Shadow(
          color: Colors.black.withOpacity(0.5),
          blurRadius: 4,
          offset: const Offset(2, 2),
        )],
      ),
    );
  }

  Widget _gameBtn(String label, Color color, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }
}

enum EnemyType { basic, fast, tank }
enum PowerupType { shield, speed, rapidFire, bomb }

class Enemy {
  double x, y, speed, size;
  int health, points, maxHealth;
  EnemyType type;
  Color color;
  
  Enemy.basic({required this.x, required this.y, int level = 1})
      : type = EnemyType.basic,
        color = Colors.red,
        speed = 100 + Random().nextDouble() * 50 + level * 5,
        health = 1,
        maxHealth = 1,
        size = 25,
        points = 10;
  
  Enemy.fast({required this.x, required this.y, int level = 1})
      : type = EnemyType.fast,
        color = Colors.orange,
        speed = 250 + Random().nextDouble() * 100 + level * 10,
        health = 1,
        maxHealth = 1,
        size = 20,
        points = 20;
  
  Enemy.tank({required this.x, required this.y, int level = 1})
      : type = EnemyType.tank,
        color = Colors.purple,
        speed = 60 + Random().nextDouble() * 30 + level * 2,
        health = 2 + (level ~/ 3),
        maxHealth = 2 + (level ~/ 3),
        size = 35,
        points = 30;
}

class Bullet {
  double x, y, vx, vy, size;
  Color color;
  bool isEnemy;
  
  Bullet({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    this.size = 4,
    this.color = Colors.cyan,
    this.isEnemy = false,
  });
}

class Powerup {
  double x, y;
  PowerupType type;
  
  Powerup({required this.x, required this.y, required this.type});
}

class ParallaxStar {
  double x, y, speed, size, brightness;
  
  ParallaxStar({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.brightness,
  });
}

class GamePainter extends CustomPainter {
  final double playerX, playerY, playerSize;
  final List<Bullet> bullets, enemyBullets;
  final List<Enemy> enemies;
  final List<Powerup> powerups;
  final ParticleSystem particles;
  final List<ParallaxStar> parallaxStars;
  final bool isGameOver;
  
  GamePainter({
    required this.playerX,
    required this.playerY,
    required this.playerSize,
    required this.bullets,
    required this.enemyBullets,
    required this.enemies,
    required this.powerups,
    required this.particles,
    required this.parallaxStars,
    required this.isGameOver,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF0A0F1F);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);
    
    for (final star in parallaxStars) {
      final paint = Paint()
        ..color = Colors.white.withOpacity(star.brightness)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(star.x, star.y), star.size, paint);
    }
    
    particles.draw(canvas);
    
    for (final bullet in enemyBullets) {
      final paint = Paint()..color = Colors.purple..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(bullet.x, bullet.y), bullet.size, paint);
    }
    
    for (final enemy in enemies) {
      final paint = Paint()..color = enemy.color..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(enemy.x, enemy.y), enemy.size, paint);
    }
    
    for (final bullet in bullets) {
      final paint = Paint()..color = Colors.cyan..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(bullet.x, bullet.y), bullet.size, paint);
    }
    
    if (!isGameOver) {
      final paint = Paint()..color = Colors.cyan..style = PaintingStyle.fill;
      final path = Path();
      path.moveTo(playerX, playerY - playerSize / 2);
      path.lineTo(playerX - playerSize / 2, playerY + playerSize / 2);
      path.lineTo(playerX + playerSize / 2, playerY + playerSize / 2);
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
