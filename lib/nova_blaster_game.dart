import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'game_audio.dart';

// ══════════════════════════════════════════════════════════════ ENUMS
enum EnemyType { drone, fighter, destroyer }
enum PUType    { shield, rapid, triple, life, bomb }
enum Phase     { title, playing, levelUp, gameOver, paused }

// ══════════════════════════════════════════════════════════════ PALETTE
const _kBg1     = Color(0xFF020509);
const _kBg2     = Color(0xFF0B1020);
const _kAccent  = Color(0xFF4DA3FF);
const _kCyan    = Color(0xFF00E5FF);
const _kGold    = Color(0xFFFFD700);
const _kRed     = Color(0xFFFF4D6D);
const _kOrange  = Color(0xFFFF7043);
const _kPurple  = Color(0xFFA855F7);
const _kGreen   = Color(0xFF6BFF6B);

// ══════════════════════════════════════════════════════════════ CONSTANTS
const _kBaseFireDelay  = 0.28;
const _kRapidFireDelay = 0.11;
const _kInvDur     = 2.2;
const _kShieldDur  = 9.0;
const _kPowerDur   = 10.0;
const _kComboTO    = 3.2;
const _kShakeDur   = 0.40;
const _kShakeMag   = 9.0;
const _kLvlDur     = 2.6;
const _kShipR      = 20.0;

// ══════════════════════════════════════════════════════════════ ENTITIES

class _Star {
  double x, y, spd, size, alpha;
  final int layer;
  _Star(this.x, this.y, this.spd, this.size, this.alpha, this.layer);
}

class _Nebula {
  final double x, y, r;
  final Color col;
  _Nebula(this.x, this.y, this.r, this.col);
}

/// Floating score / combo label that drifts upward and fades out.
class _Label {
  double x, y;
  final double vy;
  double life;
  final String text;
  final Color col;
  final double fontSize;
  _Label(this.x, this.y, this.text, this.col, {this.vy = -85, this.life = 0.85, this.fontSize = 18});
  bool get dead => life <= 0;
  void update(double dt) { y += vy * dt; life -= dt * 1.4; }
}

class _Ptcl {
  double x, y, vx, vy, life, size;
  Color col;
  final bool spark;
  _Ptcl({required this.x, required this.y, required this.vx, required this.vy,
         required this.life, required this.size, required this.col,
         this.spark = false});
  bool get dead => life <= 0;
  void update(double dt) {
    x += vx * dt; y += vy * dt;
    vy += 55 * dt; vx *= (1 - dt * 1.8);
    life -= dt * 2.4;
    if (size > 0.4) size -= dt * size * 0.9;
  }
}

class _Bullet {
  double x, y, vx, vy;
  final bool enemy;
  bool dead = false;
  _Bullet(this.x, this.y, this.vx, this.vy, {this.enemy = false});
  void update(double dt) { x += vx * dt; y += vy * dt; }
}

class _Enemy {
  double x, y, vy, rot = 0, rotSpd, flash = 0;
  double baseX, oscPhase, oscAmp, shootTimer;
  final EnemyType type;
  late int hp, maxHp;
  bool dead = false;
  late double cr;
  late int score;
  late Color col;

  _Enemy(this.x, this.y, this.type, this.vy, this.rotSpd,
         this.oscPhase, this.oscAmp, this.shootTimer)
      : baseX = x {
    switch (type) {
      case EnemyType.drone:
        hp = maxHp = 1; cr = 19; score = 10; col = const Color(0xFFFF6B3D);
      case EnemyType.fighter:
        hp = maxHp = 1; cr = 14; score = 20; col = _kCyan;
      case EnemyType.destroyer:
        hp = maxHp = 5; cr = 28; score = 50; col = _kPurple;
    }
  }

  void update(double dt, double sw) {
    y += vy * dt;
    rot += rotSpd * dt;
    oscPhase += dt * (type == EnemyType.fighter ? 2.2 : 1.4);
    x = baseX + sin(oscPhase) * oscAmp;
    x = x.clamp(cr, sw - cr);
    shootTimer -= dt;
    if (flash > 0) flash -= dt * 5;
  }
}

class _PU {
  double x, y, rot = 0, pulse = 0;
  final PUType type;
  bool dead = false;
  static const vy = 105.0, r = 15.0;
  _PU(this.x, this.y, this.type);
  void update(double dt) { y += vy * dt; rot += dt * 2.8; pulse += dt * 3.2; }
}

// ══════════════════════════════════════════════════════════════ GAME STATE

class _GS {
  final rng = Random();
  double sw = 0, sh = 0, time = 0;

  Phase phase = Phase.title;
  int score = 0, hi = 0, lives = 3, level = 1, combo = 0;
  double comboTimer = 0;

  // Ship
  double shipX = 0, shipY = 0, targetX = 0, targetY = 0;
  bool shield = false, rapid = false, triple = false;
  int bombs = 0;
  double shieldT = 0, rapidT = 0, tripleT = 0;
  double invT = 0, flashT = 0, engineFlicker = 0;
  List<Offset> trail = [];

  // World objects
  List<_Star>   stars   = [];
  List<_Nebula> nebulae = [];
  List<_Enemy>  enemies = [];
  List<_Bullet> bullets = [];
  List<_Ptcl>   ptcls   = [];
  List<_PU>     pus     = [];
  List<_Label>  labels  = [];

  // Timers / level progress
  double fireT = 0, spawnT = 0, lvlT = 0;
  int kills = 0;
  double shakeT = 0, flashScreen = 0, titleAnim = 0;

  // ── Difficulty scaling ──────────────────────────────────────────────────
  double get spawnInterval => (1.4 - level * 0.09).clamp(0.32, 1.4);
  double get enemySpeed    => (100 + level * 22).toDouble();
  int    get killsForLevel => 10 + level * 4;

