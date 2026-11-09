import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

class CameraFrameCrops {
  const CameraFrameCrops({
    required this.context,
    required this.tight,
    required this.orientedLandmarks,
  });

  final img.Image context;
  final img.Image tight;
  final List<Offset> orientedLandmarks;
}

class ImagePreprocessor {
  const ImagePreprocessor._();

  // Landmark bounds are expanded by 30% and 20% per side. The small minimum
  // prevents a noisy, tiny detection from being enlarged into a false pose.
  static const _contextPaddingScale = 1.60;
  static const _tightPaddingScale = 1.40;
  static const _contextMinimumSideFraction = 0.28;
  static const _tightMinimumSideFraction = 0.22;
  static const _borderPoints = <Offset>[
    Offset(0, 0),
    Offset(0.5, 0),
    Offset(1, 0),
    Offset(0, 0.5),
    Offset(1, 0.5),
    Offset(0, 1),
    Offset(0.5, 1),
    Offset(1, 1),
  ];

  static int effectivePortraitRotation({
    required int frameWidth,
    required int frameHeight,
    required int requestedRotationDegrees,
  }) {
    final requested = ((requestedRotationDegrees % 360) + 360) % 360;
    if (frameWidth == frameHeight) return requested;
    final swapsDimensions = requested == 90 || requested == 270;
    final outputWidth = swapsDimensions ? frameHeight : frameWidth;
    final outputHeight = swapsDimensions ? frameWidth : frameHeight;
    if (outputHeight >= outputWidth) return requested;

    // Some CameraX/OEM combinations already deliver portrait-oriented buffers.
    return frameHeight > frameWidth ? 0 : requested;
  }

