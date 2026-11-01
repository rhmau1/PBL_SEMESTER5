import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sign_language/services/jz_camera_frame_encoder.dart';

CameraImage _frame({
  required int width,
  required int height,
  required ImageFormatGroup format,
  required List<CameraImagePlane> planes,
}) => CameraImage.fromPlatformInterface(
  CameraImageData(
    format: CameraImageFormat(format, raw: 0),
    width: width,
    height: height,
    planes: planes,
  ),
);

CameraImage _bgra({int width = 32, int height = 16, int? pixelStride}) {
  final stride = width * 4 + 8;
  final bytes = Uint8List(stride * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final index = y * stride + x * 4;
      bytes[index] = x < width ~/ 2 ? 0 : 255;
      bytes[index + 2] = x < width ~/ 2 ? 255 : 0;
      bytes[index + 3] = 255;
    }
  }
  return _frame(
    width: width,
    height: height,
    format: ImageFormatGroup.bgra8888,
    planes: [
      CameraImagePlane(
        bytes: bytes,
        bytesPerRow: stride,
        bytesPerPixel: pixelStride,
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'BGRA null pixel stride keeps color and does not mirror the frame',
    () async {
      final decoded = img.decodeJpg(
        await encodeJzCameraFrame(_bgra(), rotationDegrees: 0),
      )!;
      expect([decoded.width, decoded.height], [32, 16]);
      final left = decoded.getPixel(4, 8);
      final right = decoded.getPixel(27, 8);
      expect(left.r, greaterThan(220));
      expect(left.b, lessThan(30));
      expect(right.b, greaterThan(220));
      expect(right.r, lessThan(30));
    },
  );

  test('rotation swaps dimensions once and preserves the full image', () async {
    final decoded = img.decodeJpg(
      await encodeJzCameraFrame(_bgra(pixelStride: 4), rotationDegrees: 90),
    )!;
    expect([decoded.width, decoded.height], [16, 32]);
    expect(decoded.getPixel(8, 4).r, greaterThan(220));
    expect(decoded.getPixel(8, 27).b, greaterThan(220));
  });

  test(
    'large camera frame shrinks proportionally without a square crop',
    () async {
      final decoded = img.decodeJpg(
        await encodeJzCameraFrame(
          _bgra(width: 1280, height: 720),
          rotationDegrees: 0,
        ),
      )!;
      expect([decoded.width, decoded.height], [640, 360]);
    },
  );

  test(
    'selected camera bytes are copied before asynchronous conversion',
    () async {
      final source = _bgra();
      final encoded = encodeJzCameraFrame(source, rotationDegrees: 0);
      source.planes.single.bytes.fillRange(
        0,
        source.planes.single.bytes.length,
        0,
      );
      final decoded = img.decodeJpg(await encoded)!;
      expect(decoded.getPixel(4, 8).r, greaterThan(220));
    },
  );

  test(
    'YUV420 honors row padding and interleaved chroma pixel stride',
    () async {
      final source = _frame(
        width: 16,
        height: 8,
        format: ImageFormatGroup.yuv420,
        planes: [
          CameraImagePlane(
            bytes: Uint8List.fromList(List.filled(20 * 8, 150)),
            bytesPerRow: 20,
            bytesPerPixel: 1,
          ),
          for (var i = 0; i < 2; i++)
            CameraImagePlane(
              bytes: Uint8List.fromList(List.filled(20 * 4, 128)),
              bytesPerRow: 20,
              bytesPerPixel: 2,
            ),
        ],
      );
      final decoded = img.decodeJpg(
        await encodeJzCameraFrame(source, rotationDegrees: 0),
      )!;
      final pixel = decoded.getPixel(8, 4);
      expect(pixel.r, closeTo(150, 4));
      expect(pixel.g, closeTo(150, 4));
      expect(pixel.b, closeTo(150, 4));
    },
  );

  test('packed NV21 reads V then U instead of swapping the colors', () async {
    final bytes = Uint8List(16 * 8 + 16 * 4);
    bytes.fillRange(0, 16 * 8, 100);
    for (var i = 16 * 8; i < bytes.length; i += 2) {
      bytes[i] = 128;
      bytes[i + 1] = 255;
    }
    final source = _frame(
      width: 16,
      height: 8,
      format: ImageFormatGroup.nv21,
      planes: [
        CameraImagePlane(bytes: bytes, bytesPerRow: 16, bytesPerPixel: 1),
      ],
    );
    final decoded = img.decodeJpg(
      await encodeJzCameraFrame(source, rotationDegrees: 0),
    )!;
    expect(decoded.getPixel(8, 4).b, greaterThan(235));
    expect(decoded.getPixel(8, 4).r, lessThan(130));
  });

  test(
    'invalid row stride is rejected rather than reading the next row',
    () async {
      final source = _frame(
        width: 8,
        height: 8,
        format: ImageFormatGroup.bgra8888,
        planes: [CameraImagePlane(bytes: Uint8List(256), bytesPerRow: 16)],
      );
      await expectLater(
        encodeJzCameraFrame(source, rotationDegrees: 0),
        throwsFormatException,
      );
    },
  );
}
