/// Carrom deterministic configuration.
///
/// Logical units are the pixels of the NX black-gold board artwork (1024 x 1024), measured
/// with PIL (see docs in carrom_physics.dart). MUST match test/games/tools/carrom_ref.mjs.
class CrConfig {
  static const double boardSize = 1024;

  // Inner playfield (cushion inner edges).
  static const double left = 75;
  static const double top = 67;
  static const double right = 949;
  static const double bottom = 916;
  static const double centerX = 512;
  static const double centerY = 491.5;

  // Pockets (centres of the black holes in the art; visual radius 54).
  static const List<List<double>> pockets = <List<double>>[
    <double>[91.5, 88],
    <double>[932.5, 88],
    <double>[91.5, 895],
    <double>[932.5, 895],
  ];
  static const double pocketR = 54;

  /// A piece falls when its centre comes within this distance of a pocket centre.
  static const double captureR = 42;

  /// Real proportions (ICF): playing surface 74 cm = 874 units (11.81 units/cm).
  /// Coin Ø 3.18 cm -> r 18.8; striker Ø 4.13 cm -> r 24.4. Mass: coin 5.5 g, striker 15 g.
  static const double unitsPerCm = 874 / 74;
  static const double coinR = 18.8;
  static const double strikerR = 24.4;
  static const double coinMass = 1.0;
  static const double strikerMass = 2.7;

  static const double dt = 1 / 120;

  /// Powdered-board sliding friction (constant deceleration, units/s^2 ~ 1.0 m/s^2)
  /// plus a small linear drag (1/s).
  static const double friction = 1200;
  static const double drag = 0.4;
  static const double stopSpeed = 8.0;
  static const double ePiece = 0.90;
  static const double eWall = 0.72;

  /// ~3.6 m/s: a hard break. Per-step travel (35 u) stays below a coin diameter.
  static const double maxShotSpeed = 4200;
  static const int maxSteps = 1200; // 10 s

  // Baselines (striker centre line) for seat 0 (bottom) and seat 1 (top).
  static const double baseline0 = 797;
  static const double baseline1 = 186;
  static const double baseMinX = 248;
  static const double baseMaxX = 776;

  static const int coinsPerSide = 9;
  static const int queenBonus = 3;
  static const int maxTurns = 160;
  /// Must match the server-authoritative online turn deadline.
  static const double turnSeconds = 10;

  /// UI only (not part of the deterministic contract).
  static const double maxPull = 210;

  /// Body ids: 0 striker, 1..9 white (seat 0), 10..18 black (seat 1), 19 queen.
  static const int strikerId = 0;
  static const int queenId = 19;
  static const int bodyCount = 20;
}
