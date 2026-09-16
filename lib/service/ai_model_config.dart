/// Central place for every AI asset's name AND download source.
///
/// Models are no longer bundled in the app — they're downloaded on demand
/// from [baseDownloadUrl] into the app's documents directory. Change a
/// name, or repoint at a different host/CDN, in exactly this one file —
/// every place that downloads, loads, or displays these assets (the
/// cubit's `_loadModel`/download logic, and Settings) reads from here.
class AiModelConfig {
  AiModelConfig._();

  /// Base URL your model files are hosted under. Each file's full URL is
  /// `$baseDownloadUrl/<fileName>` unless overridden individually below.
  static const String baseDownloadUrl = 'https://alajeeeb.erpfirst.net/models';

  // ====================== MAIN LLM MODEL (.gguf) ======================
  static const String modelName = 'Qwen3.5-0.8B-Q4_K_M';
  static const String modelFileName = '$modelName.gguf';
  static const String modelDownloadUrl = '$baseDownloadUrl/$modelFileName';

  // ====================== LORA ADAPTER (.gguf) ======================
  static const String loraName = 'Final-Qwen3-0.8B_rank_8_F16-LoRA';
  static const String loraFileName = '$loraName.gguf';
  static const String loraDownloadUrl = '$baseDownloadUrl/$loraFileName';

  // ====================== VISION ADAPTER / MMPROJ (.gguf) ======================
  static const String mmprojName = 'mmproj-F16';
  static const String mmprojFileName = '$mmprojName.gguf';
  static const String mmprojDownloadUrl = '$baseDownloadUrl/$mmprojFileName';

  // ====================== SPEECH RECOGNITION (ASR) ONNX ======================
  static const String asrEncoderName = 'base-encoder.int8';
  static const String asrEncoderFileName = '$asrEncoderName.onnx';
  static const String asrEncoderDownloadUrl =
      '$baseDownloadUrl/$asrEncoderFileName';

  static const String asrDecoderName = 'base-decoder.int8';
  static const String asrDecoderFileName = '$asrDecoderName.onnx';
  static const String asrDecoderDownloadUrl =
      '$baseDownloadUrl/$asrDecoderFileName';

  static const String asrTokensName = 'base-tokens';
  static const String asrTokensFileName = '$asrTokensName.txt';
  static const String asrTokensDownloadUrl =
      '$baseDownloadUrl/$asrTokensFileName';

  // ====================== AUDIO TAGGING ONNX ======================
  static const String taggingModelName = 'tagging-model.int8';
  static const String taggingModelFileName = '$taggingModelName.onnx';
  static const String taggingModelDownloadUrl =
      '$baseDownloadUrl/$taggingModelFileName';

  static const String taggingLabelsName = 'class_labels_indices';
  static const String taggingLabelsFileName = '$taggingLabelsName.csv';
  static const String taggingLabelsDownloadUrl =
      '$baseDownloadUrl/$taggingLabelsFileName';

  /// The one file that MUST be downloaded before the chat can do anything
  /// at all. Everything else (LoRA, vision, speech recognition, audio
  /// tagging) degrades gracefully if missing — same as before, just
  /// sourced from download now instead of bundled assets.
  static const String requiredFileName = modelFileName;

  /// Every downloadable asset, for driving the Settings download list.
  static const List<DownloadableAsset> allAssets = [
    DownloadableAsset(
      label: 'Language model',
      fileName: modelFileName,
      url: modelDownloadUrl,
      required: true,
    ),
    DownloadableAsset(
      label: 'LoRA adapter',
      fileName: loraFileName,
      url: loraDownloadUrl,
    ),
    DownloadableAsset(
      label: 'Vision adapter',
      fileName: mmprojFileName,
      url: mmprojDownloadUrl,
    ),
    DownloadableAsset(
      label: 'Speech recognition encoder',
      fileName: asrEncoderFileName,
      url: asrEncoderDownloadUrl,
    ),
    DownloadableAsset(
      label: 'Speech recognition decoder',
      fileName: asrDecoderFileName,
      url: asrDecoderDownloadUrl,
    ),
    DownloadableAsset(
      label: 'Speech recognition tokens',
      fileName: asrTokensFileName,
      url: asrTokensDownloadUrl,
    ),
    DownloadableAsset(
      label: 'Audio tagging model',
      fileName: taggingModelFileName,
      url: taggingModelDownloadUrl,
    ),
    DownloadableAsset(
      label: 'Audio tagging labels',
      fileName: taggingLabelsFileName,
      url: taggingLabelsDownloadUrl,
    ),
  ];
}

/// One downloadable model/adapter/onnx asset — everything the Settings
/// download list and [AiChatCubit.downloadAsset] need to know about it.
class DownloadableAsset {
  const DownloadableAsset({
    required this.label,
    required this.fileName,
    required this.url,
    this.required = false,
  });

  /// Human-readable name shown in Settings.
  final String label;

  /// Local file name, also used as the key into
  /// `AiChatState.downloadProgress`.
  final String fileName;

  /// Full download URL.
  final String url;

  /// Whether the chat screen is unusable without this file. Only true for
  /// the main model — see [AiModelConfig.requiredFileName].
  final bool required;
}