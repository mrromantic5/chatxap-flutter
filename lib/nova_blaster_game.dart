// ═══════════════════════════════════════════════════════════════════════════
// NOVA BLASTER — SaaS Grade Edition
// Features: Seamless level transitions · Reload Store (Life/Bomb/Gun/Speed/Shield)
//           1–6 Gun spread · Speed boost · Formation waves · Boss battles
//           Achievement overlays · Danger warning · Combo multiplier
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'game_audio.dart';

// ═══════════════════════════════════════════════════════ ENUMS
enum AlienKind { drone, fighter, destroyer, boss }
enum PUKind    { shield, rapid, life, bomb }
enum GamePhase { title, playing, gameOver, paused }
enum WaveShape { vForm, grid, heart, diamond, swarm, bossWave }

// ═══════════════════════════════════════════════════════ PALETTE
const _cBg1    = Color(0xFF020509);
const _cBg2    = Color(0xFF0B1020);
const _cAccent = Color(0xFF4DA3FF);
const _cCyan   = Color(0xFF00E5FF);
const _cGold   = Color(0xFFFFD700);
const _cRed    = Color(0xFFFF4D6D);
const _cOrange = Color(0xFFFF8C00);
const _cPurple = Color(0xFFA855F7);
const _cGreen  = Color(0xFF8BC34A);

// ═══════════════════════════════════════════════════════ CONSTANTS
const _kShipR        = 22.0;
const _kBaseFireDt   = 0.28;
const _kRapidFireDt  = 0.10;
const _kInvDur       = 2.2;
const _kShieldDur    = 30.0;   // reload = 30s
const _kSpeedDur     = 30.0;   // reload = 30s
const _kGunDur       = 30.0;   // gun upgrade = 30s
const _kComboTO      = 3.2;
const _kShakeDur     = 0.40;
const _kShakeMag     = 9.0;
const _kReloadCost   = 5;      // score per reload
const _kLifeAmt      = 5;      // lives per life reload

// Gun spread angles for levels 1-6
const _kGunSpreads = <List<double>>[
  [0.0],
  [-20.0, 0.0, 20.0],
  [-28.0, -9.5, 9.5, 28.0],
  [-33.0, -16.5, 0.0, 16.5, 33.0],
  [-36.0, -21.6, -7.2, 7.2, 21.6, 36.0],
];

