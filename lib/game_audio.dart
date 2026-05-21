import 'package:audioplayers/audioplayers.dart';

/// Premium audio manager with SFX pool, looping music, and mute support.
class GameAudio {
  GameAudio._();

  // SFX pool — round-robin to allow overlapping short sounds
  static const int _kPoolSize = 8;
  static final List<AudioPlayer> _sfx =
      List.generate(_kPoolSize, (_) => AudioPlayer());
  static int _sfxIdx = 0;

  // Dedicated looping music player
  static final AudioPlayer _music = AudioPlayer();

  static bool _initialized = false;
  static bool _muted       = false;

  static bool get isMuted => _muted;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    for (final p in _sfx) {
      await p.setReleaseMode(ReleaseMode.release);
      await p.setVolume(0.75);
    }
    await _music.setReleaseMode(ReleaseMode.loop);
    await _music.setVolume(0.30);
  }

  // ── SFX ──────────────────────────────────────────────────────────────────

  static void playShoot()     => _playSfx('sounds/shoot.wav');
  static void playExplosion() => _playSfx('sounds/explosion.wav');
  static void playPowerup()   => _playSfx('sounds/powerup.wav');
  static void playHit()       => _playSfx('sounds/hit.wav');
  static void playGameOver()  => _playSfx('sounds/gameover.wav');
  static void playLevelUp()   => _playSfx('sounds/levelup.wav');

  static void _playSfx(String asset) {
    if (_muted) return;
    final p = _sfx[_sfxIdx % _kPoolSize];
    _sfxIdx++;
    p.stop().then((_) => p.play(AssetSource(asset))).catchError((_) {});
  }

  // ── MUSIC ─────────────────────────────────────────────────────────────────

  static Future<void> startBackgroundMusic() async {
    if (_muted) return;
    try {
      await _music.setReleaseMode(ReleaseMode.loop);
      await _music.play(AssetSource('sounds/background.mp3'));
    } catch (_) {}
  }

  static Future<void> stopBackgroundMusic() async {
    try { await _music.stop(); } catch (_) {}
  }

  static Future<void> pauseBackgroundMusic() async {
    try { await _music.pause(); } catch (_) {}
  }

  static Future<void> resumeBackgroundMusic() async {
    if (_muted) return;
    try { await _music.resume(); } catch (_) {}
  }

  // ── MUTE ──────────────────────────────────────────────────────────────────

  static void toggleMute() {
    _muted = !_muted;
    if (_muted) {
      stopBackgroundMusic();
    } else {
      startBackgroundMusic();
    }
  }

  static void dispose() {
    for (final p in _sfx) { p.stop(); p.dispose(); }
    _music.stop(); _music.dispose();
  }
}
