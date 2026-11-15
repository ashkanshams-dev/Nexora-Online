// NEXORA physics constants for the default 'stars' profile, all in pitch-width units.
//
// W = 825 world px = the inner pitch width between the cushions (v0.7 play area fitted to the pitch art's drawn field
// edges). Cross-check: the v0.6.2 puck (r 49 px) and ball (r 21.6 px) measure 98/825 = 0.119 W and 43.2/825 = 0.052 W,
// matching the owner's "current 0.118 / 0.050".
//
// speeds W/s, accelerations W/s^2, friction rates 1/s, lengths W. Change a value here and kTuneStars follows.
// Confidence tags: [measured] from the reference video (+-30%), [guess] owner's starting guess, [kept] unchanged
// v0.6.2 value converted to W.

class PhysicsConfig {
  /// world px per W (the engine itself runs in world px; every value below is multiplied by this).
  final double wPx;

  // ---- sizes (collision radius == drawn radius) ----
  final double puckDiameter, ballDiameter;

  // ---- exponential friction v *= exp(-k dt) ----
  final double ballK, puckK;

  /// friction of a flicked puck until its first contact (puck, ball, post or cushion). The reference puck runs at an
  /// almost constant speed until it hits something, then stops with puckK.
  final double puckFlightK;

  /// v0.7b: flight friction blends linearly from puckFlightK (at or above puckFlightFull W/s) to puckK (at
  /// puckFlightMin W/s); flight ends below puckFlightMin. Without the blend a flick just above the old 1 W/s cut-off
  /// glided twice as far as one just below it (pull -> distance had a 6x kink): imprecise aiming.
  final double puckFlightMin, puckFlightFull;

  /// below this speed a body stops dead (W/s).
  final double stopSpeed;

  // ---- masses: only the ratio matters ----
  final double massPuck, massBall;

  // ---- restitution (normal) and tangential keep factor ----
  final double eBallPuck, ePuckPuck, eBallWall, ePuckWall;
  final double tBallWall, tPuckWall;

  // ---- shot / kick ----
  /// full-pull launch speed (W/s) before the power stat; launch speed = shotMax * shotCurve(pull) * statMul(power).
  final double shotMax;

  /// pull -> speed curve: shotCurve(q) = shotMinFrac + (1 - shotMinFrac) * q^shotExp (q = pull / max pull, 0..1).
  final double shotMinFrac, shotExp;

  /// a puck that ends up inside a goal net is walked back out at most at puckEjectSpeed (W/s), accelerating at
  /// puckEjectAccel (W/s^2). v0.7b: was a velocity forced every substep (an infinitely heavy bulldozer that shoved the
  /// ball and other pucks around and re-collided every substep).
  final double puckEjectSpeed, puckEjectAccel;

  /// a puck striking a ball sends it off at kickGain x the closing speed: a reference flick (puckShotRef) gives
  /// ballKickSpeed. Momentum is not conserved here on purpose (a flick is a striker, not a free body).
  final double ballKickSpeed, puckShotRef;

  /// hard cap on ball speed (reference peak) and numerical safety cap on any body.
  final double ballMaxSpeed, maxSpeed;

  /// goal posts: collision radius == drawn radius (W)
  final double postR;

  /// v0.7b goal mouth width (post centre to post centre) and net depth behind the goal line (W)
  final double goalWidth, goalDepth;

  // ---- integration ----
  /// fixed physics step (s); each step is split into substeps so that no body travels more than subTravel and the
  /// ball never more than subBallFrac x its radius per substep.
  final double fixedStep, subTravel, subBallFrac;

  /// playback speed of the whole simulation (1 = original pace). Slows the match like playing a fast-forwarded film
  /// at normal speed: identical paths/collisions (fixed steps), only wall-clock pace changes. Owner 2026-11-15.
  final double playbackSpeed;

  /// disc stats 1..10 really applied to every shot (owner 2026-11-15):
  /// launch speed x (powerMulAt1 + (1 - powerMulAt1) * (power - 1) / 9)  -> power 1 = 0.55x, power 10 = 1.0x
  /// aim deviation = (10 - accuracy) / 9 * accDevAt1Deg degrees          -> accuracy 10 = exact, accuracy 1 = 8 deg
  final bool useDiscStats;
  final double powerMulAt1, accDevAt1Deg;

  /// v0.7b: power also scales the striker kick: kick gain x (kickMulAt1 + (1 - kickMulAt1) * (power - 1) / 9)
  final double kickMulAt1;
  final int subMax, stepCap;