// ══════════════════════════════════════════════════════════════════════
//  ██████  ART ENGINE  ██████
// ══════════════════════════════════════════════════════════════════════
class _Art {
  _Art._();
  static final _f  = Paint()..style = PaintingStyle.fill;
  static final _s  = Paint()..style = PaintingStyle.stroke;
  static final _g4 = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
  static final _g8 = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
  static final _g14= Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);

  // ── PLAYER SHIP (orange/gold, gun-level engine count) ────────────────
  static void playerShip(Canvas c, double r, double flicker,
      bool shield, double flashT, double t, int gunLvl, bool speedBoost) {

    final fH = 11.0 + flicker * 13;

    // Halo
    _g14.color = (speedBoost ? _cCyan : _cOrange).withOpacity(0.16);
    c.drawCircle(Offset(0, r + 14), speedBoost ? 34 : 28, _g14);

    // Engine flames — count matches gun level (1..6)
    final nozzles = <double>[];
    switch (gunLvl) {
      case 1: nozzles.addAll([0.0]);
      case 2: nozzles.addAll([-9.5, 0.0, 9.5]);
      case 3: nozzles.addAll([-12.0, -4.0, 4.0, 12.0]);
      case 4: nozzles.addAll([-14.0, -7.0, 0.0, 7.0, 14.0]);
      default:nozzles.addAll([-15.0,-9.0,-3.0, 3.0, 9.0, 15.0]);
    }
    final col = speedBoost ? _cCyan : _cGold;
    for (final ox in nozzles) {
      final w = ox == 0 ? 9.0 : 5.5, h = ox == 0 ? fH : fH * 0.60;
      c.drawRRect(RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(ox, r + h * 0.35), width: w, height: h),
          const Radius.circular(5)),
        Paint()..shader = LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [col.withOpacity(0.95), col.withOpacity(0)],
        ).createShader(Rect.fromCenter(center: Offset(ox, r), width: w + 4, height: h + 6)));
      _f.color = Colors.white.withOpacity(0.82);
      c.drawRRect(RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(ox, r + h * 0.22), width: w * 0.38, height: h * 0.65),
          const Radius.circular(3)), _f);
    }

    // Wings
    void wing(bool left) {
      final s2 = left ? -1.0 : 1.0;
      final wp = Path()
        ..moveTo(s2*r*0.22, -r*0.28)..lineTo(s2*r*1.25, r*0.12)
        ..lineTo(s2*r*1.55, r*0.62)..lineTo(s2*r*1.05, r*0.92)
        ..lineTo(s2*r*0.32, r*0.52)..close();
      c.drawPath(wp, Paint()..shader = LinearGradient(
        begin: Alignment(s2*-1,-1), end: Alignment(s2*1,1),
        colors: [_cGold, _cOrange, const Color(0xFFBF360C)],
        stops: const [0,0.45,1],
      ).createShader(Rect.fromCenter(center: Offset(s2*r,0), width: r*2.2, height: r*2.2)));
      _s.color = _cGold.withOpacity(0.55); _s.strokeWidth = 1.1;
      c.drawPath(wp, _s);
      final ep = Path()
        ..moveTo(s2*r*0.72,r*0.3)..lineTo(s2*r*1.0,r*0.1)
        ..lineTo(s2*r*1.22,r*0.42)..lineTo(s2*r*0.92,r*0.72)..close();
      _f.color = Colors.white.withOpacity(0.88); c.drawPath(ep, _f);
      c.drawRRect(RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(s2*r*0.82, r*0.18), width: 4, height: r*0.52),
        const Radius.circular(2)), Paint()..color = const Color(0xFF37474F));
    }
    wing(true); wing(false);

    // Fuselage
    final body = Path()
      ..moveTo(0,-r)..lineTo(r*0.42,-r*0.28)..lineTo(r*0.32,r*0.62)
      ..lineTo(0,r*0.82)..lineTo(-r*0.32,r*0.62)..lineTo(-r*0.42,-r*0.28)..close();
    c.drawPath(body, Paint()..shader = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [_cGold, _cOrange, const Color(0xFFBF360C)], stops: const [0,0.4,1],
    ).createShader(Rect.fromCenter(center: Offset.zero, width: r, height: r*2)));
    _f.color = Colors.white.withOpacity(0.72);
    c.drawPath(Path()
      ..moveTo(0,-r*0.82)..lineTo(r*0.26,-r*0.18)..lineTo(-r*0.26,-r*0.18)..close(), _f);
    _s.color = _cGold.withOpacity(0.48); _s.strokeWidth = 1.2;
    c.drawPath(body, _s);

    // Cockpit
    final cR = Rect.fromCenter(center: Offset(0,-r*0.32), width: r*0.46, height: r*0.52);
    _f.color = const Color(0xFF263238); c.drawOval(cR, _f);
    c.drawOval(Rect.fromCenter(center: Offset(0,-r*0.32), width: r*0.36, height: r*0.40),
      Paint()..shader = RadialGradient(
        center: const Alignment(-0.3,-0.4),
        colors: [_cCyan.withOpacity(0.92),_cCyan.withOpacity(0.55),_cCyan.withOpacity(0.18)],
      ).createShader(cR));
    _f.color = Colors.white.withOpacity(0.52);
    c.drawOval(Rect.fromCenter(center: Offset(-r*0.06,-r*0.43), width: r*0.10, height: r*0.16), _f);
    _f.color = Colors.white; c.drawCircle(Offset(0,-r), r*0.055, _f);

    // Speed boost aura
    if (speedBoost) {
      c.drawPath(body, Paint()..color = _cCyan.withOpacity(0.18 + sin(t*8)*0.06));
      _s.color = _cCyan.withOpacity(0.55 + sin(t*8)*0.1); _s.strokeWidth = 1.8;
      c.drawPath(body, _s);
    }

    // Shield
    if (shield) {
      final a = 0.20 + sin(t*5.5)*0.09;
      c.drawCircle(Offset(0,-r*0.1), r*1.62,
        Paint()..color = _cCyan.withOpacity(a)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      c.drawCircle(Offset(0,-r*0.1), r*1.62,
        Paint()..color = _cCyan.withOpacity(0.55)..style = PaintingStyle.stroke..strokeWidth = 2.2);
    }

    // Hit flash
    if (flashT > 0) {
      c.drawPath(body, Paint()..color = _cRed.withOpacity(flashT.clamp(0.0, 0.7)));
    }
  }

  // ── ALIEN DRONE (green insect) ──────────────────────────────────────
  static void alienDrone(Canvas c, double r, double anim, double flashT) {
    const cM = Color(0xFF8BC34A), cD = Color(0xFF558B2F);
    const cE = Color(0xFFFF1744), cG = Color(0xFFFFEB3B);
    final wp = sin(anim*7)*0.08;

    void wing(bool left) {
      final s2 = left ? -1.0 : 1.0;
      final wg = Path()
        ..moveTo(s2*r*0.18,-r*0.08)
        ..cubicTo(s2*r*(1.2+wp),-r*(0.85+wp),s2*r*(1.85+wp),-r*0.28,s2*r*(1.52+wp),r*0.42)
        ..cubicTo(s2*r*1.18,r*0.72,s2*r*0.58,r*0.52,s2*r*0.22,r*0.28)..close();
      c.drawPath(wg, Paint()..shader = LinearGradient(
        begin: Alignment(s2*-1,-1), end: Alignment(s2*1,1),
        colors: [cM.withOpacity(0.78),cM.withOpacity(0.22),Colors.cyan.withOpacity(0.08)],
      ).createShader(Rect.fromCenter(center: Offset(s2*r,0), width: r*2.2, height: r*2.2)));
      _s.color = cM.withOpacity(0.45); _s.strokeWidth = 0.8; c.drawPath(wg, _s);
      for (var i=0; i<3; i++) {
        _f.color = Colors.white.withOpacity(0.52);
        c.drawCircle(Offset(s2*r*(0.5+i*0.28),-r*0.28+i*r*0.22), r*0.045, _f);
      }
    }
    wing(true); wing(false);

    for (var i=0; i<4; i++) {
      _f.color = (i%2==0?cM:cD).withOpacity(0.92);
      c.drawOval(Rect.fromCenter(center: Offset(0,r*(0.12+i*0.22)), width: r*(0.88-i*0.10), height: r*0.20), _f);
    }
    final bR = Rect.fromCenter(center: Offset(0,-r*0.05), width: r*1.08, height: r*1.45);
    c.drawOval(bR, Paint()..shader = RadialGradient(
      center: const Alignment(-0.3,-0.4),
      colors: [Color.lerp(cM,Colors.white,0.42)!,cM,cD,Color.lerp(cD,Colors.black,0.32)!],
      stops: const [0,0.28,0.68,1],
    ).createShader(bR));
    _s.color = cD.withOpacity(0.55); _s.strokeWidth = 1.0; c.drawOval(bR, _s);

    void eye(double ox) {
      _f.color = Colors.black.withOpacity(0.48);
      c.drawOval(Rect.fromCenter(center: Offset(ox,-r*0.38), width: r*0.34, height: r*0.30), _f);
      _f.color = cE; c.drawOval(Rect.fromCenter(center: Offset(ox,-r*0.38), width: r*0.26, height: r*0.24), _f);
      _f.color = Colors.black; c.drawCircle(Offset(ox,-r*0.38), r*0.09, _f);
      _f.color = Colors.white.withOpacity(0.72); c.drawCircle(Offset(ox-r*0.06,-r*0.43), r*0.048, _f);
      _g4.color = cE.withOpacity(0.55); c.drawOval(Rect.fromCenter(center: Offset(ox,-r*0.38), width: r*0.34, height: r*0.30), _g4);
    }
    eye(-r*0.28); eye(r*0.28);

    _g8.color = cG.withOpacity(0.35); c.drawCircle(Offset.zero, r*0.19*1.9, _g8);
    _f.color = cG; c.drawCircle(Offset.zero, r*0.19, _f);
    _f.color = Colors.white.withOpacity(0.62); c.drawCircle(Offset(-r*0.19*0.3,-r*0.19*0.3), r*0.19*0.38, _f);

    void ant(bool left) {
      final s2=left?-1.0:1.0;
      final ap=Path()..moveTo(s2*r*0.12,-r*0.72)..quadraticBezierTo(s2*r*0.62,-r*1.22,s2*r*0.42,-r*1.55);
      _s.color=cM;_s.strokeWidth=1.6;_s.strokeCap=StrokeCap.round; c.drawPath(ap,_s);
      _g4.color=cG.withOpacity(0.9); c.drawCircle(Offset(s2*r*0.42,-r*1.55), r*0.075, _g4);
    }
    ant(true); ant(false);

    if (flashT>0) {
      c.drawOval(bR, Paint()..color=Colors.white.withOpacity(flashT.clamp(0.0,0.85)));
    }
  }

  // ── ALIEN FIGHTER (blue angular mantis) ─────────────────────────────
  static void alienFighter(Canvas c, double r, double anim, double flashT) {
    const cM = Color(0xFF29B6F6), cD = Color(0xFF0277BD), cE = Color(0xFFE040FB);
    void wing(bool left) {
      final s2=left?-1.0:1.0;
      final wg=Path()
        ..moveTo(s2*r*0.18,-r*0.15)..lineTo(s2*r*1.42,-r*0.62)
        ..lineTo(s2*r*1.65,r*0.28)..lineTo(s2*r*1.05,r*0.58)..lineTo(s2*r*0.22,r*0.18)..close();
      c.drawPath(wg, Paint()..shader = LinearGradient(
        begin: Alignment(s2*-1,-1), end: Alignment(s2*1,1),
        colors: [cM.withOpacity(0.75),cD.withOpacity(0.55),cD.withOpacity(0.22)],
      ).createShader(Rect.fromCenter(center: Offset(s2*r,0), width: r*2.2, height: r*2.2)));
      _s.color=_cCyan.withOpacity(0.55);_s.strokeWidth=1.0; c.drawPath(wg,_s);
      c.drawLine(Offset(s2*r*0.3,-r*0.0),Offset(s2*r*1.4,-r*0.45),
        Paint()..color=_cCyan.withOpacity(0.65)..strokeWidth=1.2);
    }
    wing(true); wing(false);
    final body=Path()
      ..moveTo(0,-r)..lineTo(r*0.45,-r*0.38)..lineTo(r*0.52,r*0.25)..lineTo(r*0.28,r*0.72)
      ..lineTo(0,r*0.88)..lineTo(-r*0.28,r*0.72)..lineTo(-r*0.52,r*0.25)..lineTo(-r*0.45,-r*0.38)..close();
    c.drawPath(body, Paint()..shader = RadialGradient(
      center: const Alignment(-0.3,-0.4),
      colors: [Color.lerp(cM,Colors.white,0.35)!,cM,cD,Color.lerp(cD,Colors.black,0.3)!],
      stops: const [0,0.3,0.65,1],
    ).createShader(Rect.fromCenter(center: Offset.zero, width: r*1.2, height: r*2)));
    _s.color=_cCyan.withOpacity(0.52);_s.strokeWidth=1.1; c.drawPath(body,_s);
    final vR=Rect.fromCenter(center: Offset(0,-r*0.35), width: r*0.75, height: r*0.28);
    _f.color=Colors.black.withOpacity(0.55); c.drawRRect(RRect.fromRectAndRadius(vR,Radius.circular(r*0.12)),_f);
    _f.color=cE; c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0,-r*0.35),width: r*0.62,height: r*0.18),Radius.circular(r*0.08)),_f);
    _f.color=Colors.white.withOpacity(0.65); c.drawOval(Rect.fromCenter(center: Offset(-r*0.18,-r*0.4),width: r*0.12,height: r*0.08),_f);
    _g4.color=cE.withOpacity(0.6); c.drawRRect(RRect.fromRectAndRadius(vR,Radius.circular(r*0.12)),_g4);
    _g8.color=cE.withOpacity(0.32); c.drawCircle(Offset(0,r*0.12), r*0.25, _g8);
    _f.color=cE.withOpacity(0.9); c.drawCircle(Offset(0,r*0.12), r*0.16, _f);
    _f.color=Colors.white.withOpacity(0.55); c.drawCircle(Offset(-r*0.05,r*0.06), r*0.06, _f);
    if (flashT>0) c.drawPath(body, Paint()..color=Colors.white.withOpacity(flashT.clamp(0.0,0.85)));
  }

  // ── ALIEN DESTROYER (purple armoured beetle) ─────────────────────────
  static void alienDestroyer(Canvas c, double r, double anim, double flashT, int hp, int maxHp) {
    const cA=Color(0xFF7B1FA2),cL=Color(0xFFCE93D8),cE=Color(0xFFFF6D00);
    for (var i=0;i<8;i++){
      final a=i*pi/4-pi/8;
      final pl=Path()
        ..moveTo(cos(a-0.28)*r*0.62,sin(a-0.28)*r*0.62)
        ..lineTo(cos(a)*r,sin(a)*r)
        ..lineTo(cos(a+0.28)*r*0.62,sin(a+0.28)*r*0.62)..close();
      _f.color=(i%2==0?cA:Color.lerp(cA,Colors.black,0.3)!).withOpacity(0.92);
      c.drawPath(pl,_f);
    }
    final body=Path();
    for (var i=0;i<8;i++){final a=i*pi/4-pi/8;if(i==0)body.moveTo(cos(a)*r*0.78,sin(a)*r*0.78);else body.lineTo(cos(a)*r*0.78,sin(a)*r*0.78);}
    body.close();
    c.drawPath(body, Paint()..shader=RadialGradient(
      center: const Alignment(-0.25,-0.35),
      colors: [Color.lerp(cA,Colors.white,0.30)!,cA,Color.lerp(cA,Colors.black,0.35)!],
      stops: const [0,0.5,1],
    ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)));
    _s.color=cL.withOpacity(0.45);_s.strokeWidth=1.5; c.drawPath(body,_s);
    for (var i=-1;i<=1;i++){
      final ex=i*r*0.32;
      _g4.color=cE.withOpacity(0.6); c.drawCircle(Offset(ex,-r*0.18),r*0.16,_g4);
      _f.color=cE; c.drawCircle(Offset(ex,-r*0.18),r*0.12,_f);
      _f.color=Colors.black; c.drawCircle(Offset(ex,-r*0.18),r*0.07,_f);
      _f.color=Colors.white.withOpacity(0.65); c.drawCircle(Offset(ex-r*0.04,-r*0.22),r*0.035,_f);
    }
    for (final s2 in [-1.0,1.0]){
      _f.color=const Color(0xFF37474F);
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(s2*r*0.85,r*0.15),width: r*0.28,height: r*0.48),Radius.circular(r*0.06)),_f);
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(s2*r*0.85,-r*0.05),width: r*0.16,height: r*0.28),Radius.circular(r*0.04)),
        Paint()..color=cE.withOpacity(0.7)..maskFilter=const MaskFilter.blur(BlurStyle.normal,3));
    }
    _g8.color=cL.withOpacity(0.25); c.drawCircle(Offset(0,r*0.2),r*0.32,_g8);
    _f.color=cL.withOpacity(0.7); c.drawCircle(Offset(0,r*0.2),r*0.18,_f);
    _f.color=Colors.white.withOpacity(0.55); c.drawCircle(Offset(-r*0.06,r*0.12),r*0.07,_f);
    if (maxHp>1){
      final bW=r*2.4,bH=5.5,bY=r+8.0,pct=(hp/maxHp).clamp(0.0,1.0);
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0,bY),width: bW,height: bH),const Radius.circular(3)),Paint()..color=Colors.black.withOpacity(0.65));
      if (pct>0) c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-bW/2,bY-bH/2,bW*pct,bH),const Radius.circular(3)),Paint()..color=pct>0.5?cL:_cRed);
    }
    if (flashT>0) c.drawPath(body, Paint()..color=Colors.white.withOpacity(flashT.clamp(0.0,0.88)));
  }

  // ── ALIEN BOSS ────────────────────────────────────────────────────────
  static void alienBoss(Canvas c, double r, double anim, int phase, double flashT, int hp, int maxHp) {
    final col=phase==1?const Color(0xFFE53935):phase==2?_cPurple:_cOrange;
    final glow=sin(anim*3)*0.08+0.22;
    _g14.color=col.withOpacity(glow); c.drawCircle(Offset.zero,r*1.08,_g14);
    for (var i=0;i<12;i++){
      final a=i*pi/6+anim*0.15;
      final pl=Path()..moveTo(cos(a-0.2)*r*0.65,sin(a-0.2)*r*0.65)..lineTo(cos(a)*r,sin(a)*r)..lineTo(cos(a+0.2)*r*0.65,sin(a+0.2)*r*0.65)..close();
      _f.color=Color.lerp(col,Colors.black,i%2==0?0.2:0.45)!.withOpacity(0.92); c.drawPath(pl,_f);
      _s.color=col.withOpacity(0.4);_s.strokeWidth=0.8; c.drawPath(pl,_s);
    }
    final body=Path();
    for (var i=0;i<12;i++){final a=i*pi/6;if(i==0)body.moveTo(cos(a)*r*0.72,sin(a)*r*0.72);else body.lineTo(cos(a)*r*0.72,sin(a)*r*0.72);}
    body.close();
    c.drawPath(body, Paint()..shader=RadialGradient(
      center: const Alignment(-0.2,-0.3),
      colors: [Color.lerp(col,Colors.white,0.38)!,col,Color.lerp(col,Colors.black,0.42)!],
      stops: const [0,0.45,1],
    ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)));
    _s.color=col.withOpacity(0.55);_s.strokeWidth=1.5; c.drawPath(body,_s);
    final ec=phase==1?3:phase==2?5:7;
    for (var i=0;i<ec;i++){
      final ex=(i-(ec-1)/2)*r*(0.62/ec*2),er=r*(0.18-ec*0.01).clamp(0.06,0.18);
      _g4.color=const Color(0xFFFFEB3B).withOpacity(0.65); c.drawCircle(Offset(ex,-r*0.12),er*1.6,_g4);
      _f.color=const Color(0xFFFFEB3B); c.drawCircle(Offset(ex,-r*0.12),er,_f);
      _f.color=Colors.black; c.drawCircle(Offset(ex,-r*0.12),er*0.55,_f);
      _f.color=Colors.white.withOpacity(0.65); c.drawCircle(Offset(ex-er*0.3,-r*0.17),er*0.28,_f);
    }
    final cr2=r*0.25+sin(anim*4)*r*0.04;
    _g8.color=col.withOpacity(0.55); c.drawCircle(Offset(0,r*0.22),cr2*2,_g8);
    _f.color=col; c.drawCircle(Offset(0,r*0.22),cr2,_f);
    _f.color=Colors.white.withOpacity(0.72); c.drawCircle(Offset(-cr2*0.3,r*0.14),cr2*0.38,_f);
    final arms=phase==3?6:phase==2?4:2;
    for (var i=0;i<arms;i++){
      final a=i*(2*pi/arms)+anim*0.5;
      final ap=Path()..moveTo(cos(a)*r*0.45,sin(a)*r*0.45)..lineTo(cos(a)*r*0.95,sin(a)*r*0.95);
      c.drawPath(ap, Paint()..color=col.withOpacity(0.7)..strokeWidth=3.5..style=PaintingStyle.stroke..strokeCap=StrokeCap.round..maskFilter=const MaskFilter.blur(BlurStyle.normal,3));
    }
    final bW=r*2.4,bH=7.0,bY=r+12.0,pct=(hp/maxHp).clamp(0.0,1.0);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0,bY),width: bW,height: bH),const Radius.circular(3.5)),Paint()..color=Colors.black.withOpacity(0.70));
    if (pct>0) c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-bW/2,bY-bH/2,bW*pct,bH),const Radius.circular(3.5)),Paint()..color=pct>0.6?col:pct>0.3?_cGold:_cRed);
    if (flashT>0) c.drawPath(body, Paint()..color=Colors.white.withOpacity(flashT.clamp(0.0,0.90)));
  }

  // ── BULLET ────────────────────────────────────────────────────────────
  static void bullet(Canvas c, bool enemy, bool multi, bool speed) {
    final col=enemy?_cRed:(multi?_cGold:_cAccent);
    final bW=enemy?7.0:4.2, bH=speed?(enemy?7.0:20.0):(enemy?6.0:16.0);
    final g8=Paint()..maskFilter=const MaskFilter.blur(BlurStyle.normal,8);
    g8.color=col.withOpacity(0.38);
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: bW*2.6, height: bH*1.6), g8);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: bW, height: bH),const Radius.circular(4)),
      Paint()..color=enemy?const Color(0xFFFFB090):Colors.white);
    final f=Paint()..color=Colors.white.withOpacity(0.85);
    c.drawCircle(Offset(0,enemy?0:-bH*0.38), bW*0.29, f);
  }

  // ── POWER-UP ──────────────────────────────────────────────────────────
  static void powerUp(Canvas c, PUKind kind, double r, double pulse, double rot) {
    final col=_puColor(kind);
    final pr=r*(sin(pulse)*0.14+1.0);
    c.save(); c.rotate(rot);
    final g8=Paint()..maskFilter=const MaskFilter.blur(BlurStyle.normal,8);
    g8.color=col.withOpacity(0.3); c.drawCircle(Offset.zero, pr*1.42, g8);
    final f=Paint()..color=col.withOpacity(0.9); c.drawCircle(Offset.zero, pr, f);
    final s2=Paint()..style=PaintingStyle.stroke..color=Colors.white.withOpacity(0.30)..strokeWidth=1.6;
    c.drawCircle(Offset.zero, pr, s2);
    f.color=Colors.white.withOpacity(0.22); c.drawCircle(Offset(-pr*0.28,-pr*0.28), pr*0.38, f);
    c.restore();
    final tp=TextPainter(text: TextSpan(text: _puGlyph(kind), style: TextStyle(fontSize: pr*0.95, color: Colors.white)), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, Offset(-tp.width/2,-tp.height/2));
  }

  static Color _puColor(PUKind k) => switch(k) {
    PUKind.shield=>_cCyan, PUKind.rapid=>_cRed, PUKind.life=>const Color(0xFF6BFF6B), PUKind.bomb=>const Color(0xFFFF9F43),
  };
  static String _puGlyph(PUKind k) => switch(k) {
    PUKind.shield=>'🛡', PUKind.rapid=>'⚡', PUKind.life=>'♥', PUKind.bomb=>'💣',
  };
}