  void initWorld(double w, double h) {
    sw = w; sh = h;
    shipX = targetX = w / 2;
    shipY = targetY = h - 130;

    stars = List.generate(150, (i) {
      final l = i % 3;
      return _Star(
        rng.nextDouble() * w, rng.nextDouble() * h,
        10 + l * 19 + rng.nextDouble() * 12,
        0.4 + l * 0.55 + rng.nextDouble() * 0.65,
        0.18 + l * 0.20 + rng.nextDouble() * 0.28,
        l,
      );
    });

    nebulae = [
      _Nebula(w * 0.14, h * 0.22, 235, const Color(0xFF1A3A8A)),
      _Nebula(w * 0.86, h * 0.10, 190, const Color(0xFF3A1A6A)),
      _Nebula(w * 0.50, h * 0.65, 210, const Color(0xFF0A3A5A)),
      _Nebula(w * 0.28, h * 0.50, 160, const Color(0xFF162055)),
    ];
  }

  void reset() {
    score = 0; lives = 3; level = 1; combo = 0; comboTimer = 0;
    shield = rapid = triple = false; bombs = 0;
    shieldT = rapidT = tripleT = invT = flashT = 0;
    enemies.clear(); bullets.clear(); ptcls.clear();
    pus.clear(); trail.clear(); labels.clear();
    fireT = spawnT = 0; kills = 0;
    shakeT = flashScreen = 0;
    phase = Phase.playing;
  }
}

// ══════════════════════════════════════════════════════════════ LOGIC

class _Logic {
  final _GS s;
  _Logic(this.s);

  void update(double dt) {
    s.time += dt;
    _scrollStars(dt);
    _updatePtcls(dt);
    _updateLabels(dt);

    switch (s.phase) {
      case Phase.title:
        s.titleAnim += dt;
      case Phase.levelUp:
        s.lvlT -= dt;
        if (s.lvlT <= 0) s.phase = Phase.playing;
        _moveShip(dt);
        _tickEntities(dt, spawn: false);
      case Phase.playing:
        _moveShip(dt);
        _autoFire(dt);
        _tickEntities(dt, spawn: true);
        _collide();
      default:
        break;
    }
  }

  // ── world ────────────────────────────────────────────────────────────────

  void _scrollStars(double dt) {
    for (final st in s.stars) {
      st.y += st.spd * dt;
      if (st.y > s.sh) { st.y = -4; st.x = s.rng.nextDouble() * s.sw; }
    }
  }

  void _updatePtcls(double dt) {
    for (final p in s.ptcls) p.update(dt);
    s.ptcls.removeWhere((p) => p.dead);
  }

  void _updateLabels(double dt) {
    for (final l in s.labels) l.update(dt);
    s.labels.removeWhere((l) => l.dead);
  }

  // ── ship ─────────────────────────────────────────────────────────────────

  void _moveShip(double dt) {
    s.shipX += (s.targetX - s.shipX) * (1 - pow(0.01,  dt));
    s.shipY += (s.targetY - s.shipY) * (1 - pow(0.008, dt));
    s.shipX = s.shipX.clamp(_kShipR, s.sw - _kShipR);
    s.shipY = s.shipY.clamp(_kShipR, s.sh - _kShipR);
    s.trail.insert(0, Offset(s.shipX, s.shipY));
    if (s.trail.length > 20) s.trail.removeLast();
    s.engineFlicker = sin(s.time * 22) * 0.5 + 0.5;
  }

  void _autoFire(double dt) {
    s.fireT -= dt;
    if (s.fireT > 0) return;
    s.fireT = s.rapid ? _kRapidFireDelay : _kBaseFireDelay;
    if (s.triple) {
      s.bullets.addAll([
        _Bullet(s.shipX, s.shipY - 24, -148, -790),
        _Bullet(s.shipX, s.shipY - 24,    0, -875),
        _Bullet(s.shipX, s.shipY - 24,  148, -790),
      ]);
    } else {
      s.bullets.add(_Bullet(s.shipX, s.shipY - 24, 0, -885));
    }
    GameAudio.playShoot();
  }

  // ── entities ─────────────────────────────────────────────────────────────

  void _tickEntities(double dt, {required bool spawn}) {
    for (final b in s.bullets) b.update(dt);
    s.bullets.removeWhere((b) =>
        b.dead || b.y < -20 || b.y > s.sh + 20 ||
        b.x < -20 || b.x > s.sw + 20);

    for (final e in s.enemies) {
      e.update(dt, s.sw);
      if (e.y > s.sh + 75) e.dead = true;
      if (e.shootTimer <= 0 && !e.dead && e.y > 70) {
        e.shootTimer = _shtInterval(e.type);
        _shootEnemy(e);
      }
    }
    s.enemies.removeWhere((e) => e.dead);

    for (final p in s.pus) p.update(dt);
    s.pus.removeWhere((p) => p.dead || p.y > s.sh + 40);

    _updateTimers(dt);
    if (spawn) _spawnEnemy(dt);
  }

  double _shtInterval(EnemyType t) {
    final base = t == EnemyType.destroyer ? 1.8
               : t == EnemyType.drone     ? 2.8
               : 3.6;
    return (base - s.level * 0.07).clamp(1.1, base);
  }

  void _shootEnemy(_Enemy e) {
    final dx = s.shipX - e.x, dy = s.shipY - e.y;
    final m  = sqrt(dx * dx + dy * dy);
    if (m < 1) return;
    const spd = 315.0;
    s.bullets.add(_Bullet(e.x, e.y, dx / m * spd, dy / m * spd, enemy: true));
  }

  void _spawnEnemy(double dt) {
    s.spawnT -= dt;
    if (s.spawnT > 0) return;
    s.spawnT = s.spawnInterval;
    final roll = s.rng.nextDouble();
    final type = s.level >= 6 && roll < 0.22 ? EnemyType.destroyer
               : s.level >= 2 && roll < 0.48 ? EnemyType.fighter
               : EnemyType.drone;
    final x     = s.rng.nextDouble() * (s.sw - 70) + 35;
    final vy    = s.enemySpeed + s.rng.nextDouble() * 32;
    final rotS  = (s.rng.nextDouble() - 0.5) * 2.8;
    final amp   = 28 + s.rng.nextDouble() * 62;
    final shtT  = 0.8 + s.rng.nextDouble() * 2.2;
    s.enemies.add(_Enemy(x, -55, type, vy, rotS,
        s.rng.nextDouble() * pi * 2, amp, shtT));
  }

