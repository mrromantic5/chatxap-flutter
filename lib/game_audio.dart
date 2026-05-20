import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

class GameAudio {
  static final AudioPlayer _player = AudioPlayer();
  static final AudioPlayer _musicPlayer = AudioPlayer();
  static final AudioPlayer _sfxPlayer = AudioPlayer();
  
  static bool _isInitialized = false;
  static bool _isMuted = false;
  
  static Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    
    await _player.setReleaseMode(ReleaseMode.release);
    await _musicPlayer.setReleaseMode(ReleaseMode.loop);
    await _sfxPlayer.setReleaseMode(ReleaseMode.release);
    
    // AudioPlayers 6.0+ - set loop by setting release mode to loop
  }
  
  static Future<void> playShoot() async {
    if (_isMuted) return;
    try {
      await _player.play(AssetSource('sounds/shoot.wav'));
    } catch (_) {}
  }
  
  static Future<void> playExplosion() async {
    if (_isMuted) return;
    try {
      await _sfxPlayer.play(AssetSource('sounds/explosion.wav'));
    } catch (_) {}
  }
  
  static Future<void> playPowerup() async {
    if (_isMuted) return;
    try {
      await _sfxPlayer.play(AssetSource('sounds/powerup.wav'));
    } catch (_) {}
  }
  
  static Future<void> playHit() async {
    if (_isMuted) return;
    try {
      await _sfxPlayer.play(AssetSource('sounds/hit.wav'));
    } catch (_) {}
  }
  
  static Future<void> playGameOver() async {
    if (_isMuted) return;
    try {
      await _sfxPlayer.play(AssetSource('sounds/gameover.wav'));
    } catch (_) {}
  }
  
  static Future<void> playLevelUp() async {
    if (_isMuted) return;
    try {
      await _sfxPlayer.play(AssetSource('sounds/levelup.wav'));
    } catch (_) {}
  }
  
  static Future<void> startBackgroundMusic() async {
    if (_isMuted) return;
    try {
      await _musicPlayer.setReleaseMode(ReleaseMode.loop);
      await _musicPlayer.play(AssetSource('sounds/background.mp3'));
    } catch (_) {}
  }
  
  static Future<void> stopBackgroundMusic() async {
    try {
      await _musicPlayer.stop();
    } catch (_) {}
  }
  
  static void toggleMute() {
    _isMuted = !_isMuted;
    if (_isMuted) {
      _musicPlayer.stop();
    } else {
      startBackgroundMusic();
    }
  }
}