// ══════════════════════════════════════════════════════════════════════
//  DATA CLASSES
// ══════════════════════════════════════════════════════════════════════
class _Star { double x,y,spd,r,alpha; final int layer; _Star(this.x,this.y,this.spd,this.r,this.alpha,this.layer); }
class _Nebula { final double x,y,r; final Color col; _Nebula(this.x,this.y,this.r,this.col); }
class _Label {
  double x,y; double vy,life; final String text; final Color col; final double fs;
  _Label(this.x,this.y,this.text,this.col,{this.vy=-90,this.life=0.88,this.fs=18});
  bool get dead=>life<=0;
  void update(double dt){y+=vy*dt;life-=dt*1.35;}
}
class _Ptcl {
  double x,y,vx,vy,life,size; Color col; final bool spark;
  _Ptcl({required this.x,required this.y,required this.vx,required this.vy,required this.life,required this.size,required this.col,this.spark=false});
  bool get dead=>life<=0;
  void update(double dt){x+=vx*dt;y+=vy*dt;vy+=58*dt;vx*=1-dt*1.9;life-=dt*2.5;if(size>0.4)size-=dt*size*0.95;}
}
class _Bullet {
  double x,y,vx,vy; final bool enemy; bool dead=false; final bool multi;
  _Bullet(this.x,this.y,this.vx,this.vy,{this.enemy=false,this.multi=false});
  void update(double dt){x+=vx*dt;y+=vy*dt;}
}
class _Alien {
  double x,y,vy,rot=0,rotSpd,flash=0;
  double baseX,oscPhase,oscAmp,shootTimer;
  final AlienKind kind; late int hp,maxHp; bool dead=false;
  late double cr; late int score; late Color col;
  // Boss-specific: boss enters from top then anchors at bossAnchorY
  bool bossAnchored=false;
  double bossAnchorY=170.0;
  double _bossHoverPhase=0.0;
  _Alien(this.x,this.y,this.kind,this.vy,this.rotSpd,this.oscPhase,this.oscAmp,this.shootTimer):baseX=x{
    switch(kind){
      case AlienKind.drone:    hp=maxHp=1;cr=20;score=10;col=_cGreen;
      case AlienKind.fighter:  hp=maxHp=2;cr=16;score=20;col=const Color(0xFF29B6F6);
      case AlienKind.destroyer:hp=maxHp=6;cr=28;score=50;col=_cPurple;
      case AlienKind.boss:     hp=maxHp=80;cr=58;score=500;col=_cRed;
    }
  }
  void update(double dt,double sw){
    rot+=rotSpd*dt;
    if(kind==AlienKind.boss){
      if(!bossAnchored){
        // Slow entry slide down from off-screen
        y+=vy*dt;
        if(y>=bossAnchorY){y=bossAnchorY;bossAnchored=true;vy=0;}
      } else {
        // Gentle hovering: slow vertical bob + wide horizontal sweep
        _bossHoverPhase+=dt*0.9;
        oscPhase+=dt*0.7;
        y=bossAnchorY+sin(_bossHoverPhase)*26.0;
        x=baseX+sin(oscPhase)*oscAmp;
        x=x.clamp(cr,sw-cr);
      }
    } else {
      y+=vy*dt;
      oscPhase+=dt*(kind==AlienKind.fighter?2.4:1.5);
      x=baseX+sin(oscPhase)*oscAmp;
      x=x.clamp(cr,sw-cr);
    }
    shootTimer-=dt;if(flash>0)flash-=dt*5;
  }
  int get bossPhase{final p=hp/maxHp;return p>0.65?1:p>0.32?2:3;}
}
class _PU {
  double x,y,rot=0,pulse=0; final PUKind kind; bool dead=false;
  static const vy=108.0,r=16.0;
  _PU(this.x,this.y,this.kind);
  void update(double dt){y+=vy*dt;rot+=dt*2.8;pulse+=dt*3.2;}
}

// ══════════════════════════════════════════════════════════════════════
//  FORMATION SYSTEM
// ══════════════════════════════════════════════════════════════════════
class _Formation {
  static List<Offset> build(WaveShape shape,int count,double sw){
    switch(shape){
      case WaveShape.vForm:    return _v(count,sw);
      case WaveShape.grid:     return _grid(count,sw);
      case WaveShape.heart:    return _heart(count,sw);
      case WaveShape.diamond:  return _diamond(count,sw);
      case WaveShape.swarm:    return _swarm(count,sw);
      case WaveShape.bossWave: return [Offset(sw/2,-90)];
    }
  }
  static List<Offset> _v(int n,double sw){final r=<Offset>[],cx=sw/2;for(var i=0;i<n;i++){final s=i%2==0?1:-1,row=i~/2;r.add(Offset(cx+s*row*52,-60.0-row*50));}return r;}
  static List<Offset> _grid(int n,double sw){final cols=min(5,n),rows=(n/cols).ceil(),sx=sw/2-cols*52/2;return List.generate(n,(i)=>Offset(sx+(i%cols)*52,-60.0-(i~/cols)*55));}
  static List<Offset> _heart(int n,double sw){return List.generate(n,(i){final t=(i/n)*2*pi,hx=16*pow(sin(t),3).toDouble(),hy=-(13*cos(t)-5*cos(2*t)-2*cos(3*t)-cos(4*t));return Offset(sw/2+hx*14,-80.0+hy*14);});}
  static List<Offset> _diamond(int n,double sw){final sides=max(4,(n/4).ceil()*4);return List.generate(n,(i){final t=(i/sides)*2*pi;return Offset(sw/2+cos(t)*120,-100.0+sin(t)*60);});}
  static List<Offset> _swarm(int n,double sw){final rng=Random(42);return List.generate(n,(_)=>Offset(rng.nextDouble()*(sw-80)+40,-40.0-rng.nextDouble()*200));}
}

// ══════════════════════════════════════════════════════════════════════
//  GAME STATE — all play variables
// ══════════════════════════════════════════════════════════════════════
class _GS {
  final rng=Random();
  double sw=0,sh=0,time=0;

  GamePhase phase=GamePhase.title;
  int score=0,hi=0,lives=3,level=1,combo=0;
  double comboTimer=0;
  int lastLevel=1;   // persisted — level to resume from
  int maxLevel=1;    // persisted — highest level ever reached

  // Ship
  double shipX=0,shipY=0,targetX=0,targetY=0;
  double invT=0,flashT=0,engineFlicker=0;
  List<Offset> trail=[];

  // ── RELOAD STORE ─────────────────────────────────────────────────────
  bool shield=false;
  double shieldT=0;       // remaining shield time
  bool speedBoost=false;
  double speedT=0;        // remaining speed boost time
  int gunLevel=1;         // 1-6 gun spread
  double gunT=0;          // remaining gun upgrade time
  int bombs=0;

  // ── LEVEL SYSTEM (seamless — no phase change) ──────────────────────
  double levelUpOverlay=0.0;  // show "LEVEL X" text when > 0
  double bossWarnOverlay=0.0; // show "BOSS INCOMING" when > 0
  int waveKills=0;

  // World
  List<_Star>   stars=[];
  List<_Nebula> nebulae=[];
  List<_Alien>  aliens=[];
  List<_Bullet> bullets=[];
  List<_Ptcl>   ptcls=[];
  List<_PU>     pus=[];
  List<_Label>  labels=[];

  // Wave spawn queue
  double fireT=0,spawnT=0;
  List<Offset> wavePositions=[];
  int waveIdx=0;
  AlienKind waveKind=AlienKind.drone;
  bool spawning=false;

  // Screen effects
  double shakeT=0,flashScreen=0,titleAnim=0;

  // Reload notification
  String reloadMsg='';
  double reloadMsgT=0;

  // Derived
  double get alienSpd => (62+level*11).toDouble(); // reduced from 95+20x for better pacing
  int get killsForLevel => 12+level*3;

  bool get canAffordReload => score >= _kReloadCost;

