/// One normalized MediaPipe landmark in the upright, unmirrored input image.
///
/// Coordinates may extend outside 0..1 near the image edges. Do not clamp them
/// or mirror them to match a front-camera preview.
class HandLandmarkPoint {
  const HandLandmarkPoint({required this.x, required this.y, required this.z});

  final double x;
  final double y;
  final double z;
}

/// A fresh detector observation, including frames where no hand was found.
///
/// [timestampMs] must come from frame acquisition, not inference completion.
/// [width] and [height] describe the upright image used by MediaPipe.
class HandLandmarkFrame {
  HandLandmarkFrame({
    required this.timestampMs,
    required this.width,
    required this.height,
    required List<List<HandLandmarkPoint>> hands,
  }) : hands = List.unmodifiable(
         hands.map((hand) => List<HandLandmarkPoint>.unmodifiable(hand)),
       );

  final int timestampMs;
  final int width;
  final int height;
  final List<List<HandLandmarkPoint>> hands;
}
