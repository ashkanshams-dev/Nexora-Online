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
  static const double captureR = 44;

  /// Owner physics contract mapped to board units.
  static const double coinR = 35; // BR
  static const double strikerR = 58.5; // PR
  static const double coinMass = 4;
  static const double strikerMass = 2.6;

  static const double dt = 1 / 120;
  static const double drag = .175; // ball traction
  static const double stopSpeed = 8.0;
  static const double ePiece = .72;
  static const double eStrikerPiece = .78;
  static const double eWall = .93;
  static const double shotPowerCoefficient = 2.5;
  static const double maxShotSpeed = 520;
  static const double maxPullLength = 175;
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
  static const double maxPull = maxPullLength;

  /// Body ids: 0 striker, 1..9 white (seat 0), 10..18 black (seat 1), 19 queen.
  static const int strikerId = 0;
  static const int queenId = 19;
  static const int bodyCount = 20;
}