  void initWorld(double w,double h){
    sw=w;sh=h;shipX=targetX=w/2;shipY=targetY=h-130;
    stars=List.generate(155,(i){final l=i%3;return _Star(rng.nextDouble()*w,rng.nextDouble()*h,9+l*18+rng.nextDouble()*12,0.38+l*0.55+rng.nextDouble()*0.65,0.16+l*0.20+rng.nextDouble()*0.28,l);});
    nebulae=[
      _Nebula(w*0.14,h*0.20,245,const Color(0xFF1A3A8A)),
      _Nebula(w*0.86,h*0.08,195,const Color(0xFF3A1A6A)),
      _Nebula(w*0.50,h*0.65,215,const Color(0xFF0A3A5A)),
      _Nebula(w*0.25,h*0.48,165,const Color(0xFF162055)),
    ];
  }

  void reset(){
    score=0;lives=3;level=1;combo=0;comboTimer=0;
    shield=false;speedBoost=false;gunLevel=1;bombs=0;
    shieldT=speedT=gunT=invT=flashT=0;
    aliens.clear();bullets.clear();ptcls.clear();pus.clear();trail.clear();labels.clear();
    fireT=spawnT=0;waveKills=0;wavePositions.clear();waveIdx=0;spawning=false;
    shakeT=flashScreen=levelUpOverlay=bossWarnOverlay=0;
    reloadMsg='';reloadMsgT=0;
    phase=GamePhase.playing;
    _queueWave();
  }

  /// Resume from the last saved level (score starts fresh but level is restored).
  void continueGame(){
    score=0;lives=3;combo=0;comboTimer=0;
    shield=false;speedBoost=false;gunLevel=1;bombs=0;
    shieldT=speedT=gunT=invT=flashT=0;
    aliens.clear();bullets.clear();ptcls.clear();pus.clear();trail.clear();labels.clear();
    fireT=spawnT=0;waveKills=0;wavePositions.clear();waveIdx=0;spawning=false;
    shakeT=flashScreen=levelUpOverlay=bossWarnOverlay=0;
    reloadMsg='';reloadMsgT=0;
    level=lastLevel.clamp(1,999);
    phase=GamePhase.playing;
    _queueWave();
  }

  void _queueWave(){
    final isBoss=level%5==0;
    if(isBoss){
      wavePositions=[Offset(sw/2,-90)];
      waveKind=AlienKind.boss;
    } else {
      final shapes=[WaveShape.vForm,WaveShape.grid,WaveShape.heart,WaveShape.diamond,WaveShape.swarm];
      final shape=shapes[(level-1)%shapes.length];
      final count=8+level*2;
      final kind=level>=6&&rng.nextDouble()<0.25?AlienKind.destroyer
                :level>=3&&rng.nextDouble()<0.5?AlienKind.fighter
                :AlienKind.drone;
      wavePositions=_Formation.build(shape,count,sw);
      waveKind=kind;
    }
    waveIdx=0;spawning=true;spawnT=0;
  }
}

// ══════════════════════════════════════════════════════════════════════
//  LOGIC
// ══════════════════════════════════════════════════════════════════════
class _Logic {
  final _GS s;
  _Logic(this.s);

  void update(double dt){
    s.time+=dt;
    _scrollStars(dt);
    _updatePtcls(dt);
    _updateLabels(dt);
    if(s.levelUpOverlay>0) s.levelUpOverlay-=dt;
    if(s.bossWarnOverlay>0) s.bossWarnOverlay-=dt;
    if(s.reloadMsgT>0) s.reloadMsgT-=dt;

    switch(s.phase){
      case GamePhase.title: s.titleAnim+=dt;
      case GamePhase.playing: _tickPlaying(dt);
      default: break;
    }
  }

  void _scrollStars(double dt){for(final st in s.stars){st.y+=st.spd*dt;if(st.y>s.sh){st.y=-4;st.x=s.rng.nextDouble()*s.sw;}}}
  void _updatePtcls(double dt){for(final p in s.ptcls)p.update(dt);s.ptcls.removeWhere((p)=>p.dead);}
  void _updateLabels(double dt){for(final l in s.labels)l.update(dt);s.labels.removeWhere((l)=>l.dead);}

  void _tickPlaying(double dt){
    _moveShip(dt);
    _autoFire(dt);
    _updateBullets(dt);
    _updateAliens(dt);
    _updatePUs(dt);
    _updateTimers(dt);
    _spawnWave(dt);
    _collide();
    s.engineFlicker=sin(s.time*22)*0.5+0.5;
    // Check wave complete
    if(s.spawning==false && s.aliens.isEmpty){_waveComplete();}
  }

  void _moveShip(double dt){
    final spd = s.speedBoost ? 0.002 : 0.010;
    s.shipX+=(s.targetX-s.shipX)*(1-pow(spd,dt));
    s.shipY+=(s.targetY-s.shipY)*(1-pow(0.009,dt));
    s.shipX=s.shipX.clamp(_kShipR,s.sw-_kShipR);
    s.shipY=s.shipY.clamp(_kShipR,s.sh-_kShipR);
    s.trail.insert(0,Offset(s.shipX,s.shipY));
    if(s.trail.length>22)s.trail.removeLast();
  }

  void _autoFire(double dt){
    s.fireT-=dt;
    if(s.fireT>0)return;
    final delay=s.gunLevel>1?(_kBaseFireDt*0.82):_kBaseFireDt;
    s.fireT=delay;
    _spawnGunBullets();
    GameAudio.playShoot();
  }

  void _spawnGunBullets(){
    final gl=(s.gunLevel-1).clamp(0,4);
    final angles=_kGunSpreads[gl];
    final bSpd=s.speedBoost?1100.0:900.0;
    final isMulti=s.gunLevel>1;
    for(final deg in angles){
      final rad=deg*pi/180;
      s.bullets.add(_Bullet(s.shipX,s.shipY-26,sin(rad)*320,-bSpd*cos(rad),multi:isMulti));
    }
  }

  void _updateBullets(double dt){
    for(final b in s.bullets)b.update(dt);
    s.bullets.removeWhere((b)=>b.dead||b.y<-22||b.y>s.sh+22||b.x<-22||b.x>s.sw+22);
  }

  void _updateAliens(double dt){
    for(final e in s.aliens){
      e.update(dt,s.sw);
      // Only non-boss aliens die when they fall off screen
      if(e.kind!=AlienKind.boss && e.y>s.sh+80)e.dead=true;
      // Boss shoots as soon as it appears on screen; others only when past top 80px
      final shootThreshold = e.kind==AlienKind.boss ? -200.0 : 80.0;
      if(e.shootTimer<=0&&!e.dead&&e.y>shootThreshold){e.shootTimer=_shtInt(e.kind);_shootAlien(e);}
    }
    s.aliens.removeWhere((e)=>e.dead);
  }

  void _updatePUs(double dt){
    for(final p in s.pus)p.update(dt);
    s.pus.removeWhere((p)=>p.dead||p.y>s.sh+40);
  }

  void _updateTimers(double dt){
    if(s.invT>0)s.invT-=dt;
    if(s.flashT>0)s.flashT-=dt;
    if(s.shakeT>0)s.shakeT-=dt;
    if(s.flashScreen>0)s.flashScreen-=dt*3.0;
    if(s.comboTimer>0){s.comboTimer-=dt;if(s.comboTimer<=0)s.combo=0;}
    if(s.shieldT>0){s.shieldT-=dt;if(s.shieldT<=0)s.shield=false;}
    if(s.speedT>0){s.speedT-=dt;if(s.speedT<=0)s.speedBoost=false;}
    if(s.gunT>0){s.gunT-=dt;if(s.gunT<=0&&s.gunLevel>1){s.gunLevel=1;_label(s.shipX,s.shipY-40,'GUN EXPIRED',const Color(0xFF78909C));}}
  }

  double _shtInt(AlienKind k){
    final b=k==AlienKind.boss?0.8:k==AlienKind.destroyer?1.8:k==AlienKind.fighter?3.2:2.8;
    return (b-s.level*0.06).clamp(0.55,b);
  }

  void _shootAlien(_Alien e){
    final dx=s.shipX-e.x,dy=s.shipY-e.y,m=sqrt(dx*dx+dy*dy);
    if(m<1)return;
    const spd=318.0;
    if(e.kind==AlienKind.boss){
      final ph=e.bossPhase,shots=ph==3?7:ph==2?5:3;
      for(var i=0;i<shots;i++){
        final sp=(i-(shots-1)/2)*0.22,nx=dx/m,ny=dy/m;
        final rx=nx*cos(sp)-ny*sin(sp),ry=nx*sin(sp)+ny*cos(sp);
        s.bullets.add(_Bullet(e.x,e.y,rx*spd*0.9,ry*spd*0.9,enemy:true));
      }
    } else {
      s.bullets.add(_Bullet(e.x,e.y,dx/m*spd,dy/m*spd,enemy:true));
    }
  }

  void _spawnWave(double dt){
    if(!s.spawning)return;
    s.spawnT-=dt;
    if(s.spawnT>0)return;
    if(s.waveIdx>=s.wavePositions.length){s.spawning=false;return;}
    s.spawnT=s.waveKind==AlienKind.boss?0.0:0.16;
    final pos=s.wavePositions[s.waveIdx++];
    // Boss enters slowly; normal aliens use alienSpd
    final vy=s.waveKind==AlienKind.boss?90.0:s.alienSpd+s.rng.nextDouble()*20;
    final rotS=(s.rng.nextDouble()-0.5)*2.6;
    // Boss sweeps wide horizontally; normal aliens have moderate oscillation
    final amp=s.waveKind==AlienKind.boss?115.0:22+s.rng.nextDouble()*50;
    final shtT=0.8+s.rng.nextDouble()*2.2;
    final alien=_Alien(pos.dx,pos.dy,s.waveKind,vy,rotS,s.rng.nextDouble()*pi*2,amp,shtT);
    if(s.waveKind==AlienKind.boss){
      // Anchor boss at ~20% down the screen so it's always visible and in "fighting range"
      alien.bossAnchorY=(s.sh*0.20).clamp(130.0,220.0);
    }
    s.aliens.add(alien);
  }

  void _waveComplete(){
    if(s.levelUpOverlay>0)return; // already transitioning
    _label(s.sw/2,s.sh*0.38,'WAVE  CLEAR!',const Color(0xFF6BFF6B),big:true);
    s.levelUpOverlay=3.5;  // was 2.2 — longer display time
    s.waveKills=0;
    s.level++;
    // Persist progress so Continue works from here
    if(s.level>s.maxLevel)s.maxLevel=s.level;
    s.lastLevel=s.level;
    SharedPreferences.getInstance().then((p){
      p.setInt('nova_last_level',s.lastLevel);
      p.setInt('nova_max_level',s.maxLevel);
    });
    if(s.level%5==0){
      s.bossWarnOverlay=3.5;  // was 2.2
      Future.delayed(const Duration(milliseconds:3500),(){
        if(s.phase==GamePhase.playing){s._queueWave();}
      });
    } else {
      s._queueWave();
    }
    GameAudio.playLevelUp();
  }

  void _collide(){
    for(final b in s.bullets.where((b)=>!b.enemy&&!b.dead)){
      for(final e in s.aliens){
        if(e.dead)continue;
        final dx=b.x-e.x,dy=b.y-e.y;
        if(dx*dx+dy*dy<(e.cr+5)*(e.cr+5)){
          b.dead=true;e.flash=1.0;e.hp--;
          if(e.hp<=0){e.dead=true;_killAlien(e);}
          else{GameAudio.playHit();_boom(b.x,b.y,Colors.white,5);}
          break;
        }
      }
    }
    if(s.invT>0)return;
    for(final e in s.aliens){
      if(e.dead)continue;
      final dx=e.x-s.shipX,dy=e.y-s.shipY;
      if(dx*dx+dy*dy<(e.cr+_kShipR)*(e.cr+_kShipR)){e.dead=true;_killAlien(e,award:false);_hitPlayer();return;}
    }
    for(final b in s.bullets.where((b)=>b.enemy&&!b.dead)){
      final dx=b.x-s.shipX,dy=b.y-s.shipY;
      if(dx*dx+dy*dy<16*16){b.dead=true;_hitPlayer();return;}
    }
    for(final p in s.pus){
      if(p.dead)continue;
      final dx=p.x-s.shipX,dy=p.y-s.shipY;
      if(dx*dx+dy*dy<(22+_kShipR)*(22+_kShipR)){p.dead=true;_collectPU(p.kind);}
    }
  }

