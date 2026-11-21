import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Netflix-style rail physics: a fling carries momentum naturally, then settles
/// perfectly on a poster boundary. A card can never stop half-cut at the edge.
///
/// To make the scroll feel incredibly premium and organic:
///  1. We project where the scroll would naturally stop on its own using a
///     standard FrictionSimulation (no artificial speed limits or heavy caps).
///  2. We align that target directly to the nearest multiple of [itemExtent].
///  3. We animate seamlessly from the release velocity to the aligned target using
///     a well-tuned, critically-damped spring. This eliminates the "double-stopping"
///     or lurching sensation entirely.
class PosterSnapPhysics extends ScrollPhysics {
  const PosterSnapPhysics({required this.itemExtent, super.parent});

  /// Poster width + gap (the rail's repeating stride, and the snap unit).
  final double itemExtent;

  @override
  PosterSnapPhysics applyTo(ScrollPhysics? ancestor) =>
      PosterSnapPhysics(itemExtent: itemExtent, parent: buildParent(ancestor));

  /// Critically damped spring (stiffness 180.0, damping 26.8):
  /// matches the user's release velocity and settles cleanly in ~220ms
  /// with zero overshoot or corrective bounce-back.
  @override
  SpringDescription get spring => const SpringDescription(
        mass: 1.0,
        stiffness: 180.0,
        damping: 26.8,
      );

  double _targetPixels(ScrollMetrics position, Tolerance tolerance, double velocity) {
    if (itemExtent <= 0) return position.pixels;
    final double current = position.pixels / itemExtent;

    // Released at rest (or barely moving): snap to the nearest poster.
    if (velocity.abs() < tolerance.velocity) {
      return (current.roundToDouble() * itemExtent)
          .clamp(position.minScrollExtent, position.maxScrollExtent);
    }

    // Project where the scroll would stop naturally under standard friction.
    final sim = FrictionSimulation(0.015, position.pixels, velocity);
    final naturalTarget = sim.finalX;

    double targetPage = (naturalTarget / itemExtent).roundToDouble();

    // Never snap backwards against a directional swipe/flick on wider cards
    // (such as 184px tall cards or 313px landscape cards).
    if (velocity > tolerance.velocity && targetPage * itemExtent <= position.pixels) {
      targetPage = current.ceilToDouble();
    } else if (velocity < -tolerance.velocity && targetPage * itemExtent >= position.pixels) {
      targetPage = current.floorToDouble();
    }

    final double alignedTarget = targetPage * itemExtent;
    return alignedTarget.clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    // Overscroll/bounds are left to the parent physics (e.g. Clamping/Bouncing).
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }

    final tolerance = toleranceFor(position);
    final target = _targetPixels(position, tolerance, velocity);
    if ((target - position.pixels).abs() < tolerance.distance) return null;

    return ScrollSpringSimulation(spring, position.pixels, target, velocity, tolerance: tolerance);
  }

  @override
  bool get allowImplicitScrolling => false;
}