  // ── collisions ────────────────────────────────────────────────────────────

  void _collide() {
    // Player bullets → enemies
    for (final b in s.bullets.where((b) => !b.enemy && !b.dead)) {
      for (final e in s.enemies) {
        if (e.dead) continue;
        final dx = b.x - e.x, dy = b.y - e.y;
        if (dx * dx + dy * dy < (e.cr + 5) * (e.cr + 5)) {
          b.dead = true; e.flash = 1.0; e.hp--;
          if (e.hp <= 0) {
            e.dead = true; _killEnemy(e);
          } else {
            GameAudio.playHit();
            _boom(b.x, b.y, Colors.white, 5);
          }
          break;
        }
      }
    }

    if (s.invT > 0) return;

    // Enemies → player
    for (final e in s.enemies) {
      if (e.dead) continue;
      final dx = e.x - s.shipX, dy = e.y - s.shipY;
      if (dx * dx + dy * dy < (e.cr + _kShipR) * (e.cr + _kShipR)) {
        e.dead = true;
        _killEnemy(e, award: false);
        _hitPlayer();
        return;
      }
    }

    // Enemy bullets → player
    for (final b in s.bullets.where((b) => b.enemy && !b.dead)) {
      final dx = b.x - s.shipX, dy = b.y - s.shipY;
      if (dx * dx + dy * dy < 15 * 15) {
        b.dead = true; _hitPlayer(); return;
      }
    }

    // Power-ups → player
    for (final p in s.pus) {
      if (p.dead) continue;
      final dx = p.x - s.shipX, dy = p.y - s.shipY;
      if (dx * dx + dy * dy < (22 + _kShipR) * (22 + _kShipR)) {
        p.dead = true; _collectPU(p.type);
      }
    }
  }

  // ── events ────────────────────────────────────────────────────────────────

  void _hitPlayer() {
    if (s.shield) {
      s.shield = false; s.shieldT = 0;
      _boom(s.shipX, s.shipY, _kCyan, 10);
      s.shakeT = _kShakeDur * 0.5; s.combo = 0;
      _addLabel(s.shipX, s.shipY - 30, 'SHIELD BROKEN!', _kCyan);
      GameAudio.playHit();
      return;
    }
    s.lives--; s.invT = _kInvDur; s.flashT = 0.55;
    s.combo = 0; s.comboTimer = 0;
    s.shakeT = _kShakeDur; s.flashScreen = 0.48;
    _boom(s.shipX, s.shipY, _kAccent, 22);
    GameAudio.playHit();
    if (s.lives <= 0) _endGame();
  }

  void _endGame() {
    s.phase = Phase.gameOver;
    if (s.score > s.hi) s.hi = s.score;
    GameAudio.playGameOver();
    SharedPreferences.getInstance()
        .then((p) => p.setInt('nova_hi', s.hi));
  }

  void _killEnemy(_Enemy e, {bool award = true}) {
    GameAudio.playExplosion();
    final count = 10 + (e.type == EnemyType.destroyer ? 12 : 0);
    _boom(e.x, e.y, e.col, count);
    if (e.type == EnemyType.destroyer) s.shakeT = _kShakeDur * 0.85;

    if (!award) return;

    s.combo++; s.comboTimer = _kComboTO;
    final mult = s.combo >= 10 ? 5 : s.combo >= 6 ? 3 : s.combo >= 3 ? 2 : 1;
    final earned = e.score * mult;
    s.score += earned; s.kills++;

    // Floating score label
    _addLabel(e.x, e.y - 10, '+$earned', e.col);

    // Combo label
    if (s.combo == 3)  _addLabel(e.x, e.y - 34, '×2 COMBO!', _kGold, big: true);
    if (s.combo == 6)  _addLabel(e.x, e.y - 34, '×3 COMBO!', _kGold, big: true);
    if (s.combo == 10) _addLabel(e.x, e.y - 34, '×5 COMBO!', _kGold, big: true);

    if (s.kills >= s.killsForLevel) {
      s.kills = 0; s.level++; s.phase = Phase.levelUp; s.lvlT = _kLvlDur;
      GameAudio.playLevelUp();
    }

    if (s.rng.nextDouble() < 0.17) {
      s.pus.add(_PU(e.x, e.y, PUType.values[s.rng.nextInt(PUType.values.length)]));
    }
  }

  void _collectPU(PUType t) {
    GameAudio.playPowerup();
    String msg;
    Color col;
    switch (t) {
      case PUType.shield: s.shield = true; s.shieldT = _kShieldDur; msg = 'SHIELD ON!';  col = _kCyan;
      case PUType.rapid:  s.rapid  = true; s.rapidT  = _kPowerDur;  msg = 'RAPID FIRE!'; col = _kRed;
      case PUType.triple: s.triple = true; s.tripleT = _kPowerDur;  msg = 'TRIPLE SHOT!';col = _kGold;
      case PUType.life:   if (s.lives < 5) s.lives++; msg = '+ LIFE!'; col = _kGreen;
      case PUType.bomb:   s.bombs++; msg = 'BOMB +1!'; col = const Color(0xFFFF9F43);
    }
    _addLabel(s.shipX, s.shipY - 40, msg, col, big: true);
    _boom(s.shipX, s.shipY, col, 14);
  }

  void _boom(double x, double y, Color col, int n) {
    for (var i = 0; i < n; i++) {
      final ang = s.rng.nextDouble() * 2 * pi;
      final spd = 65 + s.rng.nextDouble() * 230;
      s.ptcls.add(_Ptcl(
        x: x, y: y,
        vx: cos(ang) * spd, vy: sin(ang) * spd - 55,
        life: 0.6 + s.rng.nextDouble() * 0.55,
        size: 2 + s.rng.nextDouble() * 4.5,
        col: Color.lerp(col, Colors.white, s.rng.nextDouble() * 0.5)!,
        spark: s.rng.nextBool(),
      ));
    }
    // Ring burst
    s.ptcls.add(_Ptcl(
      x: x, y: y, vx: 0, vy: 0,
      life: 0.26, size: 36, col: col.withOpacity(0.52),
    ));
  }

