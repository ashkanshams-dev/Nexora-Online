import 'package:flame/components.dart';
import 'package:flame/game.dart';

/// Flame runtime used by NEXORA board games. Deterministic rules remain in the
/// pure-Dart engines; this game owns the frame lifecycle and is mounted in the
/// real game widget, so rendering/input can be migrated component-by-component.
class NexoraPhysicsFlameGame extends FlameGame {
  NexoraPhysicsFlameGame(this.gameId);

  final String gameId;
  late final NexoraFrameComponent frame;

  @override
  Future<void> onLoad() async {
    frame = NexoraFrameComponent(gameId);
    await add(frame);
  }
}

/// A lightweight Flame component deliberately kept visual-neutral: the existing
/// painters remain the authoritative presentation while Flame owns update timing.
/// This avoids a second physics clock and preserves replay/server determinism.
class NexoraFrameComponent extends Component {
  NexoraFrameComponent(this.gameId);

  final String gameId;
  double elapsed = 0;

  @override
  void update(double dt) {
    elapsed += dt;
  }
}

class BermudaFlameGame extends NexoraPhysicsFlameGame {
  BermudaFlameGame() : super('finger_soccer');
}

class BilliardsFlameGame extends NexoraPhysicsFlameGame {
  BilliardsFlameGame() : super('billiards');
}

class CarromFlameGame extends NexoraPhysicsFlameGame {
  CarromFlameGame() : super('carrom');
}
