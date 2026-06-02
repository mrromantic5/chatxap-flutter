import 'package:audioplayers/audioplayers.dart';

/// Premium audio manager for Nova Blaster.
///
/// Design goals (fixes the previous "sounds cut each other / glitch" issues):
///   • DEDICATED CHANNELS per sound category. A shot can never interrupt an
///     explosion, a level-up can never interrupt a power-up, etc. Each category
///     owns its own AudioPlayer(s), so they mix instead of stealing one pool.
///   • SMALL POOLS for sounds that legitimately overlap (explosions, hits) so
///     several can ring out at once without clipping.
///   • NO stop()->play() race. We call play() directly; audioplayers v6 resets
///     the player cleanly, which removes the ordering glitch from the old code.
///   • SHOOT THROTTLE so rapid auto-fire can't spam dozens of overlapping clips.
///   • IDEMPOTENT MUSIC so repeated start calls (menu/continue/new-game) never
///     stack a second background track on top of the first.
class GameAudio {
  GameAudio._();

  // ── Category channels ────────────────────────────────────────────────
  static final List<AudioPlayer> _shoot = [];   // pool 2  (machine-gun fire)
  static final List<AudioPlayer> _hit   = [];   // pool 2  (bullet→armor pings)
  static final List<AudioPlayer> _boom  = [];   // pool 3  (explosions overlap)
  static final AudioPlayer _power = AudioPlayer(playerId: 'cx_power');
  static final AudioPlayer _level = AudioPlayer(playerId: 'cx_level');
  static final AudioPlayer _over  = AudioPlayer(playerId: 'cx_over');
  static final AudioPlayer _music = AudioPlayer(playerId: 'cx_music');

  static int _iShoot = 0, _iHit = 0, _iBoom = 0;
  static bool _initialized = false, _muted = false, _musicOn = false;
  static int _lastShootMs = 0;

  static bool get isMuted => _muted;

  static Future<void> _buildPool(
      List<AudioPlayer> pool, int n, String id, double vol) async {
    for (var i = 0; i < n; i++) {
      final p = AudioPlayer(playerId: '$id$i');
      await p.setReleaseMode(ReleaseMode.stop); // keep source ready, low latency
      await p.setVolume(vol);
      pool.add(p);
    }
  }

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _buildPool(_shoot, 2, 'cx_shoot', 0.42); // quieter so it never drowns SFX
    await _buildPool(_hit,   2, 'cx_hit',   0.55);
    await _buildPool(_boom,  3, 'cx_boom',  0.80);
    await _power.setReleaseMode(ReleaseMode.stop); await _power.setVolume(0.85);
    await _level.setReleaseMode(ReleaseMode.stop); await _level.setVolume(0.90);
    await _over.setReleaseMode(ReleaseMode.stop);  await _over.setVolume(0.95);
    await _music.setReleaseMode(ReleaseMode.loop); await _music.setVolume(0.26);
  }

  // Cycle through a category's pool so consecutive plays use different players
  // (consecutive sounds overlap cleanly instead of cutting each other).
  static void _cyclePlay(List<AudioPlayer> pool, int idx, void Function(int) setIdx, String asset) {
    if (_muted || pool.isEmpty) return;
    final i = idx % pool.length;
    setIdx(i + 1);
    pool[i].play(AssetSource(asset)).catchError((_) {});
  }

  static void playShoot() {
    if (_muted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastShootMs < 45) return; // throttle: max ~22 shots/sec of audio
    _lastShootMs = now;
    _cyclePlay(_shoot, _iShoot, (v) => _iShoot = v, 'sounds/shoot.wav');
  }

  static void playHit()       => _cyclePlay(_hit,  _iHit,  (v) => _iHit  = v, 'sounds/hit.wav');
  static void playExplosion() => _cyclePlay(_boom, _iBoom, (v) => _iBoom = v, 'sounds/explosion.wav');

  static void playPowerup() {
    if (_muted) return;
    _power.play(AssetSource('sounds/powerup.wav')).catchError((_) {});
  }

  static void playLevelUp() {
    if (_muted) return;
    _level.play(AssetSource('sounds/levelup.wav')).catchError((_) {});
  }

  static void playGameOver() {
    if (_muted) return;
    _over.play(AssetSource('sounds/gameover.wav')).catchError((_) {});
  }

  // ── Background music (looping, single instance) ──────────────────────
  static Future<void> startBackgroundMusic() async {
    if (_muted || _musicOn) return; // idempotent — never stack tracks
    _musicOn = true;
    try {
      await _music.setReleaseMode(ReleaseMode.loop);
      await _music.play(AssetSource('sounds/background.mp3'));
    } catch (_) {
      _musicOn = false;
    }
  }

  static Future<void> stopBackgroundMusic() async {
    _musicOn = false;
    try { await _music.stop(); } catch (_) {}
  }

  static Future<void> pauseBackgroundMusic() async {
    try { await _music.pause(); } catch (_) {}
  }

  static Future<void> resumeBackgroundMusic() async {
    if (_muted) return;
    try { await _music.resume(); } catch (_) {}
  }

  static void toggleMute() {
    _muted = !_muted;
    if (_muted) {
      stopBackgroundMusic();
    } else {
      startBackgroundMusic();
    }
  }

  static void dispose() {
    final all = <AudioPlayer>[..._shoot, ..._hit, ..._boom, _power, _level, _over, _music];
    for (final p in all) { p.stop(); p.dispose(); }
    _shoot.clear(); _hit.clear(); _boom.clear();
    _initialized = false; _musicOn = false;
  }
}