  void _addLabel(double x, double y, String text, Color col,
      {bool big = false}) {
    s.labels.add(_Label(x, y, text, col,
        fontSize: big ? 22 : 17,
        vy: big ? -100 : -78,
        life: big ? 1.0 : 0.82));
  }

  void _updateTimers(double dt) {
    if (s.invT > 0)        s.invT -= dt;
    if (s.flashT > 0)      s.flashT -= dt;
    if (s.shakeT > 0)      s.shakeT -= dt;
    if (s.flashScreen > 0) s.flashScreen -= dt * 3.0;
    if (s.comboTimer > 0)  { s.comboTimer -= dt; if (s.comboTimer <= 0) s.combo = 0; }
    if (s.shieldT > 0)     { s.shieldT -= dt; if (s.shieldT <= 0) s.shield = false; }
    if (s.rapidT > 0)      { s.rapidT  -= dt; if (s.rapidT  <= 0) s.rapid  = false; }
    if (s.tripleT > 0)     { s.tripleT -= dt; if (s.tripleT <= 0) s.triple = false; }
  }

  void useBomb() {
    if (s.bombs <= 0 || s.phase != Phase.playing) return;
    s.bombs--;
    for (final e in s.enemies) { _boom(e.x, e.y, e.col, 8); e.dead = true; }
    s.bullets.removeWhere((b) => b.enemy);
    s.shakeT = _kShakeDur * 1.9; s.flashScreen = 0.68;
    _addLabel(s.sw / 2, s.sh * 0.42, '💣  BOMB!', _kGold, big: true);
    GameAudio.playExplosion();
  }
}

// ══════════════════════════════════════════════════════════════ PAINTER

class _Painter extends CustomPainter {
  final _GS s;
  _Painter(this.s);