  const PhysicsConfig({
    required this.wPx,
    this.playbackSpeed = 1.0,
    this.useDiscStats = true,
    this.powerMulAt1 = .55,
    this.accDevAt1Deg = 8,
    this.kickMulAt1 = .8,
    required this.puckDiameter,
    required this.ballDiameter,
    required this.ballK,
    required this.puckK,
    required this.puckFlightK,
    required this.puckFlightMin,
    required this.puckFlightFull,
    required this.stopSpeed,
    required this.massPuck,
    required this.massBall,
    required this.eBallPuck,
    required this.ePuckPuck,
    required this.eBallWall,
    required this.ePuckWall,
    required this.tBallWall,
    required this.tPuckWall,
    required this.shotMax,
    this.shotMinFrac = .06,
    this.shotExp = 1.35,
    this.puckEjectSpeed = 270 * 1.27 / 825,
    this.puckEjectAccel = 4,
    required this.ballKickSpeed,
    required this.puckShotRef,
    required this.ballMaxSpeed,
    required this.maxSpeed,
    required this.postR,
    required this.goalWidth,
    required this.goalDepth,
    required this.fixedStep,
    required this.subTravel,
    required this.subBallFrac,
    required this.subMax,
    required this.stepCap,
  });

  double get kickGain => ballKickSpeed / puckShotRef;
}

// ignore: constant_identifier_names
const PHYSICS_CONFIG = PhysicsConfig(
  wPx: 825,
  puckDiameter: .134, // [measured] was .117 (98 px)
  ballDiameter: .058, // [measured] was .052 (43.2 px)
  ballK: 2.1, // [measured, medium] tau .48 s (spec 2026-11-15). Owner's earlier 'heavier' retune was 2.6
  puckK: 2.9, // [measured, LOW: one path] tau .34 s (spec 2026-11-15). Owner's 'heavier' retune was 3.6
  puckFlightK: .5, // [guess] 'almost constant speed until the first hit'. Owner's 'heavier' retune was 1.2
  puckFlightMin: .5, // [guess] v0.7b: lower knee of the flight blend (was a hard 1 W/s cut-off)
  puckFlightFull: 1.8, // [guess] v0.7b: full flight (near-constant speed) at and above this; reference flick ~2 W/s
  stopSpeed: .02, // [measured] was 2 px/s = .0024 W/s
  massPuck: 1, // [guess] ball 3x puck; was ball 1 : puck 4
  massBall: 3,
  eBallPuck: .5, // [guess, start point from spec; measured m ratio ~4, e .7..1 from ONE oblique hit] owner 'heavier' was .4
  ePuckPuck: .8, // [guess] spec default; owner 'heavier' was .55
  eBallWall: .8, // [guess] spec default; owner 'heavier' was .5
  ePuckWall: .6, // [guess] spec default; owner 'heavier' was .35
  tBallWall: .96, // [kept] v0.6.2 value; owner 'heavier' was .85
  tPuckWall: .97, // [kept] v0.6.2 value; owner 'heavier' was .85
  shotMax: 2.6, // [derived] v0.7b: = ballMaxSpeed / kickGain (6.5 / 2.5), so a full pull gives exactly the reference
  //            ball peak and every pull length still changes the kick. Was 3500/825 = 4.24 W/s: 2x the reference
  //            flick (~2 W/s) and above 2.6 W/s every kick hit the 6.5 cap (pull 60%..100% kicked the same).
  shotMinFrac: .06, // [kept] v0.6.1 shotCurve constant, moved here from engine.dart
  shotExp: 1.35, // [kept] v0.6.1 shotCurve constant, moved here from engine.dart
  puckEjectSpeed: 270 * 1.27 / 825, // [kept] 343 px/s = .416 W/s (gout walk-out speed)
  puckEjectAccel: 4, // [guess] v0.7b: reaches the walk-out speed in ~0.1 s
  ballKickSpeed: 5, // [guess, low] reference peak ~6.5, spec start 5. Owner 'heavier' was 3.8
  puckShotRef: 2, // [measured] reference flick ~2 W/s
  ballMaxSpeed: 6.5, // [measured, low] reference peak ball speed. Owner 'heavier' was 5
  maxSpeed: 7, // safety clamp; was 4200 px/s = 5.03 W/s
  postR: .009, // [visual] v0.7b: 7.4 px = the drawn post (render drew 7.2 px while collision used 5 px)
  goalWidth: .33, // [owner 2026-11-15: 'a bit wider'] was 248 px = .301 W (+10%)
  goalDepth: .125, // [owner 2026-11-15: 'deeper'] was 72 px = .087 W (+43%); a whole ball (.058 W) sits in it with room
  playbackSpeed: 1.0, // v0.7b: real time again (was .6 slow motion: on screen tau ball .80 s / puck .58 s, outside
  //                    acceptance 1-2). The calm pace now comes from shotMax 2.6 (on-screen flick speed ~= the old
  //                    4.24 x .6 = 2.54 W/s) instead of slowing every decay and bounce.
  useDiscStats: true, // owner: real 1..10 power/accuracy on every disc
  powerMulAt1: .55, // was .62 (statMul)
  accDevAt1Deg: 8, // was 4 (aimDevDeg)
  kickMulAt1: .8, // [guess] v0.7b: power 1 kicks with 80% of the gain (with powerMulAt1: full-pull ball 2.9 vs 6.5 W/s)
  fixedStep: 1 / 120, // was 1/240 (brief: 1/120 + substeps)
  subTravel: 4 / 825, // [kept] 4 px
  subBallFrac: .5, // spec: ball moves < half its radius per substep
  subMax: 24, // was 16 (1/120 step: 7 W/s needs 18 substeps of 4 px)
  stepCap: 14, // [kept]
);