  void _hitPlayer(){
    if(s.shield){
      s.shield=false;s.shieldT=0;_boom(s.shipX,s.shipY,_cCyan,12);
      s.shakeT=_kShakeDur*0.5;s.combo=0;
      _label(s.shipX,s.shipY-32,'SHIELD BROKEN!',_cCyan);
      // Gun degrades on hit
      if(s.gunLevel>1){s.gunLevel--;_label(s.shipX,s.shipY-52,'GUN LEVEL DOWN',_cGold);}
      GameAudio.playHit();return;
    }
    // Gun degrades on hit
    if(s.gunLevel>1){s.gunLevel=max(1,s.gunLevel-1);}
    s.lives--;s.invT=_kInvDur;s.flashT=0.55;
    s.combo=0;s.comboTimer=0;s.shakeT=_kShakeDur;s.flashScreen=0.50;
    _boom(s.shipX,s.shipY,_cAccent,24);
    GameAudio.playHit();
    if(s.lives<=1&&s.lives>0)_label(s.shipX,s.shipY-40,'⚠  DANGER!',_cRed,big:true);
    if(s.lives<=0)_endGame();
  }

  void _endGame(){
    s.phase=GamePhase.gameOver;
    if(s.score>s.hi)s.hi=s.score;
    if(s.level>s.maxLevel)s.maxLevel=s.level;
    s.lastLevel=s.level.clamp(1,999);
    GameAudio.playGameOver();
    SharedPreferences.getInstance().then((p){
      p.setInt('nova_hi',s.hi);
      p.setInt('nova_last_level',s.lastLevel);
      p.setInt('nova_max_level',s.maxLevel);
    });
  }

  void _killAlien(_Alien e,{bool award=true}){
    GameAudio.playExplosion();
    _boom(e.x,e.y,e.col,e.kind==AlienKind.boss||e.kind==AlienKind.destroyer?22:12);
    if(e.kind==AlienKind.boss||e.kind==AlienKind.destroyer)s.shakeT=_kShakeDur*(e.kind==AlienKind.boss?1.5:0.9);
    if(!award)return;
    s.combo++;s.comboTimer=_kComboTO;
    final mult=s.combo>=10?5:s.combo>=6?3:s.combo>=3?2:1;
    final pts=e.score*mult;
    s.score+=pts;s.waveKills++;
    _label(e.x,e.y-12,'+$pts',e.col);
    if(s.combo==3) _label(e.x,e.y-36,'×2 COMBO!',_cGold,big:true);
    if(s.combo==6) _label(e.x,e.y-36,'×3 COMBO!',_cGold,big:true);
    if(s.combo==10)_label(e.x,e.y-36,'×5 COMBO!',_cGold,big:true);
    if(e.kind==AlienKind.boss)_label(s.sw/2,s.sh*0.4,'BOSS  SLAIN!',_cGold,big:true);
    if(s.rng.nextDouble()<0.18)s.pus.add(_PU(e.x,e.y,PUKind.values[s.rng.nextInt(PUKind.values.length)]));
  }

  void _collectPU(PUKind k){
    GameAudio.playPowerup();
    String msg;Color col;
    switch(k){
      case PUKind.shield:s.shield=true;s.shieldT=_kShieldDur;msg='SHIELD ON!';col=_cCyan;
      case PUKind.rapid: s.gunLevel=min(s.gunLevel+1,5);s.gunT=_kGunDur;msg='GUN UP!';col=_cGold;
      case PUKind.life:  if(s.lives<10)s.lives+=2;msg='+2 LIFE!';col=const Color(0xFF6BFF6B);
      case PUKind.bomb:  s.bombs++;msg='BOMB +1!';col=const Color(0xFFFF9F43);
    }
    _label(s.shipX,s.shipY-42,msg,col,big:true);
    _boom(s.shipX,s.shipY,col,15);
  }

  void _boom(double x,double y,Color col,int n){
    for(var i=0;i<n;i++){
      final a=s.rng.nextDouble()*2*pi,spd=68+s.rng.nextDouble()*235;
      s.ptcls.add(_Ptcl(x:x,y:y,vx:cos(a)*spd,vy:sin(a)*spd-58,life:0.55+s.rng.nextDouble()*0.58,size:2+s.rng.nextDouble()*4.8,col:Color.lerp(col,Colors.white,s.rng.nextDouble()*0.52)!,spark:s.rng.nextBool()));
    }
    s.ptcls.add(_Ptcl(x:x,y:y,vx:0,vy:0,life:0.26,size:38,col:col.withOpacity(0.50)));
  }

  void _label(double x,double y,String text,Color col,{bool big=false}){
    s.labels.add(_Label(x,y,text,col,fs:big?22:17,vy:big?-105:-82,life:big?1.05:0.85));
  }

  // ── RELOAD STORE ACTIONS ──────────────────────────────────────────────
  bool reloadLife(){
    if(!s.canAffordReload){_reloadFail();return false;}
    s.score=max(0,s.score-_kReloadCost);
    s.lives=min(s.lives+_kLifeAmt,10);
    _label(s.shipX,s.shipY-50,'+$_kLifeAmt LIVES!',const Color(0xFF6BFF6B),big:true);
    _boom(s.shipX,s.shipY,const Color(0xFF6BFF6B),10);
    GameAudio.playPowerup();
    return true;
  }
  bool reloadBomb(){
    if(!s.canAffordReload){_reloadFail();return false;}
    s.score=max(0,s.score-_kReloadCost);
    s.bombs+=3;
    _label(s.shipX,s.shipY-50,'BOMB ×3!',const Color(0xFFFF9F43),big:true);
    GameAudio.playPowerup();
    return true;
  }
  bool reloadGun(){
    if(!s.canAffordReload){_reloadFail();return false;}
    s.score=max(0,s.score-_kReloadCost);
    s.gunLevel=min(s.gunLevel+1,6);
    s.gunT=_kGunDur;
    _label(s.shipX,s.shipY-50,'GUN LVL ${s.gunLevel}!',_cGold,big:true);
    GameAudio.playPowerup();
    return true;
  }
  bool reloadSpeed(){
    if(!s.canAffordReload){_reloadFail();return false;}
    s.score=max(0,s.score-_kReloadCost);
    s.speedBoost=true;s.speedT=_kSpeedDur;
    _label(s.shipX,s.shipY-50,'SPEED BOOST!',_cCyan,big:true);
    GameAudio.playPowerup();
    return true;
  }
  bool reloadShield(){
    if(!s.canAffordReload){_reloadFail();return false;}
    s.score=max(0,s.score-_kReloadCost);
    s.shield=true;s.shieldT=_kShieldDur;
    _label(s.shipX,s.shipY-50,'SHIELD ON!',_cCyan,big:true);
    GameAudio.playPowerup();
    return true;
  }
  void _reloadFail(){s.reloadMsg='NEED 5 SCORE';s.reloadMsgT=1.5;}

  void useBomb(){
    if(s.bombs<=0||s.phase!=GamePhase.playing)return;
    s.bombs--;
    for(final e in s.aliens){_boom(e.x,e.y,e.col,8);e.dead=true;}
    s.bullets.removeWhere((b)=>b.enemy);
    s.shakeT=_kShakeDur*1.9;s.flashScreen=0.68;
    _label(s.sw/2,s.sh*0.42,'💣  BOMB!',_cGold,big:true);
    GameAudio.playExplosion();
  }
}

// ══════════════════════════════════════════════════════════════════════
//  PAINTER
// ══════════════════════════════════════════════════════════════════════
class _Painter extends CustomPainter {
  final _GS s;
  _Painter(this.s);
  static final _f=Paint()..style=PaintingStyle.fill;
  @override bool shouldRepaint(_)=>true;

  @override
  void paint(Canvas c, Size sz){
    c.save();
    if(s.shakeT>0){final mag=_kShakeMag*(s.shakeT/_kShakeDur).clamp(0.0,1.0);c.translate(sin(s.time*67)*mag,cos(s.time*83)*mag);}
    _bg(c,sz);_trail(c);_ptcls(c);_pus(c);_aliens(c);_bullets(c);
    final show=s.phase==GamePhase.playing;
    if(show&&(s.invT<=0||(s.time*9).toInt()%2==0))_ship(c);
    _floatLabels(c);
    if(s.flashScreen>0)c.drawRect(Rect.fromLTWH(0,0,sz.width,sz.height),Paint()..color=Colors.white.withOpacity(s.flashScreen.clamp(0.0,0.55)));
    c.restore();
  }

  void _bg(Canvas c,Size sz){
    c.drawRect(Rect.fromLTWH(0,0,sz.width,sz.height),Paint()..shader=const LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[_cBg1,_cBg2]).createShader(Rect.fromLTWH(0,0,sz.width,sz.height)));
    for(final n in s.nebulae){c.drawCircle(Offset(n.x,n.y),n.r,Paint()..shader=RadialGradient(colors:[n.col.withOpacity(0.15),Colors.transparent]).createShader(Rect.fromCircle(center:Offset(n.x,n.y),radius:n.r)));}
    for(final st in s.stars){_f.color=Colors.white.withOpacity(st.alpha);c.drawCircle(Offset(st.x,st.y),st.r,_f);}
  }

  void _trail(Canvas c){
    final n=s.trail.length;if(n<2)return;
    final tc=s.speedBoost?_cCyan:_cOrange;
    for(var i=0;i<n-1;i++){final t=1.0-i/n;c.drawLine(s.trail[i],s.trail[i+1],Paint()..color=tc.withOpacity(t*0.30)..strokeWidth=t*3.8+0.4..strokeCap=StrokeCap.round);}
  }

  void _ptcls(Canvas c){
    for(final p in s.ptcls){if(p.dead)continue;final a=p.life.clamp(0.0,1.0);_f.color=p.col.withOpacity(a);
    if(p.spark){c.drawLine(Offset(p.x,p.y),Offset(p.x-p.vx*0.024,p.y-p.vy*0.024),Paint()..color=_f.color..strokeWidth=1.7..strokeCap=StrokeCap.round);}
    else c.drawCircle(Offset(p.x,p.y),p.size.clamp(0.5,9.5),_f);}
  }

  void _pus(Canvas c){for(final pu in s.pus){if(pu.dead)continue;c.save();c.translate(pu.x,pu.y);_Art.powerUp(c,pu.kind,_PU.r,pu.pulse,pu.rot);c.restore();}}

  void _aliens(Canvas c){
    for(final e in s.aliens){if(e.dead)continue;
    c.save();c.translate(e.x,e.y);c.rotate(e.rot);
    switch(e.kind){
      case AlienKind.drone:    _Art.alienDrone(c,e.cr,s.time,e.flash);
      case AlienKind.fighter:  _Art.alienFighter(c,e.cr,s.time,e.flash);
      case AlienKind.destroyer:_Art.alienDestroyer(c,e.cr,s.time,e.flash,e.hp,e.maxHp);
      case AlienKind.boss:     _Art.alienBoss(c,e.cr,s.time,e.bossPhase,e.flash,e.hp,e.maxHp);
    }
    c.restore();}
  }

  void _bullets(Canvas c){for(final b in s.bullets){if(b.dead)continue;c.save();c.translate(b.x,b.y);_Art.bullet(c,b.enemy,b.multi,s.speedBoost);c.restore();}}

  void _ship(Canvas c){c.save();c.translate(s.shipX,s.shipY);_Art.playerShip(c,_kShipR,s.engineFlicker,s.shield,s.flashT,s.time,s.gunLevel,s.speedBoost);c.restore();}

  void _floatLabels(Canvas c){
    for(final lbl in s.labels){if(lbl.dead)continue;final a=lbl.life.clamp(0.0,1.0);
    final tp=TextPainter(text:TextSpan(text:lbl.text,style:TextStyle(color:lbl.col.withOpacity(a),fontSize:lbl.fs,fontWeight:FontWeight.w900,letterSpacing:1.2,shadows:[Shadow(color:Colors.black.withOpacity(a*0.85),blurRadius:6,offset:const Offset(0,2))])),textDirection:TextDirection.ltr)..layout();
    tp.paint(c,Offset(lbl.x-tp.width/2,lbl.y-tp.height/2));}
  }
}