  static img.Image decodeFileBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Format gambar tidak dapat dibaca.');
    }
    return img.bakeOrientation(decoded);
  }

  static CameraFrameCrops cameraImageToGrayCrops(
    CameraImage cameraImage, {
    required int rotationDegrees,
    required bool mirrorHorizontally,
    required List<Offset> normalizedLandmarks,
  }) {
    // MediaPipe applies ImageProcessingOptions.rotationDegrees before it
    // returns normalized landmarks. Rotating these points again moves the crop
    // away from the hand. The front-camera mirror is the only remaining
    // transform needed to align landmarks with the model image below.
    final landmarks = orientNormalizedPoints(
      normalizedLandmarks,
      rotationDegrees: 0,
      mirrorHorizontally: mirrorHorizontally,
    );
    final bounds = _boundsForPoints(landmarks);
    if (cameraImage.format.group == ImageFormatGroup.yuv420 ||
        cameraImage.format.group == ImageFormatGroup.nv21) {
      final orientedSize = _orientedSize(
        cameraImage.width,
        cameraImage.height,
        rotationDegrees,
      );
      final contextBounds = _squareCropAroundBounds(
        orientedSize,
        bounds,
        paddingScale: _contextPaddingScale,
        minimumSideFraction: _contextMinimumSideFraction,
      );
      final tightBounds = _squareCropAroundBounds(
        orientedSize,
        bounds,
        paddingScale: _tightPaddingScale,
        minimumSideFraction: _tightMinimumSideFraction,
      );
      return CameraFrameCrops(
        context: _sampleLuminanceCrop(
          cameraImage,
          contextBounds,
          rotationDegrees: rotationDegrees,
          mirrorHorizontally: mirrorHorizontally,
        ),
        tight: _sampleLuminanceCrop(
          cameraImage,
          tightBounds,
          rotationDegrees: rotationDegrees,
          mirrorHorizontally: mirrorHorizontally,
        ),
        orientedLandmarks: landmarks,
      );
    }

    if (cameraImage.format.group != ImageFormatGroup.bgra8888) {
      throw UnsupportedError(
        'Format kamera ${cameraImage.format.group.name} belum didukung.',
      );
    }
    var oriented = _bgraImage(cameraImage);
    if (rotationDegrees != 0) {
      oriented = img.copyRotate(oriented, angle: rotationDegrees.toDouble());
    }
    if (mirrorHorizontally) oriented = img.flipHorizontal(oriented);
    return imageToGrayHandCrops(oriented, normalizedLandmarks: landmarks);
  }

  static CameraFrameCrops imageToGrayHandCrops(
    img.Image image, {
    required List<Offset> normalizedLandmarks,
  }) {
    if (normalizedLandmarks.length != 21) {
      throw ArgumentError('Crop tangan membutuhkan 21 landmark.');
    }
    final bounds = _boundsForPoints(normalizedLandmarks);
    return CameraFrameCrops(
      context: _sampleImageCrop(
        image,
        _squareCropAroundBounds(
          Size(image.width.toDouble(), image.height.toDouble()),
          bounds,
          paddingScale: _contextPaddingScale,
          minimumSideFraction: _contextMinimumSideFraction,
        ),
      ),
      tight: _sampleImageCrop(
        image,
        _squareCropAroundBounds(
          Size(image.width.toDouble(), image.height.toDouble()),
          bounds,
          paddingScale: _tightPaddingScale,
          minimumSideFraction: _tightMinimumSideFraction,
        ),
      ),
      orientedLandmarks: List<Offset>.unmodifiable(normalizedLandmarks),
    );
  }

  // Still images, BGRA and YUV share the same sampling grid and square ROI.
  // This also avoids rounding the crop to integer pixels only on the file path.
  static img.Image _sampleImageCrop(img.Image image, Rect crop) {
    final padding = _imageBorderLuminance(image).floor();
    return _sampleModelCrop(
      crop,
      luminanceAt: (x, y) {
        if (x < 0 || y < 0 || x >= image.width || y >= image.height) {
          return padding;
        }
        return _pixelLuminance(image, x.floor(), y.floor()).floor();
      },
    );
  }

  static img.Image _sampleModelCrop(
    Rect crop, {
    required int Function(double x, double y) luminanceAt,
  }) {
    const offsets = <double>[0.125, 0.375, 0.625, 0.875];
    final output = img.Image(width: 28, height: 28, numChannels: 1);
    for (var y = 0; y < 28; y++) {
      for (var x = 0; x < 28; x++) {
        var sum = 0;
        for (final sy in offsets) {
          for (final sx in offsets) {
            sum += luminanceAt(
              crop.left + (x + sx) * crop.width / 28,
              crop.top + (y + sy) * crop.height / 28,
            );
          }
        }
        output.setPixelR(x, y, sum ~/ 16);
      }
    }
    return output;
  }

  static List<Offset> orientNormalizedPoints(
    List<Offset> points, {
    required int rotationDegrees,
    required bool mirrorHorizontally,
  }) {
    final rotation = ((rotationDegrees % 360) + 360) % 360;
    if (rotation != 0 && rotation != 90 && rotation != 180 && rotation != 270) {
      throw ArgumentError.value(
        rotationDegrees,
        'rotationDegrees',
        'Rotasi harus kelipatan 90 derajat.',
      );
    }

    return List<Offset>.unmodifiable(
      points.map((point) {
        final rotated = switch (rotation) {
          90 => Offset(1 - point.dy, point.dx),
          180 => Offset(1 - point.dx, 1 - point.dy),
          270 => Offset(point.dy, 1 - point.dx),
          _ => point,
        };
        return mirrorHorizontally
            ? Offset(1 - rotated.dx, rotated.dy)
            : rotated;
      }),
    );
  }

  static img.Image cropAndOrientSensorImage(
    img.Image sensorGray, {
    required int rotationDegrees,
    required bool mirrorHorizontally,
    Rect? normalizedCrop,
  }) {
    // MediaPipe reports landmarks in sensor-frame coordinates. Crop before
    // rotating so the region stays aligned with the detected hand.
    final gray = normalizedCrop == null
        ? sensorGray
        : _cropAroundHand(sensorGray, normalizedCrop);
    var oriented = rotationDegrees == 0
        ? gray
        : img.copyRotate(gray, angle: rotationDegrees.toDouble());
    if (mirrorHorizontally) {
      oriented = img.flipHorizontal(oriented);
    }
    return oriented;
  }

  static List<List<List<List<double>>>> toModelInput(
    img.Image source, {
    double cropFraction = 1,
    Rect? normalizedCrop,
  }) {
    return modelImageToInput(
      toModelImage(
        source,
        cropFraction: cropFraction,
        normalizedCrop: normalizedCrop,
      ),
    );
  }

  static img.Image toModelImage(
    img.Image source, {
    double cropFraction = 1,
    Rect? normalizedCrop,
  }) {
    final cropped = normalizedCrop == null
        ? _centerCrop(source, cropFraction)
        : _cropAroundHand(source, normalizedCrop);
    return img.copyResize(
      cropped,
      width: 28,
      height: 28,
      interpolation: img.Interpolation.average,
    );
  }

  static List<List<List<List<double>>>> modelImageToInput(img.Image resized) {
    if (resized.width != 28 || resized.height != 28) {
      throw ArgumentError.value(
        '${resized.width}x${resized.height}',
        'resized',
        'Gambar input model harus berukuran 28x28.',
      );
    }
    return <List<List<List<double>>>>[
      List<List<List<double>>>.generate(
        28,
        (y) => List<List<double>>.generate(
          28,
          (x) => <double>[_pixelLuminance(resized, x, y).toDouble()],
          growable: false,
        ),
        growable: false,
      ),
    ];
  }

  static img.Image _centerCrop(img.Image source, double cropFraction) {
    final shortestSide = source.width < source.height
        ? source.width
        : source.height;
    final side = (shortestSide * cropFraction.clamp(0.1, 1)).round();
    return img.copyCrop(
      source,
      x: (source.width - side) ~/ 2,
      y: (source.height - side) ~/ 2,
      width: side,
      height: side,
    );
  }

  static Rect _boundsForPoints(List<Offset> points) {
    if (points.isEmpty) return const Rect.fromLTWH(0, 0, 1, 1);
    var left = points.first.dx;
    var top = points.first.dy;
    var right = points.first.dx;
    var bottom = points.first.dy;
    for (final point in points.skip(1)) {
      if (point.dx < left) left = point.dx;
      if (point.dy < top) top = point.dy;
      if (point.dx > right) right = point.dx;
      if (point.dy > bottom) bottom = point.dy;
    }
    return Rect.fromLTRB(
      left.clamp(0.0, 1.0),
      top.clamp(0.0, 1.0),
      right.clamp(0.0, 1.0),
      bottom.clamp(0.0, 1.0),
    );
  }

  static Size _orientedSize(int width, int height, int rotationDegrees) {
    final rotation = ((rotationDegrees % 360) + 360) % 360;
    return rotation == 90 || rotation == 270
        ? Size(height.toDouble(), width.toDouble())
        : Size(width.toDouble(), height.toDouble());
  }

  static Rect _squareCropAroundBounds(
    Size imageSize,
    Rect normalizedBounds, {
    required double paddingScale,
    double minimumSideFraction = 0,
  }) {
    final left = normalizedBounds.left.clamp(0.0, 1.0) * imageSize.width;
    final top = normalizedBounds.top.clamp(0.0, 1.0) * imageSize.height;
    final right = normalizedBounds.right.clamp(0.0, 1.0) * imageSize.width;
    final bottom = normalizedBounds.bottom.clamp(0.0, 1.0) * imageSize.height;
    final requestedSide =
        ((right - left).abs() > (bottom - top).abs()
            ? (right - left).abs()
            : (bottom - top).abs()) *
        paddingScale;
    final shortestSide = imageSize.width < imageSize.height
        ? imageSize.width
        : imageSize.height;
    final longestSide = imageSize.width > imageSize.height
        ? imageSize.width
        : imageSize.height;
    final minimumSide = (shortestSide * minimumSideFraction).clamp(
      1.0,
      shortestSide,
    );
    final side = requestedSide.clamp(minimumSide, longestSide);
    // Keep the hand centred even at a frame edge. Sampling outside the image
    // is filled with background instead of shifting and distorting the crop.
    final x = (left + right - side) / 2;
    final y = (top + bottom - side) / 2;
    return Rect.fromLTWH(x, y, side, side);
  }

  static img.Image _sampleLuminanceCrop(
    CameraImage cameraImage,
    Rect crop, {
    required int rotationDegrees,
    required bool mirrorHorizontally,
  }) {
    final plane = cameraImage.planes.first;
    final pixelStride = plane.bytesPerPixel ?? 1;
    final orientedSize = _orientedSize(
      cameraImage.width,
      cameraImage.height,
      rotationDegrees,
    );
    final paddingLuminance = _cameraBorderLuminance(
      cameraImage,
      rotationDegrees: rotationDegrees,
      mirrorHorizontally: mirrorHorizontally,
    );
    return _sampleModelCrop(
      crop,
      luminanceAt: (x, y) {
        final orientedX = x / orientedSize.width;
        final orientedY = y / orientedSize.height;
        if (orientedX < 0 ||
            orientedX >= 1 ||
            orientedY < 0 ||
            orientedY >= 1) {
          return paddingLuminance;
        }
        // Quantize in the upright image before mapping back to the sensor.
        // Otherwise a sample exactly on a pixel edge can choose the adjacent
        // pixel after a 90-degree rotation or mirror, unlike the still-image path.
        final sensorPoint = _orientedToSensorPoint(
          Offset(
            (x.floor() + 0.5) / orientedSize.width,
            (y.floor() + 0.5) / orientedSize.height,
          ),
          rotationDegrees: rotationDegrees,
          mirroredHorizontally: mirrorHorizontally,
        );
        final sensorX = (sensorPoint.dx * cameraImage.width).floor().clamp(
          0,
          cameraImage.width - 1,
        );
        final sensorY = (sensorPoint.dy * cameraImage.height).floor().clamp(
          0,
          cameraImage.height - 1,
        );
        return plane.bytes[sensorY * plane.bytesPerRow + sensorX * pixelStride];
      },
    );
  }

  static int _cameraBorderLuminance(
    CameraImage cameraImage, {
    required int rotationDegrees,
    required bool mirrorHorizontally,
  }) {
    final size = _orientedSize(
      cameraImage.width,
      cameraImage.height,
      rotationDegrees,
    );
    final plane = cameraImage.planes.first;
    final pixelStride = plane.bytesPerPixel ?? 1;
    final values =
        _borderPoints
            .map((point) {
              final pixelCenter = Offset(
                ((point.dx * (size.width - 1)).floor() + 0.5) / size.width,
                ((point.dy * (size.height - 1)).floor() + 0.5) / size.height,
              );
              final sensorPoint = _orientedToSensorPoint(
                pixelCenter,
                rotationDegrees: rotationDegrees,
                mirroredHorizontally: mirrorHorizontally,
              );
              final x = (sensorPoint.dx * cameraImage.width).floor().clamp(
                0,
                cameraImage.width - 1,
              );
              final y = (sensorPoint.dy * cameraImage.height).floor().clamp(
                0,
                cameraImage.height - 1,
              );
              return plane.bytes[y * plane.bytesPerRow + x * pixelStride];
            })
            .toList(growable: false)
          ..sort();
    return (values[3] + values[4]) ~/ 2;
  }

  static Offset _orientedToSensorPoint(
    Offset point, {
    required int rotationDegrees,
    required bool mirroredHorizontally,
  }) {
    final rotated = mirroredHorizontally
        ? Offset(1 - point.dx, point.dy)
        : point;
    final rotation = ((rotationDegrees % 360) + 360) % 360;
    return switch (rotation) {
      90 => Offset(rotated.dy, 1 - rotated.dx),
      180 => Offset(1 - rotated.dx, 1 - rotated.dy),
      270 => Offset(1 - rotated.dy, rotated.dx),
      _ => rotated,
    };
  }

  static img.Image _cropAroundHand(
    img.Image source,
    Rect normalizedCrop, {
    double paddingScale = 1.55,
    double minimumSideFraction = 0,
  }) {
    final crop = _squareCropAroundBounds(
      Size(source.width.toDouble(), source.height.toDouble()),
      normalizedCrop,
      paddingScale: paddingScale,
      minimumSideFraction: minimumSideFraction,
    );
    return _cropImageWithPadding(source, crop);
  }

  static img.Image _cropImageWithPadding(img.Image source, Rect crop) {
    final side = crop.width
        .round()
        .clamp(1, source.width + source.height)
        .toInt();
    final startX = crop.left.round();
    final startY = crop.top.round();
    final paddingLuminance = _imageBorderLuminance(source);
    final output = img.Image(width: side, height: side, numChannels: 1);
    for (var y = 0; y < side; y++) {
      final sourceY = startY + y;
      for (var x = 0; x < side; x++) {
        final sourceX = startX + x;
        final luminance =
            sourceX >= 0 &&
                sourceX < source.width &&
                sourceY >= 0 &&
                sourceY < source.height
            ? _pixelLuminance(source, sourceX, sourceY)
            : paddingLuminance;
        output.setPixelR(x, y, luminance);
      }
    }
    return output;
  }

  static num _imageBorderLuminance(img.Image source) {
    final maxX = source.width - 1;
    final maxY = source.height - 1;
    final values =
        _borderPoints
            .map(
              (point) => _pixelLuminance(
                source,
                (point.dx * maxX).floor(),
                (point.dy * maxY).floor(),
              ),
            )
            .toList()
          ..sort();
    return (values[3] + values[4]) / 2;
  }

  static num _pixelLuminance(img.Image source, int x, int y) {
    final pixel = source.getPixel(x, y);
    return source.numChannels == 1 ? pixel.r : pixel.luminance.round();
  }

  static img.Image _bgraImage(CameraImage cameraImage) {
    final plane = cameraImage.planes.first;
    final source = img.Image.fromBytes(
      width: cameraImage.width,
      height: cameraImage.height,
      bytes: plane.bytes.buffer,
      bytesOffset: plane.bytes.offsetInBytes,
      rowStride: plane.bytesPerRow,
      numChannels: 4,
      order: img.ChannelOrder.bgra,
    );
    // Convert to luminance once, in the shared crop sampler. Converting here
    // and reading RGB luminance again can truncate a neutral pixel twice.
    return source;
  }
}
