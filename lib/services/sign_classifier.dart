import '../models/sign_prediction.dart';

/// The model planned for this branch. No trained model is bundled yet.
enum SignModel {
  svmHog(id: 'svm_hog', name: 'SVM + HOG');

  const SignModel({required this.id, required this.name});

  final String id;
  final String name;
}

/// Frontend boundary only. A later task will supply preprocessing and inference.
/// Fails explicitly so the UI cannot record fabricated recognition results.
class SignClassifier {
  SignClassifier._();

  static final SignClassifier instance = SignClassifier._();
  static const unavailableMessage =
      'Backend SVM-HOG belum terpasang. Saat ini hanya frontend.';

  Future<void> initialize({SignModel model = SignModel.svmHog}) async {
    throw UnsupportedError(unavailableMessage);
  }

  Future<SignPrediction> classifyFile(
    String path, {
    SignModel model = SignModel.svmHog,
  }) async {
    throw UnsupportedError(unavailableMessage);
  }

  Future<SignPrediction> classifyUploadFile(
    String path, {
    SignModel model = SignModel.svmHog,
  }) => classifyFile(path, model: model);
}