// ══════════════════════════════════════════════════════════════════════
//  MAIN WIDGET
// ══════════════════════════════════════════════════════════════════════
class NovaBlasterGame extends StatefulWidget {
  final VoidCallback? onExit;
  const NovaBlasterGame({super.key,this.onExit});
  @override State<NovaBlasterGame> createState()=>_NBS();
}

class _NBS extends State<NovaBlasterGame> with SingleTickerProviderStateMixin {
  late final _GS _gs;
  late final _Logic _logic;
  late final Ticker _ticker;
  Duration? _last;
  final _frame=ValueNotifier(0);

  void _exit(){if(widget.onExit!=null)widget.onExit!();else Navigator.pop(context);}

  @override
  void initState(){
    super.initState();
    _gs=_GS();_logic=_Logic(_gs);
    _ticker=createTicker(_tick)..start();
    SharedPreferences.getInstance().then((p){
      setState((){
        _gs.hi=p.getInt('nova_hi')??0;
        _gs.lastLevel=(p.getInt('nova_last_level')??1).clamp(1,999);
        _gs.maxLevel=(p.getInt('nova_max_level')??1).clamp(1,999);
      });
    });
    GameAudio.initialize().then((_)=>GameAudio.startBackgroundMusic());
  }

  void _tick(Duration e){
    final dt=_last==null?0.016:((e-_last!).inMicroseconds/1e6).clamp(0.0,0.05);
    _last=e;
    if(_gs.sw>0)_logic.update(dt);
    _frame.value++;
  }

  @override void dispose(){_ticker.dispose();_frame.dispose();GameAudio.stopBackgroundMusic();super.dispose();}

  void _onDrag(Offset p){
    if(_gs.phase==GamePhase.playing){
      _gs.targetX=p.dx.clamp(_kShipR,_gs.sw-_kShipR);
      _gs.targetY=p.dy.clamp(_kShipR,_gs.sh-_kShipR);
    }
  }
  void _onTap(Offset p){
    switch(_gs.phase){
      case GamePhase.title: break; // title screen uses explicit buttons
      case GamePhase.playing:_logic.useBomb();
      case GamePhase.gameOver:_gs.reset();GameAudio.startBackgroundMusic();
      case GamePhase.paused:_gs.phase=GamePhase.playing;GameAudio.resumeBackgroundMusic();
    }
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(backgroundColor:_cBg1,body:LayoutBuilder(builder:(_,box){
      final w=box.maxWidth,h=box.maxHeight;
      if(_gs.sw==0){_gs.initWorld(w,h);}  // title screen shows first
      return GestureDetector(
        onPanStart:(d)=>_onDrag(d.localPosition),
        onPanUpdate:(d)=>_onDrag(d.localPosition),
        onTapDown:(d)=>_onTap(d.localPosition),
        child:Stack(children:[
          ValueListenableBuilder<int>(valueListenable:_frame,builder:(_,__,___)=>CustomPaint(painter:_Painter(_gs),size:Size(w,h))),
          ValueListenableBuilder<int>(valueListenable:_frame,builder:(_,__,___)=>_hud(box)),
        ]),
      );
    }));
  }

  // ══════════════════════════════════════════════════════ HUD ROUTER
  Widget _hud(BoxConstraints b)=>switch(_gs.phase){
    GamePhase.title   =>_hudTitle(),
    GamePhase.playing =>_hudPlaying(b),
    GamePhase.gameOver=>_hudGameOver(),
    GamePhase.paused  =>_hudPaused(),
  };