  // Static re-usable Paint objects (avoid per-frame allocations)
  static final _fill   = Paint()..style = PaintingStyle.fill;
  static final _stroke = Paint()..style = PaintingStyle.stroke;
  static final _g6  = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
  static final _g10 = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
  static final _g16 = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);

  @override
  bool shouldRepaint(_) => true;

  @override
  void paint(Canvas c, Size sz) {
    c.save();

    // Screen shake
    if (s.shakeT > 0) {
      final mag = _kShakeMag * (s.shakeT / _kShakeDur).clamp(0.0, 1.0);
      c.translate(sin(s.time * 67) * mag, cos(s.time * 83) * mag);
    }

    _bg(c, sz);
    _trail(c);
    _ptcls(c);
    _pus(c);
    _enemies(c);
    _bullets(c);

    final drawShip = s.phase == Phase.playing || s.phase == Phase.levelUp;
    if (drawShip && (s.invT <= 0 || (s.time * 9).toInt() % 2 == 0)) {
      _ship(c);
    }
    _floatingLabels(c);

    if (s.flashScreen > 0) {
      c.drawRect(Rect.fromLTWH(0, 0, sz.width, sz.height),
          Paint()..color = Colors.white
              .withOpacity(s.flashScreen.clamp(0.0, 0.55)));
    }
    c.restore();
  }

  // ── BACKGROUND ────────────────────────────────────────────────────────────

  void _bg(Canvas c, Size sz) {
    // Deep space gradient
    c.drawRect(
      Rect.fromLTWH(0, 0, sz.width, sz.height),
      Paint()..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [_kBg1, _kBg2],
      ).createShader(Rect.fromLTWH(0, 0, sz.width, sz.height)),
    );

    // Nebula blobs
    for (final n in s.nebulae) {
      c.drawCircle(Offset(n.x, n.y), n.r,
          Paint()..shader = RadialGradient(
            colors: [n.col.withOpacity(0.14), Colors.transparent],
          ).createShader(
              Rect.fromCircle(center: Offset(n.x, n.y), radius: n.r)));
    }

    // Parallax stars (3 layers)
    for (final st in s.stars) {
      _fill.color = Colors.white.withOpacity(st.alpha);
      c.drawCircle(Offset(st.x, st.y), st.size, _fill);
    }
  }

  // ── ENGINE TRAIL ──────────────────────────────────────────────────────────

  void _trail(Canvas c) {
    final n = s.trail.length;
    if (n < 2) return;
    for (var i = 0; i < n - 1; i++) {
      final t = 1.0 - i / n;
      c.drawLine(
        s.trail[i], s.trail[i + 1],
        Paint()
          ..color = _kAccent.withOpacity(t * 0.27)
          ..strokeWidth = t * 3.6 + 0.4
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  // ── PARTICLES ─────────────────────────────────────────────────────────────

  void _ptcls(Canvas c) {
    for (final p in s.ptcls) {
      if (p.dead) continue;
      final a = p.life.clamp(0.0, 1.0);
      _fill.color = p.col.withOpacity(a);
      if (p.spark) {
        c.drawLine(
          Offset(p.x, p.y),
          Offset(p.x - p.vx * 0.024, p.y - p.vy * 0.024),
          Paint()
            ..color = _fill.color
            ..strokeWidth = 1.7
            ..strokeCap = StrokeCap.round,
        );
      } else {
        c.drawCircle(Offset(p.x, p.y), p.size.clamp(0.5, 9.5), _fill);
      }
    }
  }

  // ── FLOATING SCORE LABELS ─────────────────────────────────────────────────

  void _floatingLabels(Canvas c) {
    for (final lbl in s.labels) {
      if (lbl.dead) continue;
      final alpha = lbl.life.clamp(0.0, 1.0);
      final tp = TextPainter(
        text: TextSpan(
          text: lbl.text,
          style: TextStyle(
            color: lbl.col.withOpacity(alpha),
            fontSize: lbl.fontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            shadows: [
              Shadow(
                color: Colors.black.withOpacity(alpha * 0.8),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, Offset(lbl.x - tp.width / 2, lbl.y - tp.height / 2));
    }
  }

  // ── POWER-UPS ─────────────────────────────────────────────────────────────

  void _pus(Canvas c) {
    for (final pu in s.pus) {
      if (pu.dead) continue;
      final col   = _puColor(pu.type);
      final pulse = sin(pu.pulse) * 0.14 + 1.0;

      // Outer glow
      _g10.color = col.withOpacity(0.3);
      c.drawCircle(Offset(pu.x, pu.y), 22 * pulse, _g10);

      c.save();
      c.translate(pu.x, pu.y);
      c.rotate(pu.rot);

      // Body
      _fill.color = col.withOpacity(0.9);
      c.drawCircle(Offset.zero, 15 * pulse, _fill);
      _stroke
        ..color = Colors.white.withOpacity(0.30)
        ..strokeWidth = 1.6;
      c.drawCircle(Offset.zero, 15 * pulse, _stroke);

      // Inner highlight
      _fill.color = Colors.white.withOpacity(0.22);
      c.drawCircle(const Offset(-3, -3), 5 * pulse, _fill);

      // Icon
      final tp = TextPainter(
        text: TextSpan(
          text: _puGlyph(pu.type),
          style: TextStyle(fontSize: 13 * pulse, color: Colors.white),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));

      c.restore();
    }
  }

  Color  _puColor(PUType t) => switch (t) {
    PUType.shield => _kCyan,
    PUType.rapid  => _kRed,
    PUType.triple => _kGold,
    PUType.life   => _kGreen,
    PUType.bomb   => const Color(0xFFFF9F43),
  };

  String _puGlyph(PUType t) => switch (t) {
    PUType.shield => '🛡',
    PUType.rapid  => '⚡',
    PUType.triple => '✦',
    PUType.life   => '♥',
    PUType.bomb   => '💣',
  };

  // ── ENEMIES ───────────────────────────────────────────────────────────────

  void _enemies(Canvas c) {
    for (final e in s.enemies) {
      if (e.dead) continue;
      c.save();
      c.translate(e.x, e.y);
      c.rotate(e.rot);

      final col = e.flash > 0
          ? Color.lerp(e.col, Colors.white, e.flash.clamp(0.0, 1.0))!
          : e.col;

      // Engine glow
      _g16.color = col.withOpacity(0.22);
      c.drawCircle(Offset(0, e.cr * 0.28), e.cr * 0.55, _g16);

      final path = _enemyPath(e);

      // Radial gradient fill — gives 3-D sphere-like appearance
      c.drawPath(path,
          Paint()..shader = RadialGradient(
            center: const Alignment(-0.30, -0.40),
            colors: [
              Color.lerp(col, Colors.white, 0.28)!,
              col,
              Color.lerp(col, Colors.black, 0.32)!,
            ],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(
              Rect.fromCircle(center: Offset.zero, radius: e.cr)));

      // Rim highlight
      _stroke
        ..color = Colors.white.withOpacity(0.26)
        ..strokeWidth = 1.5;
      c.drawPath(path, _stroke);

      // Central cockpit / energy core
      _fill.color = Colors.white.withOpacity(0.55);
      c.drawCircle(Offset.zero, e.cr * 0.22, _fill);
      _fill.color = col.withOpacity(0.9);
      c.drawCircle(Offset.zero, e.cr * 0.12, _fill);

      // HP bar — destroyers
      if (e.type == EnemyType.destroyer && e.maxHp > 1) {
        final bW = e.cr * 2.4, bH = 5.0, bY = e.cr + 7.0;
        final pct = (e.hp / e.maxHp).clamp(0.0, 1.0);
        // Background track
        c.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: Offset(0, bY), width: bW, height: bH),
                const Radius.circular(3)),
            Paint()..color = Colors.black.withOpacity(0.65));
        // Fill
        if (pct > 0) {
          c.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTWH(-bW / 2, bY - bH / 2, bW * pct, bH),
                  const Radius.circular(3)),
              Paint()..color = pct > 0.5 ? col : _kRed);
        }
      }

      c.restore();
    }
  }

  Path _enemyPath(_Enemy e) {
    final r = e.cr;
    final p = Path();
    switch (e.type) {
      case EnemyType.drone: // hexagon
        for (var i = 0; i < 6; i++) {
          final a = i * pi / 3 - pi / 6;
          if (i == 0) p.moveTo(cos(a) * r, sin(a) * r);
          else        p.lineTo(cos(a) * r, sin(a) * r);
        }
        p.close();
      case EnemyType.fighter: // narrow diamond — fast interceptor
        p.moveTo(0, -r);
        p.lineTo(r * 0.52, 0);
        p.lineTo(0, r);
        p.lineTo(-r * 0.52, 0);
        p.close();
      case EnemyType.destroyer: // heavy octagon
        for (var i = 0; i < 8; i++) {
          final a = i * pi / 4 - pi / 8;
          if (i == 0) p.moveTo(cos(a) * r, sin(a) * r);
          else        p.lineTo(cos(a) * r, sin(a) * r);
        }
        p.close();
    }
    return p;
  }

  // ── BULLETS ───────────────────────────────────────────────────────────────

  void _bullets(Canvas c) {
    for (final b in s.bullets) {
      if (b.dead) continue;
      final col = b.enemy ? _kOrange : _kAccent;
      final bW  = b.enemy ? 7.0 : 4.2;
      final bH  = b.enemy ? 6.0 : 15.0;

      // Glow halo
      _g6.color = col.withOpacity(0.35);
      c.drawOval(
          Rect.fromCenter(
              center: Offset(b.x, b.y), width: bW * 2.6, height: bH * 1.6),
          _g6);

      // Core capsule
      c.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(b.x, b.y), width: bW, height: bH),
              const Radius.circular(4)),
          Paint()
            ..color =
                b.enemy ? const Color(0xFFFFB090) : Colors.white);

      // Bright tip
      _fill.color = Colors.white.withOpacity(0.85);
      c.drawCircle(
          Offset(b.x, b.y - (b.enemy ? 0 : bH * 0.38)), bW * 0.3, _fill);
    }
  }

  // ── PLAYER SHIP ───────────────────────────────────────────────────────────

  void _ship(Canvas c) {
    final sx = s.shipX, sy = s.shipY;
    final fH  = 11.0 + s.engineFlicker * 13;

    // Ambient engine halo
    _g16.color = _kAccent.withOpacity(0.14);
    c.drawCircle(Offset(sx, sy + 18), 30, _g16);

    // Three engine flames
    void flame(double ox, double h, double op) {
      c.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(sx + ox, sy + 20 + h * 0.3),
                  width: ox == 0 ? 9 : 5, height: h),
              const Radius.circular(5)),
          Paint()..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_kAccent.withOpacity(op), _kAccent.withOpacity(0)],
          ).createShader(Rect.fromCenter(
              center: Offset(sx + ox, sy + 20),
              width: 10, height: h + 5)));
    }
    flame(0,   fH,        0.93);
    flame(-9.5, fH * 0.62, 0.62);
    flame( 9.5, fH * 0.62, 0.62);

    // Ship body path
    final body = Path()
      ..moveTo(sx,      sy - 24) // nose tip
      ..lineTo(sx + 19, sy + 17) // right wing tip
      ..lineTo(sx + 9,  sy + 8)  // right wing indent
      ..lineTo(sx,      sy + 14) // center rear
      ..lineTo(sx - 9,  sy + 8)  // left wing indent
      ..lineTo(sx - 19, sy + 17) // left wing tip
      ..close();

    // Body gradient
    c.drawPath(body,
        Paint()..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, const Color(0xFF9DC8FF), const Color(0xFF5A8FD4)],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(
            Rect.fromCenter(center: Offset(sx, sy), width: 42, height: 50)));

    // Body rim
    _stroke
      ..color = _kAccent.withOpacity(0.52)
      ..strokeWidth = 1.3;
    c.drawPath(body, _stroke);

    // Wing accent stripes
    _fill.color = _kAccent.withOpacity(0.32);
    c.drawPath(Path()
      ..moveTo(sx + 10, sy + 10)
      ..lineTo(sx + 19, sy + 17)
      ..lineTo(sx + 13, sy + 17)
      ..close(), _fill);
    c.drawPath(Path()
      ..moveTo(sx - 10, sy + 10)
      ..lineTo(sx - 19, sy + 17)
      ..lineTo(sx - 13, sy + 17)
      ..close(), _fill);

    // Cockpit glass
    c.drawOval(
        Rect.fromCenter(center: Offset(sx, sy - 5), width: 10, height: 13),
        Paint()..color = _kAccent.withOpacity(0.88));
    // Cockpit glare
    c.drawOval(
        Rect.fromCenter(
            center: Offset(sx - 1.5, sy - 6.5), width: 3.5, height: 4.5),
        Paint()..color = Colors.white.withOpacity(0.52));

    // Shield bubble
    if (s.shield) {
      final a = 0.20 + sin(s.time * 5.5) * 0.09;
      c.drawCircle(Offset(sx, sy), 34,
          Paint()
            ..color = _kCyan.withOpacity(a)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      c.drawCircle(
          Offset(sx, sy), 34,
          Paint()
            ..color = _kCyan.withOpacity(0.58)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2);
    }

    // Hit flash red overlay
    if (s.flashT > 0) {
      c.drawPath(body,
          Paint()..color = _kRed.withOpacity(
              (sin(s.time * 28) * 0.4 + 0.5) * s.flashT.clamp(0.0, 1.0)));
    }
  }
}