  // ── TITLE — SaaS Premium Screen ─────────────────────────────────────
  Widget _hudTitle() {
    final t      = _gs.titleAnim;
    final blink  = (sin(t * 2.5) * 0.38 + 0.62).clamp(0.22, 1.0);
    final pulse  = (sin(t * 1.8) * 0.5 + 0.5);   // 0..1 for glow intensity
    final shimmer= (sin(t * 3.0) * 0.5 + 0.5);   // text shimmer phase

    return SizedBox.expand(
      child: Stack(children: [

        // ── Animated shooting stars ──────────────────────────────────
        ValueListenableBuilder<int>(
          valueListenable: _frame,
          builder: (_, __, ___) => CustomPaint(
            painter: _ShootingStarPainter(t),
            size: Size(_gs.sw, _gs.sh),
          ),
        ),

        // ── Planet upper right ────────────────────────────────────────
        Positioned(
          top: 0, right: -18,
          child: ValueListenableBuilder<int>(
            valueListenable: _frame,
            builder: (_, __, ___) => SizedBox(
              width: 220, height: 220,
              child: CustomPaint(painter: _TitlePlanetPainter(t)),
            ),
          ),
        ),

        // ── Main scrollable content ───────────────────────────────────
        SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                // Space for planet
                const SizedBox(height: 72),

                // ── LOGO with glow ──────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    boxShadow: [BoxShadow(
                      color: _cAccent.withOpacity(0.28 + shimmer * 0.14),
                      blurRadius: 55, spreadRadius: 8,
                    )],
                  ),
                  child: ShaderMask(
                    shaderCallback: (b) => LinearGradient(
                      colors: [
                        const Color(0xFF4DA3FF),
                        Color.lerp(const Color(0xFF00E5FF), Colors.white, shimmer * 0.3)!,
                        const Color(0xFF4DA3FF),
                      ],
                    ).createShader(b),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('NOVA',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 66,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 8, color: Colors.white, height: 1.04)),
                        Text('BLASTER',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 66,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 8, color: Colors.white, height: 1.04)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 6),
                // ── Subtitle ───────────────────────────────────────
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(width: 28, height: 1, color: _cAccent.withOpacity(0.5)),
                  const SizedBox(width: 10),
                  const Text('OFFLINE  ARCADE',
                    style: TextStyle(color: _cAccent, fontSize: 12,
                      letterSpacing: 5.5, fontWeight: FontWeight.w300)),
                  const SizedBox(width: 10),
                  Container(width: 28, height: 1, color: _cAccent.withOpacity(0.5)),
                ]),

                const SizedBox(height: 38),

                // ── Feature badges row ─────────────────────────────
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _titleBadge('🎮 ARCADE',   _cAccent),
                  const SizedBox(width: 8),
                  _titleBadge('📡 OFFLINE',  _cCyan),
                  const SizedBox(width: 8),
                  _titleBadge('👾 BOSSES',   _cPurple),
                ]),

                const SizedBox(height: 36),

                // ── Launch buttons ─────────────────────────────────
                // CONTINUE button — only shown when the player has reached level 2+
                if (_gs.lastLevel > 1) ...[
                  GestureDetector(
                    onTap: () {
                      _gs.continueGame();
                      GameAudio.startBackgroundMusic();
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 28),
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1A4F8A), Color(0xFF0D2E5A)],
                        ),
                        border: Border.all(color: _cAccent, width: 1.8),
                        boxShadow: [BoxShadow(
                          color: _cAccent.withOpacity(0.35),
                          blurRadius: 28, spreadRadius: 2,
                        )],
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.play_circle_filled_rounded, color: _cAccent, size: 22),
                        const SizedBox(width: 10),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          const Text('CONTINUE',
                            style: TextStyle(color: Colors.white, fontSize: 16,
                              fontWeight: FontWeight.w900, letterSpacing: 3.0)),
                          Text('From  Level ${_gs.lastLevel}',
                            style: TextStyle(color: _cAccent.withOpacity(0.75),
                              fontSize: 10, letterSpacing: 1.5)),
                        ]),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // NEW GAME / TAP TO LAUNCH button
                Stack(alignment: Alignment.center, children: [
                  // Outer pulse ring
                  Container(
                    width: 276 + pulse * 12,
                    height: 58 + pulse * 12,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(
                        color: (_gs.lastLevel > 1 ? _cGold : _cAccent).withOpacity(0.25 - pulse * 0.18),
                        width: 1.5,
                      ),
                    ),
                  ),
                  // Middle ring
                  Container(
                    width: 260 + pulse * 6,
                    height: 54 + pulse * 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(36),
                      border: Border.all(
                        color: (_gs.lastLevel > 1 ? _cGold : _cAccent).withOpacity(0.18 - pulse * 0.12),
                        width: 1.0,
                      ),
                    ),
                  ),
                  // Main button
                  GestureDetector(
                    onTap: () { _gs.reset(); GameAudio.startBackgroundMusic(); },
                    child: Opacity(
                      opacity: blink,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 38, vertical: 15),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: _gs.lastLevel > 1 ? _cGold : _cAccent,
                            width: 1.6,
                          ),
                          color: (_gs.lastLevel > 1 ? _cGold : _cAccent).withOpacity(0.10),
                          boxShadow: [BoxShadow(
                            color: (_gs.lastLevel > 1 ? _cGold : _cAccent).withOpacity(0.22 + pulse * 0.18),
                            blurRadius: 24 + pulse * 18,
                            spreadRadius: 2,
                          )],
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                            _gs.lastLevel > 1 ? Icons.restart_alt_rounded : Icons.play_arrow_rounded,
                            color: _gs.lastLevel > 1 ? _cGold : _cAccent,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _gs.lastLevel > 1 ? 'NEW  GAME' : 'TAP  TO  LAUNCH',
                            style: TextStyle(
                              color: _gs.lastLevel > 1 ? _cGold : _cAccent,
                              fontSize: 16,
                              letterSpacing: 3.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ]),

                const SizedBox(height: 34),

                // ── Controls card — glass morphism ─────────────────
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 28),
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.09)),
                    boxShadow: [BoxShadow(
                      color: _cAccent.withOpacity(0.05),
                      blurRadius: 20, spreadRadius: 2,
                    )],
                  ),
                  child: Column(children: [
                    // Card header
                    Row(children: [
                      const Icon(Icons.gamepad_rounded, color: _cAccent, size: 14),
                      const SizedBox(width: 6),
                      const Text('HOW TO PLAY',
                        style: TextStyle(color: _cAccent, fontSize: 10,
                          fontWeight: FontWeight.w800, letterSpacing: 2)),
                    ]),
                    const SizedBox(height: 10),
                    const Divider(color: Colors.white12, height: 1),
                    const SizedBox(height: 10),
                    const _Hint('DRAG',  'Move your ship anywhere'),
                    const SizedBox(height: 7),
                    const _Hint('AUTO',  'Ship fires continuously'),
                    const SizedBox(height: 7),
                    const _Hint('TAP',   'Detonate bomb (clears wave)'),
                    const SizedBox(height: 7),
                    const _Hint('STORE', '→ sidebar: 5 upgrades (5⭐ each)'),
                    const SizedBox(height: 7),
                    const _Hint('GUN',   'Reload gun → 4/5/6 bullet spread'),
                  ]),
                ),

                const SizedBox(height: 24),

                // ── Stats section ──────────────────────────────────
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 28),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _cGold.withOpacity(0.25)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _statCell(Icons.emoji_events_rounded, _cGold,
                        'BEST SCORE', _gs.hi > 0
                          ? _gs.hi.toString().padLeft(7, '0')
                          : '-------'),
                      Container(width: 1, height: 36, color: Colors.white12),
                      _statCell(Icons.military_tech_rounded, _cPurple,
                        'LEVEL BEST',
                        _gs.maxLevel > 1 ? 'LV  ${_gs.maxLevel}' : 'LV  1'),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // ── Version + back ─────────────────────────────────
                Text('v4.0  SaaS Edition',
                  style: TextStyle(color: Colors.white.withOpacity(0.25),
                    fontSize: 10, letterSpacing: 2)),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: _exit,
                  icon: const Icon(Icons.arrow_back_ios_rounded,
                    color: _cAccent, size: 13),
                  label: const Text('Back to ChatXAP',
                    style: TextStyle(color: _cAccent, fontSize: 13,
                      letterSpacing: 0.5)),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _titleBadge(String text, Color col) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
    decoration: BoxDecoration(
      color: col.withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: col.withOpacity(0.38)),
    ),
    child: Text(text,
      style: TextStyle(color: col, fontSize: 10,
        fontWeight: FontWeight.w700, letterSpacing: 1.2)),
  );

  Widget _statCell(IconData icon, Color col, String label, String value) =>
    Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: col, size: 18),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(color: Colors.white.withOpacity(0.45),
        fontSize: 9, letterSpacing: 1.5)),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(color: col, fontSize: 15,
        fontWeight: FontWeight.w800, letterSpacing: 1.5,
        fontFamily: 'monospace')),
    ]);

  // ── PLAYING HUD ───────────────────────────────────────────────────────
  Widget _hudPlaying(BoxConstraints b){
    final dangerFlash=_gs.lives<=1&&((_gs.time*4).toInt()%2==0);
    return Stack(children:[

      // Top left: score + best
      Positioned(top:0,left:0,right:72,child:Container(
        padding:const EdgeInsets.fromLTRB(14,42,14,12),
        decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Colors.black.withOpacity(0.82),Colors.transparent])),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(_gs.score.toString().padLeft(7,'0'),style:const TextStyle(color:Colors.white,fontSize:24,fontWeight:FontWeight.w800,letterSpacing:2.8,fontFamily:'monospace')),
          if(_gs.hi>0)Text('BEST  ${_gs.hi.toString().padLeft(7,"0")}',style:const TextStyle(color:Color(0xFF4B5563),fontSize:10,letterSpacing:1.5)),
        ]))),

      // Top centre: lives + level badge
      Positioned(top:44,left:0,right:72,child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[
        // Lives
        ...List.generate(min(_gs.lives,10),(i)=>Icon(Icons.favorite_rounded,color:dangerFlash?const Color(0xFFFF1744):_cRed,size:16)),
        ...List.generate(max(0,3-_gs.lives),(i)=>const Icon(Icons.favorite_border_rounded,color:Color(0xFF374151),size:16)),
        const SizedBox(width:8),
        Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:3),
          decoration:BoxDecoration(color:_cAccent.withOpacity(0.18),borderRadius:BorderRadius.circular(7),border:Border.all(color:_cAccent.withOpacity(0.42))),
          child:Text('LV  ${_gs.level}',style:const TextStyle(color:_cAccent,fontSize:11,fontWeight:FontWeight.w800,letterSpacing:0.5))),
        const SizedBox(width:6),
        GestureDetector(onTap:(){GameAudio.toggleMute();_frame.value++;},child:Icon(GameAudio.isMuted?Icons.volume_off_rounded:Icons.volume_up_rounded,color:Colors.white54,size:20)),
      ])),

      // Pause button
      Positioned(top:40,left:10,child:GestureDetector(
        onTap:(){_gs.phase=GamePhase.paused;GameAudio.pauseBackgroundMusic();},
        child:Container(padding:const EdgeInsets.all(8),decoration:BoxDecoration(color:Colors.black.withOpacity(0.45),borderRadius:BorderRadius.circular(10)),child:const Icon(Icons.pause_rounded,color:Colors.white60,size:18)))),

      // Bombs indicator (bottom left)
      if(_gs.bombs>0) Positioned(bottom:18,left:14,child:Container(
        padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),
        decoration:BoxDecoration(color:const Color(0xFFFF9F43).withOpacity(0.18),borderRadius:BorderRadius.circular(20),border:Border.all(color:const Color(0xFFFF9F43).withOpacity(0.55))),
        child:Text('💣 ×${_gs.bombs}  TAP',style:const TextStyle(color:Color(0xFFFF9F43),fontSize:12,fontWeight:FontWeight.w700,letterSpacing:1)))),

      // Active power-ups (bottom centre)
      Positioned(bottom:18,left:0,right:0,child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[
        if(_gs.shield)    _puChip('🛡','SHIELD', _gs.shieldT/_kShieldDur,_cCyan),
        if(_gs.speedBoost)_puChip('⚡','SPEED',  _gs.speedT/_kSpeedDur,  _cCyan),
        if(_gs.gunLevel>1)_puChip('🔫','GUN LV${_gs.gunLevel}',_gs.gunT/_kGunDur,_cGold),
      ])),

      // Combo strip
      if(_gs.combo>=3) Positioned(top:104,left:0,right:72,child:Center(child:Container(
        padding:const EdgeInsets.symmetric(horizontal:12,vertical:4),
        decoration:BoxDecoration(color:Colors.black.withOpacity(0.62),borderRadius:BorderRadius.circular(20),border:Border.all(color:_cGold.withOpacity(0.65))),
        child:Text('×${_gs.combo>=10?5:_gs.combo>=6?3:2}  COMBO  ×${_gs.combo}',style:const TextStyle(color:_cGold,fontSize:11,fontWeight:FontWeight.w700,letterSpacing:2))))),

      // Level-up overlay (NO FREEZE — game keeps running)
      if(_gs.levelUpOverlay>0) Positioned.fill(child:IgnorePointer(child:Center(child:Opacity(
        opacity:(sin(_gs.levelUpOverlay/_kShakeDur*3)*0.5+0.5).clamp(0.0,1.0).toDouble(),
        child:Column(mainAxisSize:MainAxisSize.min,children:[
          ShaderMask(shaderCallback:(b)=>const LinearGradient(colors:[_cAccent,_cCyan]).createShader(b),
            child:Text('LEVEL  ${_gs.level}',style:const TextStyle(fontSize:58,fontWeight:FontWeight.w900,letterSpacing:5,color:Colors.white))),
          const SizedBox(height:6),
          Text(_gs.level%5==0?'⚠  BOSS  WAVE!':'WAVE INCOMING!',style:TextStyle(color:Colors.white.withOpacity(0.76),fontSize:13,letterSpacing:2.5)),
        ]))))),

      // Boss warn overlay
      if(_gs.bossWarnOverlay>0) Positioned.fill(child:IgnorePointer(child:Container(
        color:Colors.black.withOpacity(0.55),
        child:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
          const Text('⚠  BOSS  INCOMING  ⚠',style:TextStyle(color:_cRed,fontSize:26,fontWeight:FontWeight.w900,letterSpacing:4)),
          const SizedBox(height:10),
          Text('LEVEL ${_gs.level}  BOSS  WAVE',style:TextStyle(color:Colors.white.withOpacity(0.72),fontSize:13,letterSpacing:3)),
        ]))))),

      // Reload failure message
      if(_gs.reloadMsgT>0) Positioned(top:160,right:60,child:Opacity(
        opacity:_gs.reloadMsgT.clamp(0.0,1.0),
        child:Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
          decoration:BoxDecoration(color:_cRed.withOpacity(0.9),borderRadius:BorderRadius.circular(8)),
          child:Text(_gs.reloadMsg,style:const TextStyle(color:Colors.white,fontSize:10,fontWeight:FontWeight.w700))))),

      // ══ RELOAD SIDEBAR (top right) ══
      Positioned(top:36,right:5,child:Column(children:[
        _SideBtn(emoji:'❤️',label:'LIFE', cost:_kReloadCost, active:false, progress:0,
          canAfford:_gs.canAffordReload, onTap:(){_logic.reloadLife();_frame.value++;},
          extraLabel:'+$_kLifeAmt'),
        _SideBtn(emoji:'💣',label:'BOMB', cost:_kReloadCost, active:false, progress:0,
          canAfford:_gs.canAffordReload, onTap:(){_logic.reloadBomb();_frame.value++;},
          extraLabel:'+3'),
        _SideBtn(emoji:'🔫',label:'GUN',  cost:_kReloadCost,
          active:_gs.gunLevel>1, progress:_gs.gunT/_kGunDur,
          canAfford:_gs.canAffordReload, onTap:(){_logic.reloadGun();_frame.value++;},
          extraLabel:'LV${_gs.gunLevel}'),
        _SideBtn(emoji:'⚡',label:'SPEED',cost:_kReloadCost,
          active:_gs.speedBoost, progress:_gs.speedT/_kSpeedDur,
          canAfford:_gs.canAffordReload, onTap:(){_logic.reloadSpeed();_frame.value++;},
          extraLabel:'30s'),
        _SideBtn(emoji:'🛡',label:'SHLD', cost:_kReloadCost,
          active:_gs.shield, progress:_gs.shieldT/_kShieldDur,
          canAfford:_gs.canAffordReload, onTap:(){_logic.reloadShield();_frame.value++;},
          extraLabel:'30s'),
      ])),
    ]);
  }

  Widget _puChip(String icon,String lbl,double t,Color col)=>Container(
    margin:const EdgeInsets.symmetric(horizontal:4),
    padding:const EdgeInsets.symmetric(horizontal:10,vertical:4),
    decoration:BoxDecoration(color:col.withOpacity(0.14),borderRadius:BorderRadius.circular(20),border:Border.all(color:col.withOpacity(0.42))),
    child:Row(mainAxisSize:MainAxisSize.min,children:[
      Text(icon,style:const TextStyle(fontSize:11)),const SizedBox(width:4),
      Text(lbl,style:TextStyle(color:col,fontSize:10,fontWeight:FontWeight.w700,letterSpacing:1)),
      const SizedBox(width:6),
      SizedBox(width:26,height:3,child:ClipRRect(borderRadius:BorderRadius.circular(2),child:LinearProgressIndicator(value:t.clamp(0.0,1.0),backgroundColor:col.withOpacity(0.18),valueColor:AlwaysStoppedAnimation<Color>(col)))),
    ]));

  // ── GAME OVER ─────────────────────────────────────────────────────────
  Widget _hudGameOver(){
    final newHS=_gs.score>0&&_gs.score>=_gs.hi;
    return SizedBox.expand(child:Container(color:Colors.black.withOpacity(0.84),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
      const Text('GAME  OVER',style:TextStyle(color:_cRed,fontSize:46,fontWeight:FontWeight.w900,letterSpacing:6)),
      const SizedBox(height:30),
      Container(margin:const EdgeInsets.symmetric(horizontal:36),padding:const EdgeInsets.symmetric(horizontal:30,vertical:22),
        decoration:BoxDecoration(color:Colors.white.withOpacity(0.05),borderRadius:BorderRadius.circular(22),border:Border.all(color:Colors.white.withOpacity(0.09))),
        child:Column(children:[
          Text(_gs.score.toString().padLeft(7,'0'),style:const TextStyle(color:Colors.white,fontSize:46,fontWeight:FontWeight.w900,letterSpacing:4,fontFamily:'monospace')),
          const SizedBox(height:2),
          const Text('SCORE',style:TextStyle(color:Color(0xFF6B7280),fontSize:11,letterSpacing:4)),
          if(newHS)...[const SizedBox(height:10),Container(padding:const EdgeInsets.symmetric(horizontal:14,vertical:5),decoration:BoxDecoration(color:_cGold.withOpacity(0.16),borderRadius:BorderRadius.circular(20),border:Border.all(color:_cGold.withOpacity(0.5))),child:const Row(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.emoji_events_rounded,color:_cGold,size:15),SizedBox(width:6),Text('NEW HIGH SCORE!',style:TextStyle(color:_cGold,fontSize:13,fontWeight:FontWeight.w800,letterSpacing:2))]))],
          const SizedBox(height:18),
          _sRow('LEVEL REACHED','${_gs.level}'),const SizedBox(height:4),
          _sRow('HIGH SCORE',_gs.hi.toString().padLeft(7,'0')),
        ])),
      const SizedBox(height:30),
      // ── Play Again (restart from level 1) ─────────────────────────
      GestureDetector(onTap:(){_gs.reset();GameAudio.startBackgroundMusic();},child:Container(
        padding:const EdgeInsets.symmetric(horizontal:52,vertical:15),
        decoration:BoxDecoration(color:_cAccent,borderRadius:BorderRadius.circular(32),boxShadow:[BoxShadow(color:_cAccent.withOpacity(0.50),blurRadius:26,spreadRadius:2)]),
        child:const Text('NEW  GAME',style:TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w900,letterSpacing:3.5)))),
      const SizedBox(height:12),
      // ── Continue from last level ───────────────────────────────────
      if(_gs.lastLevel>1)
        GestureDetector(
          onTap:(){_gs.continueGame();GameAudio.startBackgroundMusic();},
          child:Container(
            padding:const EdgeInsets.symmetric(horizontal:38,vertical:13),
            decoration:BoxDecoration(
              color:Colors.transparent,
              borderRadius:BorderRadius.circular(32),
              border:Border.all(color:_cGold,width:1.8),
              boxShadow:[BoxShadow(color:_cGold.withOpacity(0.25),blurRadius:18,spreadRadius:1)],
            ),
            child:Row(mainAxisSize:MainAxisSize.min,children:[
              const Icon(Icons.play_circle_outline_rounded,color:_cGold,size:18),
              const SizedBox(width:8),
              Text('CONTINUE  LV ${_gs.lastLevel}',style:const TextStyle(color:_cGold,fontSize:14,fontWeight:FontWeight.w800,letterSpacing:2.5)),
            ]),
          ),
        ),
      if(_gs.lastLevel>1) const SizedBox(height:12),
      const SizedBox(height:2),
      TextButton.icon(onPressed:_exit,icon:const Icon(Icons.arrow_back_ios_rounded,color:_cAccent,size:14),label:const Text('Back to ChatXAP',style:TextStyle(color:_cAccent,fontSize:13))),
    ])));
  }

  Widget _sRow(String lbl,String val)=>Padding(padding:const EdgeInsets.symmetric(vertical:1),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,mainAxisSize:MainAxisSize.min,children:[
    Text(lbl,style:const TextStyle(color:Color(0xFF9CA3AF),fontSize:12,letterSpacing:1)),const SizedBox(width:28),
    Text(val,style:const TextStyle(color:Colors.white,fontSize:12,fontWeight:FontWeight.w800,fontFamily:'monospace')),
  ]));

  // ── PAUSED ────────────────────────────────────────────────────────────
  Widget _hudPaused()=>SizedBox.expand(child:Container(color:Colors.black.withOpacity(0.82),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
    const Icon(Icons.pause_circle_filled_rounded,color:_cAccent,size:80),const SizedBox(height:20),
    const Text('PAUSED',style:TextStyle(color:Colors.white,fontSize:42,fontWeight:FontWeight.w900,letterSpacing:5)),const SizedBox(height:12),
    Text('Tap anywhere to resume',style:TextStyle(color:Colors.white.withOpacity(0.55),fontSize:14,letterSpacing:1.5)),const SizedBox(height:36),
    TextButton.icon(onPressed:_exit,icon:const Icon(Icons.arrow_back_ios_rounded,color:_cAccent,size:14),label:const Text('Back to ChatXAP',style:TextStyle(color:_cAccent,fontSize:13))),
  ])));
}

// ══════════════════════════════════════════════════════════════════════
//  RELOAD SIDEBAR BUTTON
// ══════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════
//  TITLE SCREEN PAINTERS
// ══════════════════════════════════════════════════════════════════════

/// Draws the rotating purple planet with ring on the title screen.
class _TitlePlanetPainter extends CustomPainter {
  final double t;
  _TitlePlanetPainter(this.t);

  @override
  void paint(Canvas c, Size sz) {
    final cx = sz.width * 0.60;
    final cy = sz.height * 0.42;
    final r  = sz.width  * 0.40;

    // Outer atmospheric glow
    c.drawCircle(Offset(cx, cy), r * 1.55,
      Paint()
        ..color = const Color(0xFF4A148C).withOpacity(0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28));

    // Ring — back half (behind planet)
    final ringRect = Rect.fromCenter(
      center: Offset(cx, cy), width: r * 2.95, height: r * 0.54);
    c.drawOval(ringRect,
      Paint()
        ..color = const Color(0xFF7B1FA2).withOpacity(0.52)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10);
    c.drawOval(ringRect,
      Paint()
        ..color = const Color(0xFF9C27B0).withOpacity(0.20)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22);

    // Planet body with animated shimmer
    final shimmer = sin(t * 0.6) * 0.08;
    c.drawCircle(Offset(cx, cy), r,
      Paint()..shader = RadialGradient(
        center: const Alignment(-0.32, -0.42),
        colors: [
          Color.lerp(const Color(0xFF9C27B0), Colors.white, 0.18 + shimmer)!,
          const Color(0xFF6A1B9A),
          const Color(0xFF2A0050),
          Colors.black,
        ],
        stops: const [0.0, 0.40, 0.70, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)));

    // Surface bands
    for (var i = 0; i < 3; i++) {
      final bandY = cy - r * 0.3 + i * r * 0.28;
      final bandW = r * (0.9 - i * 0.12);
      c.save();
      c.clipPath(Path()..addOval(
        Rect.fromCircle(center: Offset(cx, cy), radius: r - 1)));
      c.drawRect(Rect.fromCenter(center: Offset(cx, bandY), width: bandW * 2, height: r * 0.06),
        Paint()..color = const Color(0xFF7B1FA2).withOpacity(0.22));
      c.restore();
    }

    // Highlight glare
    c.drawCircle(Offset(cx - r * 0.28, cy - r * 0.32), r * 0.20,
      Paint()..color = Colors.white.withOpacity(0.13));
    c.drawCircle(Offset(cx - r * 0.22, cy - r * 0.26), r * 0.08,
      Paint()..color = Colors.white.withOpacity(0.22));

    // Ring — front half (in front of planet, clip to top half)
    c.save();
    c.clipRect(Rect.fromLTWH(0, 0, sz.width, cy));
    c.drawOval(ringRect,
      Paint()
        ..color = const Color(0xFFBA68C8).withOpacity(0.70)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7);
    c.restore();

    // Ring inner glow line
    c.save();
    c.clipRect(Rect.fromLTWH(0, 0, sz.width, cy));
    c.drawOval(ringRect,
      Paint()
        ..color = Colors.white.withOpacity(0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    c.restore();
  }

  @override
  bool shouldRepaint(_TitlePlanetPainter old) => old.t != t;
}

/// Draws animated shooting stars that streak across the title screen.
class _ShootingStarPainter extends CustomPainter {
  final double t;
  static const _seeds = [17, 31, 53, 71, 97];

  _ShootingStarPainter(this.t);

  @override
  void paint(Canvas c, Size sz) {
    final rng = Random(0);
    for (var i = 0; i < 4; i++) {
      // Each star has its own offset phase so they stagger
      final phase = ((t * 0.22 + i * 0.38) % 1.0);
      // Only visible during first 18% of cycle — fast streak
      if (phase > 0.18) continue;
      final progress = phase / 0.18;           // 0→1 within streak window
      final alpha    = sin(progress * pi);      // fade in + out

      // Deterministic start position per star
      final rng2 = Random(_seeds[i % _seeds.length]);
      final startX = rng2.nextDouble() * sz.width  * 0.55 + sz.width  * 0.05;
      final startY = rng2.nextDouble() * sz.height * 0.35 + sz.height * 0.04;
      final length = 70.0 + rng2.nextDouble() * 90;
      const angle  = 0.48; // ~28° from horizontal

      final dx = cos(angle) * length;
      final dy = sin(angle) * length;

      // Trail: tail is shorter and more transparent
      final tailX = startX + progress * sz.width * 0.35;
      final tailY = startY + progress * sz.height * 0.22;

      c.drawLine(
        Offset(tailX, tailY),
        Offset(tailX + dx, tailY + dy),
        Paint()
          ..color = Colors.white.withOpacity(alpha * 0.80)
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );

      // Bright head dot
      c.drawCircle(Offset(tailX + dx, tailY + dy), 1.8,
        Paint()..color = Colors.white.withOpacity(alpha));
    }
    rng.nextInt(1); // suppress unused warning
  }

  @override
  bool shouldRepaint(_ShootingStarPainter old) => old.t != t;
}

class _SideBtn extends StatelessWidget {
  final String emoji, label, extraLabel;
  final int cost;
  final bool active, canAfford;
  final double progress;
  final VoidCallback onTap;

  const _SideBtn({
    required this.emoji, required this.label, required this.cost,
    required this.active, required this.progress, required this.canAfford,
    required this.onTap, this.extraLabel='',
  });

  @override
  Widget build(BuildContext context){
    final glow = active ? _cGold : (canAfford ? Colors.white24 : Colors.white10);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52, height: 64,
        margin: const EdgeInsets.only(bottom: 5),
        decoration: BoxDecoration(
          color: active ? Colors.black.withOpacity(0.78) : Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: glow, width: active ? 1.6 : 1.0),
          boxShadow: active ? [BoxShadow(color: _cGold.withOpacity(0.3), blurRadius: 8, spreadRadius: 1)] : null,
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          // Icon + progress ring
          SizedBox(width: 34, height: 34, child: Stack(alignment: Alignment.center, children: [
            if (active)
              SizedBox.expand(child: CircularProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: Colors.white12,
                color: _cGold,
                strokeWidth: 2.5,
              )),
            Text(emoji, style: TextStyle(fontSize: 17, color: canAfford ? Colors.white : Colors.white38)),
          ])),
          const SizedBox(height: 1),
          Text(label, style: TextStyle(color: canAfford ? Colors.white70 : Colors.white24, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('$cost⭐', style: TextStyle(color: canAfford ? _cGold : Colors.white24, fontSize: 8, fontWeight: FontWeight.w700)),
            if (extraLabel.isNotEmpty) ...[const SizedBox(width:2), Text(extraLabel, style: TextStyle(color: active ? _cCyan : Colors.white38, fontSize: 7))],
          ]),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  HELPER
// ══════════════════════════════════════════════════════════════════════
class _Hint extends StatelessWidget {
  final String label, hint;
  const _Hint(this.label, this.hint);
  @override
  Widget build(BuildContext ctx)=>Row(children:[
    Container(padding:const EdgeInsets.symmetric(horizontal:7,vertical:2),decoration:BoxDecoration(color:_cAccent.withOpacity(0.18),borderRadius:BorderRadius.circular(4)),child:Text(label,style:const TextStyle(color:_cAccent,fontSize:10,fontWeight:FontWeight.w800,letterSpacing:1))),
    const SizedBox(width:12),
    Expanded(child:Text(hint,style:const TextStyle(color:Color(0xFFD1D5DB),fontSize:11))),
  ]);
}