// ══════════════════════════════════════════════════════════════ MAIN WIDGET

class NovaBlasterGame extends StatefulWidget {
  final VoidCallback? onExit;
  const NovaBlasterGame({super.key, this.onExit});
  @override
  State<NovaBlasterGame> createState() => _NBState();
}

class _NBState extends State<NovaBlasterGame>
    with SingleTickerProviderStateMixin {
  late final _GS    _gs;
  late final _Logic _logic;
  late final Ticker _ticker;
  Duration? _last;
  final _frame = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _gs     = _GS();
    _logic  = _Logic(_gs);
    _ticker = createTicker(_tick)..start();
    SharedPreferences.getInstance()
        .then((p) => _gs.hi = p.getInt('nova_hi') ?? 0);
    GameAudio.initialize()
        .then((_) => GameAudio.startBackgroundMusic());
  }


  /// Safe exit — avoids void-null-check compile error
  void _exit() {
    if (widget.onExit != null) {
      widget.onExit!();
    } else {
      Navigator.pop(context);
    }
  }

  void _tick(Duration elapsed) {
    final dt = _last == null
        ? 0.016
        : ((elapsed - _last!).inMicroseconds / 1e6).clamp(0.0, 0.050);
    _last = elapsed;
    if (_gs.sw > 0) _logic.update(dt);
    _frame.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    GameAudio.stopBackgroundMusic();
    super.dispose();
  }

  // ── INPUT ────────────────────────────────────────────────────────────────

  void _onDrag(Offset p) {
    if (_gs.phase == Phase.playing || _gs.phase == Phase.levelUp) {
      _gs.targetX = p.dx.clamp(_kShipR, _gs.sw - _kShipR);
      _gs.targetY = p.dy.clamp(_kShipR, _gs.sh - _kShipR);
    }
  }

  void _onTap(Offset p) {
    switch (_gs.phase) {
      case Phase.title:
        _gs.reset();
      case Phase.playing:
        _logic.useBomb();
      case Phase.gameOver:
        _gs.reset();
        GameAudio.startBackgroundMusic();
      case Phase.paused:
        _gs.phase = Phase.playing;
        GameAudio.resumeBackgroundMusic();
      case Phase.levelUp:
        break;
    }
  }

  // ── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg1,
      body: LayoutBuilder(builder: (_, box) {
        final w = box.maxWidth, h = box.maxHeight;
        if (_gs.sw == 0) _gs.initWorld(w, h);
        return GestureDetector(
          onPanStart:  (d) => _onDrag(d.localPosition),
          onPanUpdate: (d) => _onDrag(d.localPosition),
          onTapDown:   (d) => _onTap(d.localPosition),
          child: Stack(children: [
            // ── Game canvas ──────────────────────────────────────
            ValueListenableBuilder<int>(
              valueListenable: _frame,
              builder: (_, __, ___) => CustomPaint(
                painter: _Painter(_gs),
                size: Size(w, h),
              ),
            ),
            // ── HUD overlay ──────────────────────────────────────
            ValueListenableBuilder<int>(
              valueListenable: _frame,
              builder: (_, __, ___) => _hud(box),
            ),
          ]),
        );
      }),
    );
  }

  // ══════════════════════════════════════════════════════════════ HUD LAYERS

  Widget _hud(BoxConstraints box) => switch (_gs.phase) {
    Phase.title   => _hudTitle(),
    Phase.playing => _hudPlaying(box),
    Phase.levelUp => _hudLevelUp(box),
    Phase.gameOver => _hudGameOver(),
    Phase.paused  => _hudPaused(),
  };

  // ── TITLE SCREEN ──────────────────────────────────────────────────────────

  Widget _hudTitle() {
    final blink = (sin(_gs.titleAnim * 2.5) * 0.38 + 0.62).clamp(0.22, 1.0);
    return SizedBox.expand(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          // Gradient logo
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [Color(0xFF4DA3FF), Color(0xFF00E5FF), Color(0xFF4DA3FF)],
            ).createShader(b),
            child: const Text(
              'NOVA\nBLASTER',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 62, fontWeight: FontWeight.w900,
                letterSpacing: 7, color: Colors.white, height: 1.05,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text('OFFLINE ARCADE',
              style: TextStyle(color: _kAccent, fontSize: 12,
                  letterSpacing: 5.5, fontWeight: FontWeight.w300)),
          const SizedBox(height: 50),
          // Blinking launch prompt
          Opacity(
            opacity: blink,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 13),
              decoration: BoxDecoration(
                  border: Border.all(color: _kAccent, width: 1.5),
                  borderRadius: BorderRadius.circular(32),
                  color: _kAccent.withOpacity(0.09)),
              child: const Text('▶   TAP TO LAUNCH',
                  style: TextStyle(color: _kAccent, fontSize: 15,
                      letterSpacing: 3.5, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 34),
          // Controls card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 38),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.08))),
            child: const Column(children: [
              _Hint('DRAG',  'Move your ship anywhere'),
              SizedBox(height: 7),
              _Hint('AUTO',  'Guns fire continuously'),
              SizedBox(height: 7),
              _Hint('TAP',   'Detonate bomb power-up'),
              SizedBox(height: 7),
              _Hint('COMBO', 'Kill streak × score multiplier'),
            ]),
          ),
          if (_gs.hi > 0) ...[
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.emoji_events_rounded, color: _kGold, size: 18),
              const SizedBox(width: 6),
              Text(
                'BEST  ${_gs.hi.toString().padLeft(7, "0")}',
                style: const TextStyle(color: _kGold, fontSize: 16,
                    letterSpacing: 3, fontWeight: FontWeight.w700),
              ),
            ]),
          ],
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: () =>
                _exit(),
            icon: const Icon(Icons.arrow_back_ios_rounded,
                color: _kAccent, size: 14),
            label: const Text('Back to ChatXAP',
                style: TextStyle(color: _kAccent, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ── PLAYING HUD ───────────────────────────────────────────────────────────

  Widget _hudPlaying(BoxConstraints box) {
    return Stack(children: [
      // Top gradient panel
      Positioned(
        top: 0, left: 0, right: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 42, 16, 14),
          decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withOpacity(0.78), Colors.transparent],
              )),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Score + best
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  _gs.score.toString().padLeft(7, '0'),
                  style: const TextStyle(
                    color: Colors.white, fontSize: 26,
                    fontWeight: FontWeight.w800, letterSpacing: 2.8,
                    fontFamily: 'monospace',
                  ),
                ),
                if (_gs.hi > 0)
                  Text('BEST  ${_gs.hi.toString().padLeft(7, "0")}',
                      style: const TextStyle(
                          color: Color(0xFF4B5563), fontSize: 10,
                          letterSpacing: 1.5)),
              ]),
              const Spacer(),
              // Lives (up to 5 hearts)
              Row(children: List.generate(5, (i) => Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Icon(
                  i < _gs.lives
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: i < _gs.lives ? _kRed : const Color(0xFF374151),
                  size: 18,
                ),
              ))),
              const SizedBox(width: 10),
              // Level badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                    color: _kAccent.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kAccent.withOpacity(0.42))),
                child: Text('LV  ${_gs.level}',
                    style: const TextStyle(
                        color: _kAccent, fontSize: 12,
                        fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              ),
              const SizedBox(width: 8),
              // Mute toggle
              GestureDetector(
                onTap: () { GameAudio.toggleMute(); _frame.value++; },
                child: Icon(
                  GameAudio.isMuted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  color: Colors.white54, size: 22,
                ),
              ),
            ],
          ),
        ),
      ),

      // Combo strip
      if (_gs.combo >= 3)
        Positioned(
          top: 106, left: 0, right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.60),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _kGold.withOpacity(0.65))),
              child: Text(
                '×${_gs.combo >= 10 ? 5 : _gs.combo >= 6 ? 3 : 2}  '
                'COMBO  ×${_gs.combo}',
                style: const TextStyle(
                    color: _kGold, fontSize: 12,
                    fontWeight: FontWeight.w700, letterSpacing: 2.5),
              ),
            ),
          ),
        ),

      // Power-up chips (bottom)
      Positioned(
        bottom: 18, left: 12, right: 12,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_gs.shield) _puChip('🛡', 'SHIELD', _gs.shieldT / _kShieldDur, _kCyan),
            if (_gs.triple) _puChip('✦', 'TRIPLE', _gs.tripleT / _kPowerDur,   _kGold),
            if (_gs.rapid)  _puChip('⚡', 'RAPID',  _gs.rapidT  / _kPowerDur,   _kRed),
            if (_gs.bombs > 0) _bombChip(),
          ],
        ),
      ),

      // Pause button (top-left)
      Positioned(
        top: 40, left: 10,
        child: GestureDetector(
          onTap: () {
            _gs.phase = Phase.paused;
            GameAudio.pauseBackgroundMusic();
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.pause_rounded,
                color: Colors.white60, size: 20),
          ),
        ),
      ),
    ]);
  }

  Widget _puChip(String icon, String lbl, double t, Color col) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 4),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
        color: col.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: col.withOpacity(0.42))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(icon, style: const TextStyle(fontSize: 12)),
      const SizedBox(width: 4),
      Text(lbl, style: TextStyle(color: col, fontSize: 11,
          fontWeight: FontWeight.w700, letterSpacing: 1)),
      const SizedBox(width: 6),
      SizedBox(
        width: 28, height: 4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
              value: t.clamp(0.0, 1.0),
              backgroundColor: col.withOpacity(0.18),
              valueColor: AlwaysStoppedAnimation<Color>(col)),
        ),
      ),
    ]),
  );

  Widget _bombChip() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 4),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
        color: const Color(0xFFFF9F43).withOpacity(0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFF9F43).withOpacity(0.5))),
    child: Text('💣  ×${_gs.bombs}  TAP',
        style: const TextStyle(color: Color(0xFFFF9F43),
            fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1)),
  );

  // ── LEVEL UP ──────────────────────────────────────────────────────────────

  Widget _hudLevelUp(BoxConstraints box) {
    final t = (_gs.lvlT / _kLvlDur).clamp(0.0, 1.0);
    return Stack(children: [
      _hudPlaying(box),
      IgnorePointer(
        child: Center(
          child: Opacity(
            opacity: sin(t * pi).clamp(0.0, 1.0),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ShaderMask(
                shaderCallback: (b) => const LinearGradient(
                  colors: [_kAccent, _kCyan],
                ).createShader(b),
                child: Text('LEVEL  ${_gs.level}',
                    style: const TextStyle(fontSize: 58,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 5, color: Colors.white)),
              ),
              const SizedBox(height: 8),
              Text(
                _gs.level % 5 == 0
                    ? '⚠   WAVE INTENSIFIES!'
                    : 'ENEMIES FASTER!',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.76),
                    fontSize: 13, letterSpacing: 2.5),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }

  // ── GAME OVER ─────────────────────────────────────────────────────────────

  Widget _hudGameOver() {
    final newHS = _gs.score > 0 && _gs.score >= _gs.hi;
    return SizedBox.expand(
      child: Container(
        color: Colors.black.withOpacity(0.83),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          // Headline
          const Text('GAME  OVER',
              style: TextStyle(color: _kRed, fontSize: 46,
                  fontWeight: FontWeight.w900, letterSpacing: 6)),
          const SizedBox(height: 32),

          // Score card (glass morphism)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 36),
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 22),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withOpacity(0.09))),
            child: Column(children: [
              Text(
                _gs.score.toString().padLeft(7, '0'),
                style: const TextStyle(
                    color: Colors.white, fontSize: 46,
                    fontWeight: FontWeight.w900, letterSpacing: 4,
                    fontFamily: 'monospace'),
              ),
              const SizedBox(height: 2),
              const Text('SCORE',
                  style: TextStyle(color: Color(0xFF6B7280),
                      fontSize: 11, letterSpacing: 4)),
              if (newHS) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                      color: _kGold.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _kGold.withOpacity(0.5))),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.emoji_events_rounded, color: _kGold, size: 15),
                    SizedBox(width: 6),
                    Text('NEW HIGH SCORE!',
                        style: TextStyle(color: _kGold, fontSize: 13,
                            fontWeight: FontWeight.w800, letterSpacing: 2)),
                  ]),
                ),
              ],
              const SizedBox(height: 20),
              _sRow('LEVEL  REACHED', '${_gs.level}'),
              const SizedBox(height: 5),
              _sRow('HIGH  SCORE', _gs.hi.toString().padLeft(7, '0')),
            ]),
          ),
          const SizedBox(height: 32),

          // Play Again button
          GestureDetector(
            onTap: () {
              _gs.reset();
              GameAudio.startBackgroundMusic();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 52, vertical: 15),
              decoration: BoxDecoration(
                  color: _kAccent,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [BoxShadow(
                    color: _kAccent.withOpacity(0.50),
                    blurRadius: 26, spreadRadius: 2,
                  )]),
              child: const Text('PLAY  AGAIN',
                  style: TextStyle(color: Colors.white, fontSize: 16,
                      fontWeight: FontWeight.w900, letterSpacing: 3.5)),
            ),
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: () =>
                _exit(),
            icon: const Icon(Icons.arrow_back_ios_rounded,
                color: _kAccent, size: 14),
            label: const Text('Back to ChatXAP',
                style: TextStyle(color: _kAccent, fontSize: 13)),
          ),
        ]),
      ),
    );
  }

  Widget _sRow(String lbl, String val) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(lbl, style: const TextStyle(color: Color(0xFF9CA3AF),
            fontSize: 12, letterSpacing: 1)),
        const SizedBox(width: 28),
        Text(val, style: const TextStyle(color: Colors.white, fontSize: 12,
            fontWeight: FontWeight.w800, fontFamily: 'monospace')),
      ],
    ),
  );

  // ── PAUSED ────────────────────────────────────────────────────────────────

  Widget _hudPaused() => SizedBox.expand(
    child: Container(
      color: Colors.black.withOpacity(0.80),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.pause_circle_filled_rounded,
            color: _kAccent, size: 78),
        const SizedBox(height: 20),
        const Text('PAUSED',
            style: TextStyle(color: Colors.white, fontSize: 42,
                fontWeight: FontWeight.w900, letterSpacing: 5)),
        const SizedBox(height: 12),
        Text('Tap anywhere to resume',
            style: TextStyle(color: Colors.white.withOpacity(0.55),
                fontSize: 14, letterSpacing: 1.5)),
        const SizedBox(height: 38),
        TextButton.icon(
          onPressed: () =>
              _exit(),
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: _kAccent, size: 14),
          label: const Text('Back to ChatXAP',
              style: TextStyle(color: _kAccent, fontSize: 13)),
        ),
      ]),
    ),
  );
}

// ══════════════════════════════════════════════════════════════ HELPER

class _Hint extends StatelessWidget {
  final String label, hint;
  const _Hint(this.label, this.hint);
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: _kAccent.withOpacity(0.18),
          borderRadius: BorderRadius.circular(4)),
      child: Text(label,
          style: const TextStyle(color: _kAccent, fontSize: 10,
              fontWeight: FontWeight.w800, letterSpacing: 1)),
    ),
    const SizedBox(width: 12),
    Expanded(child: Text(hint,
        style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 11))),
  ]);
}
