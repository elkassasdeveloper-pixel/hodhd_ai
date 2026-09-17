import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:audio_decoder/audio_decoder.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hodhd_ai/dash_chat.dart';
import 'package:hodhd_ai/service/ai_model_config.dart';
import 'package:hodhd_ai/service/cache_helper.dart';
import 'package:hodhd_ai/service/chat_database.dart';
import 'package:hodhd_ai/service/chat_sync/chat_sync_service.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

/// Selection value meaning "use the model/LoRA bundled with the app"
/// (i.e. the ones `AiModelConfig` extracts from assets), as opposed to a
/// custom `.gguf` filename found in the `models/`/`loras/` folders.
const String kDefaultModelSelection = '__default__';

/// LoRA-only selection value meaning "don't apply any LoRA".
const String kNoLoraSelection = '__none__';

class AiChatCubit extends Cubit<AiChatState> {
  AiChatCubit()
      : super(
    AiChatState.initial(
      enableThinking:
      CacheHelper.getData('enableThinking') as bool? ?? true,
      maxTokens: (CacheHelper.getData('maxTokens') as int?) ?? 1024,
      selectedModelFile:
      (CacheHelper.getData('selectedModelFile') as String?) ??
          kDefaultModelSelection,
      selectedLoraFile:
      (CacheHelper.getData('selectedLoraFile') as String?) ??
          kDefaultModelSelection,
      useAudioTranscription:
      CacheHelper.getData('useAudioTranscription') as bool? ?? true,
      chatSyncEnabled:
      CacheHelper.getData('chatSyncEnabled') as bool? ?? false,
    ),
  ) {
    _init();
  }

  final ChatUser me = ChatUser(uid: 'user', name: 'You');
  final ChatUser ai = ChatUser(uid: 'ai', name: 'Assistant');

  /// Exposed so the DashChat widget can bind to it directly.
  final TextEditingController chatController = TextEditingController();

  /// Bound to the search field shown in the AppBar when search is active.
  final TextEditingController searchController = TextEditingController();

  LlamaEngine? _engine;
  String? _loraPath;

  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _recordingPath;

  sherpa_onnx.OfflineRecognizer? _recognizer;
  sherpa_onnx.AudioTagging? _audioTagger;

  StreamSubscription<List<SharedMediaFile>>? _shareIntentSub;

  final ChatDatabase _chatDb = ChatDatabase();

  static const int _multimodalMaxImageEdge = 384;
  final ChatSyncService _chatSync = ChatSyncService();

  Future<void> _init() async {
    await _loadHistory();
    await _loadModel();
    _chatSync.init();
    if(!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)){
    await _initSharingIntent();
    }
  }

  // ====================== MODEL / LORA LIBRARY ======================
  // Lets you `adb push` extra .gguf model/LoRA files onto the device and
  // pick between them from Settings, instead of only ever using the one
  // bundled in assets. Push files into these two folders under the app's
  // documents directory:
  //   <app docs dir>/models/*.gguf
  //   <app docs dir>/loras/*.gguf
  // (Use `flutter run` with a debug , or `adb shell run-as
  // <package> ls files/models` to find the exact on-device path.)

  Future<Directory> _modelsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/models');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<Directory> _lorasDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/loras');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  List<String> _listGguf(Directory dir) {
    return dir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((name) => name.toLowerCase().endsWith('.gguf'))
        .toList()
      ..sort();
  }

  /// Rescans the `models/`/`loras/` folders. Call this from Settings (e.g.
  /// a refresh button) after `adb push`-ing a new file while the app is
  /// already running — the folders are otherwise only scanned once, at
  /// startup in [_loadModel].
  Future<void> refreshModelLibrary() async {
    final models = _listGguf(await _modelsDir());
    final loras = _listGguf(await _lorasDir());
    emit(
      state.copyWith(availableModelFiles: models, availableLoraFiles: loras),
    );
  }

  /// Checks which of [AiModelConfig.allAssets] (the server-downloadable
  /// core files) already exist at their default path — used by the
  /// Settings download list to show a ✓ instead of a Download button.
  /// Called at startup and after every successful [downloadAsset].
  Future<void> refreshDownloadedAssets() async {
    final appDir = await getApplicationDocumentsDirectory();
    final downloaded = <String>{
      for (final asset in AiModelConfig.allAssets)
        if (File('${appDir.path}/${asset.fileName}').existsSync())
          asset.fileName,
    };
    emit(state.copyWith(downloadedAssets: downloaded));
  }

  /// Selects which model file to load. Pass [kDefaultModelSelection] for
  /// the bundled model, or one of `state.availableModelFiles`. Persisted,
  /// but only applied on the next app restart (loading a model live isn't
  /// supported here — this just saves the choice).
  void selectModelFile(String fileName) {
    CacheHelper.saveData(key: 'selectedModelFile', value: fileName);
    emit(state.copyWith(selectedModelFile: fileName));
  }

  /// Selects which LoRA file to apply. Pass [kDefaultModelSelection] for
  /// the bundled LoRA, [kNoLoraSelection] to apply none, or one of
  /// `state.availableLoraFiles`. Same restart-to-apply caveat as
  /// [selectModelFile].
  void selectLoraFile(String fileName) {
    CacheHelper.saveData(key: 'selectedLoraFile', value: fileName);
    emit(state.copyWith(selectedLoraFile: fileName));
  }

  /// Lets the user pick a `.gguf` file from anywhere on the device (e.g.
  /// Downloads, after adb-pushing it there — public storage isn't directly
  /// readable on modern Android without scoped-storage workarounds) via
  /// `file_picker`, then copies it into `models/` or `loras/` so it shows
  /// up in [AiChatState.availableModelFiles] / [availableLoraFiles].
  ///
  /// Returns null on success (or user cancellation), or an error message
  /// to show the user otherwise. Does NOT select the imported file — call
  /// [selectModelFile]/[selectLoraFile] afterwards if you want that too.
  Future<String?> importModelFile({required bool isLora}) async {
    if (state.isImportingLibraryFile) return null;
    emit(state.copyWith(isImportingLibraryFile: true));
    try {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['gguf'],
      );
      final pickedPath = result?.path;
      if (pickedPath == null) {
        return null; // user cancelled — not an error
      }
      if (!pickedPath.toLowerCase().endsWith('.gguf')) {
        return 'Please pick a .gguf file.';
      }

      final targetDir = isLora ? await _lorasDir() : await _modelsDir();
      final fileName = pickedPath.split(Platform.pathSeparator).last;
      final destPath = '${targetDir.path}/$fileName';

      await File(pickedPath).copy(destPath);

      await refreshModelLibrary();
      return null;
    } catch (e) {
      ('Failed to import model/LoRA file: $e');
      return 'Import failed: $e';
    } finally {
      emit(state.copyWith(isImportingLibraryFile: false));
    }
  }

  // ====================== SERVER DOWNLOADS ======================
  // Core assets (main model, LoRA, vision, ASR, tagging) are downloaded
  // from AiModelConfig.baseDownloadUrl rather than bundled in the app.
  // Driven from Settings' download list.

  /// Downloads [asset] to the app's documents directory (same final path
  /// `_loadModel` already checks — `${appDir.path}/${asset.fileName}`),
  /// streaming so `state.downloadProgress[asset.fileName]` can be updated
  /// as bytes arrive. Returns null on success, or an error message.
  ///
  /// If this was the required main model and the engine isn't loaded yet,
  /// automatically retries [_loadModel] afterwards so the chat becomes
  /// usable immediately, with no restart needed.
  Future<String?> downloadAsset(DownloadableAsset asset) async {
    if (state.downloadingFile != null) {
      return 'Another download is already in progress.';
    }

    emit(
      state.copyWith(
        downloadingFile: asset.fileName,
        downloadProgress: {...state.downloadProgress, asset.fileName: 0.0},
      ),
    );

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final destPath = '${appDir.path}/${asset.fileName}';
      final tmpPath = '$destPath.part';

      final request = http.Request('GET', Uri.parse(asset.url));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        return 'Download failed: HTTP ${response.statusCode}';
      }

      final total = response.contentLength ?? 0;
      var received = 0;
      final sink = File(tmpPath).openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          emit(
            state.copyWith(
              downloadProgress: {
                ...state.downloadProgress,
                asset.fileName: received / total,
              },
            ),
          );
        }
      }
      await sink.close();

      // Only replace the destination once fully downloaded, so a
      // cancelled/failed download never leaves a corrupt/partial file
      // sitting at the real path for _loadModel to trip over later.
      await File(tmpPath).rename(destPath);

      await refreshModelLibrary();
      await refreshDownloadedAssets();

      // If this was the main model and we haven't loaded it yet, get the
      // chat working right away instead of requiring a restart.
      if (asset.fileName == AiModelConfig.requiredFileName) {
        await _loadModel();
      }

      return null;
    } catch (e) {
      ('Failed to download ${asset.fileName}: $e');
      return 'Download failed: $e';
    } finally {
      final updatedProgress = {...state.downloadProgress}
        ..remove(asset.fileName);
      emit(
        state.copyWith(
          downloadingFile: null,
          downloadProgress: updatedProgress,
        ),
      );
    }
  }

  // ====================== MODEL LOADING ======================

  Future<void> _loadModel() async {
    // Safe to call again after a download completes in Settings — only
    // ever creates the LlamaEngine once.
    if (_engine != null) return;

    final appDir = await getApplicationDocumentsDirectory();

    await refreshModelLibrary();
    await refreshDownloadedAssets();

    // Fall back to the bundled default if a previously-selected custom
    // file is no longer present (e.g. it was removed via adb, or this is
    // a fresh install that still has the old CacheHelper value).
    var modelSelection = state.selectedModelFile;
    if (modelSelection != kDefaultModelSelection &&
        !state.availableModelFiles.contains(modelSelection)) {
      (
        'Selected model "$modelSelection" not found, falling back to default.',
      );
      modelSelection = kDefaultModelSelection;
      selectModelFile(kDefaultModelSelection);
    }

    var loraSelection = state.selectedLoraFile;
    if (loraSelection != kDefaultModelSelection &&
        loraSelection != kNoLoraSelection &&
        !state.availableLoraFiles.contains(loraSelection)) {
      (
        'Selected LoRA "$loraSelection" not found, falling back to default.',
      );
      loraSelection = kDefaultModelSelection;
      selectLoraFile(kDefaultModelSelection);
    }

    final modelPath = modelSelection == kDefaultModelSelection
        ? '${appDir.path}/${AiModelConfig.modelFileName}'
        : '${appDir.path}/models/$modelSelection';

    // null = no LoRA at all (kNoLoraSelection).
    final String? loraPath = loraSelection == kNoLoraSelection
        ? null
        : loraSelection == kDefaultModelSelection
        ? '${appDir.path}/${AiModelConfig.loraFileName}'
        : '${appDir.path}/loras/$loraSelection';

    final mmprojPath = '${appDir.path}/${AiModelConfig.mmprojFileName}';
    final asrEncoderPath = '${appDir.path}/${AiModelConfig.asrEncoderFileName}';
    final asrDecoderPath = '${appDir.path}/${AiModelConfig.asrDecoderFileName}';
    final asrTokensPath = '${appDir.path}/${AiModelConfig.asrTokensFileName}';
    final tagModelPath = '${appDir.path}/${AiModelConfig.taggingModelFileName}';
    final tagLabelsPath =
        '${appDir.path}/${AiModelConfig.taggingLabelsFileName}';

    // Models are downloaded on demand (see downloadAsset, driven from
    // Settings) rather than bundled as assets. The main model is the one
    // hard requirement the chat can't function without — LoRA, vision,
    // speech recognition, and audio tagging all degrade gracefully if
    // their files aren't present, exactly like before, just sourced from
    // download now instead of asset extraction.
    if (!File(modelPath).existsSync()) {
      emit(
        state.copyWith(
          needsModelDownload: true,
          loadingText:
          'No language model downloaded yet. Go to Settings to '
              'download one before you can start chatting.',
        ),
      );
      return;
    }

    emit(
      state.copyWith(needsModelDownload: false, loadingText: 'Loading model...'),
    );

    _engine = LlamaEngine(LlamaBackend());
    await _engine!.loadModel(
      modelPath,
      modelParams: const ModelParams(gpuLayers: 0, contextSize: 1024),
    );

    if (loraPath != null && File(loraPath).existsSync()) {
      emit(state.copyWith(loadingText: 'Applying LoRA adapter...'));
      try {
        await _engine!.setLora(loraPath, scale: 1.0);
        _loraPath = loraPath;
        ('LoRA adapter loaded: $loraPath');
      } catch (e) {
        ('Failed to load LoRA adapter: $e');
      }
    }

    bool visionReady = false;
    bool audioSupported = false;
    if (File(mmprojPath).existsSync()) {
      emit(state.copyWith(loadingText: 'Loading vision adapter...'));
      try {
        await _engine!.loadMultimodalProjector(mmprojPath);
        final hasVision = await _engine!.supportsVision;
        final hasAudio = await _engine!.supportsAudio;
        visionReady = hasVision;
        audioSupported = hasAudio;
        ('Vision supported: $hasVision');
        ('Audio supported: $hasAudio');
      } catch (e) {
        visionReady = false;
        audioSupported = false;
        ('Failed to load vision adapter: $e');
      }
    }

    // Only initialize the ONNX model for whichever mode is actually
    // selected (state.useAudioTranscription) — both extracted-to-disk
    // above regardless, so switching modes later doesn't need
    // re-extraction, but running BOTH sherpa_onnx sessions at once on top
    // of the already-loaded GGUF model is exactly the kind of thing that
    // triggers `Ort::Exception: std::bad_alloc` on memory-constrained
    // devices — only one of these is ever used per message anyway.
    if (state.useAudioTranscription &&
        File(asrEncoderPath).existsSync() &&
        File(asrDecoderPath).existsSync() &&
        File(asrTokensPath).existsSync()) {
      emit(state.copyWith(loadingText: 'Loading speech recognizer...'));
      try {
        sherpa_onnx.initBindings();

        final asrConfig = sherpa_onnx.OfflineRecognizerConfig(
          model: sherpa_onnx.OfflineModelConfig(
            whisper: sherpa_onnx.OfflineWhisperModelConfig(
              encoder: asrEncoderPath,
              decoder: asrDecoderPath,
              language: 'ar',
              task: 'transcribe',
            ),
            tokens: asrTokensPath,
            numThreads: 2,
            debug: false,
          ),
        );

        _recognizer = sherpa_onnx.OfflineRecognizer(asrConfig);
        ('Speech recognizer loaded');
      } catch (e) {
        ('Failed to load speech recognizer: $e');
      }
    } else if (!state.useAudioTranscription &&
        File(tagModelPath).existsSync() &&
        File(tagLabelsPath).existsSync()) {
      emit(state.copyWith(loadingText: 'Loading audio tagging model...'));
      try {
        sherpa_onnx.initBindings();

        final tagConfig = sherpa_onnx.AudioTaggingConfig(
          model: sherpa_onnx.AudioTaggingModelConfig(
            zipformer: sherpa_onnx.OfflineZipformerAudioTaggingModelConfig(
              model: tagModelPath,
            ),
            numThreads: 2,
            debug: false,
          ),
          labels: tagLabelsPath,
        );

        _audioTagger = sherpa_onnx.AudioTagging(config: tagConfig);
        ('Audio tagging model loaded');
      } catch (e) {
        ('Failed to load audio tagging model: $e');
      }
    }

    final activeModelName = modelSelection == kDefaultModelSelection
        ? AiModelConfig.modelName
        : modelSelection;
    final activeLoraName = loraSelection == kNoLoraSelection
        ? 'None'
        : loraSelection == kDefaultModelSelection
        ? AiModelConfig.loraName
        : loraSelection;

    emit(
      state.copyWith(
        modelReady: true,
        visionReady: visionReady,
        supportsAudio: audioSupported,
        loraReady: _loraPath != null,
        activeModelName: activeModelName,
        activeLoraName: activeLoraName,
        // Raw selection values (same domain as selectedModelFile/
        // selectedLoraFile) actually used to load this session — lets the
        // UI detect "you picked something different, restart to apply" by
        // simple equality, instead of reverse-engineering it from the
        // display name above.
        activeModelSelection: modelSelection,
        activeLoraSelection: loraSelection,
      ),
    );
  }

  // ====================== SHARE INTENT (receive_sharing_intent) ======================
  // Lets other apps share an image (or text/url, if you add that
  // intent-filter too) directly into this chat.

  Future<void> _initSharingIntent() async {
    // While this app is already running in memory.
    _shareIntentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handleSharedFiles,
      onError: (err) => ('Share intent stream error: $err'),
    );

    // Cold start — app was launched *by* the share action.
    final initialFiles = await ReceiveSharingIntent.instance.getInitialMedia();
    if (initialFiles.isNotEmpty) {
      _handleSharedFiles(initialFiles);
    }
    // Tell the plugin the initial intent was consumed, otherwise the same
    // shared file gets redelivered next time getInitialMedia() is called
    // (e.g. after a hot restart).
    ReceiveSharingIntent.instance.reset();
  }

  void _handleSharedFiles(List<SharedMediaFile> files) async {
    for (final file in files) {
      // Compared by name/extension/mimeType rather than the enum constant
      // directly, since exact SharedMediaType members have changed across
      // package versions — this keeps it working either way.
      final typeName = file.type.toString().toLowerCase();
      final lowerPath = file.path.toLowerCase();
      final mimeType = file.mimeType?.toLowerCase() ?? '';

      final isImage = typeName.contains('image');
      final isWav = lowerPath.endsWith('.wav');
      // Any other audio — by extension (common voice-note/music formats)
      // or by mimeType prefix as a catch-all for anything the extension
      // list misses. sherpa_onnx.readWave() only understands wav, so
      // anything that isn't already wav gets converted first.
      const otherAudioExtensions = [
        '.opus',
        '.ogg',
        '.mp3',
        '.m4a',
        '.aac',
        '.flac',
        '.wma',
        '.amr',
        '.3gp',
        '.3gpp',
        '.aiff',
        '.caf',
        '.weba',
      ];
      final isConvertibleAudio = !isWav &&
          (otherAudioExtensions.any((ext) => lowerPath.endsWith(ext)) ||
              mimeType.startsWith('audio/'));

      if (isImage) {
        emit(
          state.copyWith(
            pendingSharedFile: SharedIncomingFile(
              path: file.path,
              kind: SharedFileKind.image,
            ),
          ),
        );
      } else if (isWav) {
        emit(
          state.copyWith(
            pendingSharedFile: SharedIncomingFile(
              path: file.path,
              kind: SharedFileKind.audio,
            ),
          ),
        );
      } else if (isConvertibleAudio) {
        final wavPath = await _convertSharedAudioToWav(file.path);
        if (wavPath != null) {
          emit(
            state.copyWith(
              pendingSharedFile: SharedIncomingFile(
                path: wavPath,
                kind: SharedFileKind.audio,
              ),
            ),
          );
        } else {
          ('Could not convert shared audio to wav: ${file.path}');
        }
      } else {
        // Only images and audio (wav passed through, anything else
        // auto-converted) are handled for now — everything else (video,
        // text, url, other file types) is ignored.
        ('Ignoring unsupported shared file: ${file.type} ($lowerPath)');
      }
    }
  }

  /// Called by the UI once it has picked up [AiChatState.pendingSharedFile]
  /// and shown the matching caption dialog, so the same shared file
  /// doesn't trigger the dialog again on the next rebuild.
  void clearPendingSharedFile() {
    emit(state.copyWith(pendingSharedFile: null));
  }

  Future<void> setLoraScale(double scale) async {
    if (_engine == null || _loraPath == null) return;
    try {
      await _engine!.setLora(_loraPath!, scale: scale);
      emit(state.copyWith(loraScale: scale));
    } catch (e) {
      ('Failed to set LoRA scale: $e');
    }
  }

  Future<void> disableLora() async {
    if (_engine == null || _loraPath == null) return;
    await _engine!.removeLora(_loraPath!);
    emit(state.copyWith(loraReady: false));
  }

  // ====================== USER-CONFIGURABLE SETTINGS ======================
  // Exposed for the Settings screen to read/write. Both are persisted via
  // CacheHelper (same pattern as MainCubit's theme settings) and applied to
  // the very next generation immediately — the chat screen listens to this
  // same cubit's state, so no restart is needed.

  void setEnableThinking(bool value) {
    CacheHelper.saveData(key: 'enableThinking', value: value);
    emit(state.copyWith(enableThinking: value));
  }

  void setMaxTokens(int value) {
    CacheHelper.saveData(key: 'maxTokens', value: value);
    emit(state.copyWith(maxTokens: value));
  }

  /// true = transcribe audio messages to text (ASR); false = tag/identify
  /// sounds instead. Explicitly chosen by the user rather than the old
  /// automatic "try transcription, fall back to tagging if empty" logic —
  /// applied to the very next audio message sent, no restart needed.
  void setUseAudioTranscription(bool value) {
    CacheHelper.saveData(key: 'useAudioTranscription', value: value);
    emit(state.copyWith(useAudioTranscription: value));
  }

  void setChatSyncEnabled(bool value) {
    CacheHelper.saveData(key: 'chatSyncEnabled', value: value);
    emit(state.copyWith(chatSyncEnabled: value));
  }

  // ====================== HISTORY / MESSAGE LIST ======================

  Future<void> _loadHistory() async {
    final history = await _chatDb.loadMessages();
    if (history.isNotEmpty) {
      emit(state.copyWith(messages: [...state.messages, ...history]));
    }
  }

  void _addMessage(ChatMessage msg) {
    emit(state.copyWith(messages: [...state.messages, msg]));
    _chatDb.saveMessage(msg);
  }

  void _replaceMessageAt(int index, ChatMessage msg) {
    final updated = List<ChatMessage>.from(state.messages);
    updated[index] = msg;
    emit(state.copyWith(messages: updated));
  }

  void extractStoryToJson() {
    final currentText = chatController.text.trim();
    final combinedText = currentText.isNotEmpty
        ? "$currentText\n\nExtract the story details into a JSON"
        : "Extract the story details into a JSON";

    final jsonMessage = ChatMessage(
      text: combinedText,
      user: me,
      createdAt: DateTime.now(),
      userName: me.name,
    );
    onSend(jsonMessage);
    chatController.clear();
  }

  // ====================== SEARCH ======================
  // Implemented as a live filter over `state.messages` rather than
  // scroll-to-message, since it works regardless of whether the custom
  // DashChat widget exposes any scroll-control API — it already has to
  // handle the message list changing (send/delete/clear), so handing it a
  // filtered subset to render works the same way.

  void openSearch() {
    emit(state.copyWith(isSearchActive: true));
  }

  void closeSearch() {
    searchController.clear();
    emit(state.copyWith(isSearchActive: false, searchQuery: ''));
  }

  void updateSearchQuery(String query) {
    emit(state.copyWith(searchQuery: query));
  }

  // ====================== PROMPT BUILDING ======================

  /// Builds the manual `<|im_start|>` prompt used by [generate] (the
  /// non-vision paths). `generate()` has no native `enableThinking`
  /// parameter — Qwen3 models expose the same toggle by appending
  /// `/no_think` to the user turn, so we do that here when thinking is
  /// disabled in settings. Remove this if your model/template doesn't
  /// support that convention.
  String _buildPrompt(String userText) {
    final content = state.enableThinking ? userText : '$userText /no_think';
    return '<|im_start|>user\n$content\n<|im_end|>\n<|im_start|>assistant\n';
  }

  // ====================== SEND / GENERATE ======================

  Future<void> onSend(ChatMessage userMsg) async {
    if (state.isGenerating) return;

    emit(state.copyWith(isGenerating: true));
    _addMessage(userMsg);

    final aiMsg = ChatMessage(
      text: '...',
      user: ai,
      userName: ai.name,
      createdAt: DateTime.now(),
    );
    emit(state.copyWith(messages: [...state.messages, aiMsg]));

    try {
      final buffer = StringBuffer();
      final stopwatch = Stopwatch()..start();
      int tokenCount = 0;

      if (userMsg.image != null) {
        // ===== IMAGE (vision) =====
        // Uses engine.create() + LlamaChatMessage.withContent, matching the
        // official llamadart multimodal example. This lets the engine build
        // the prompt via the model's own chat template (chatTemplate()),
        // instead of a hand-written prompt string with a manual <image>
        // placeholder, which was hanging indefinitely with generate().
        if (!state.visionReady) {
          _updateLastMessage(
            'Vision is not available on this device. Try resending without an image.',
            aiMsg.createdAt,
          );
          emit(state.copyWith(isGenerating: false));
          if (state.messages.isNotEmpty) {
            await _chatDb.saveMessage(state.messages.last);
          }
          return;
        }

        ('🖼️ Image path: ${userMsg.image}');
        ('🖼️ Image exists: ${File(userMsg.image!).existsSync()}');
        ('🖼️ Vision ready flag: ${state.visionReady}');

        final messages = [
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: [
              await _prepareImagePart(userMsg.image!),
              LlamaTextContent(
                userMsg.text?.isNotEmpty == true
                    ? userMsg.text!
                    : 'What is in this image?',
              ),
            ],
          ),
        ];

        ('🖼️ Starting create() with multimodal message...');

        await for (final chunk in _engine!
            .create(messages, enableThinking: state.enableThinking)
            .timeout(
          const Duration(seconds: 45),
          onTimeout: (sink) {
            ('🖼️ create() TIMED OUT after 45s — no tokens received');
            sink.close();
          },
        )) {
          final token = chunk.choices.first.delta.content;
          if (token != null && token.isNotEmpty) {
            ('🖼️ Got token: "$token"');
            tokenCount++;
            buffer.write(token);
            final cleaned = _stripThinkingAndStops(buffer.toString());
            _updateLastMessage(cleaned.text, aiMsg.createdAt);
            if (cleaned.stopped) break;
          }
        }
        ('🖼️ create() loop finished. Buffer: ${buffer.toString()}');
        stopwatch.stop();
        _appendStats(stopwatch.elapsedMilliseconds, tokenCount, aiMsg.createdAt);
      } else if (userMsg.customProperties?['type'] == 'audio') {
        final audioPath = userMsg.customProperties!['path'] as String;
        final useTranscription = state.useAudioTranscription;

        if (useTranscription && _recognizer == null) {
          _updateLastMessage(
            'Speech recognition model not loaded. Try switching to audio '
                'tagging in Settings.',
            aiMsg.createdAt,
          );
          emit(state.copyWith(isGenerating: false));
          return;
        }
        if (!useTranscription && _audioTagger == null) {
          _updateLastMessage(
            'Audio tagging model not loaded. Try switching to transcription '
                'in Settings.',
            aiMsg.createdAt,
          );
          emit(state.copyWith(isGenerating: false));
          return;
        }

        final audioDurationSeconds = _wavDurationSeconds(audioPath);
        final analysisStopwatch = Stopwatch()..start();

        String transcribedText = '';
        List<String> detectedSounds = [];
        if (useTranscription) {
          _updateLastMessage('Transcribing audio...', aiMsg.createdAt);
          transcribedText = _transcribeWav(audioPath).trim();
        } else {
          _updateLastMessage('Analyzing audio...', aiMsg.createdAt);
          detectedSounds = _detectSoundEvents(audioPath);
        }
        analysisStopwatch.stop();

        if (transcribedText.isEmpty && detectedSounds.isEmpty) {
          _updateLastMessage(
            useTranscription
                ? 'Could not understand the audio. Please try again.'
                : 'Could not identify any sounds in the audio. Please try '
                'again.',
            aiMsg.createdAt,
          );
          emit(state.copyWith(isGenerating: false));
          return;
        }

        final usedTranscription = transcribedText.isNotEmpty;
        final recognizedLabel = usedTranscription
            ? transcribedText
            : 'Detected sounds: ${detectedSounds.join(", ")}';

        final originalCaption = userMsg.text?.trim();
        final hasCaption =
            originalCaption != null &&
                originalCaption.isNotEmpty &&
                !originalCaption.startsWith('🎤') &&
                !originalCaption.startsWith('🎵');

        final combinedText = hasCaption
            ? '$originalCaption\n\n[Voice message ${usedTranscription ? 'transcription' : 'sound tags'}]: $recognizedLabel'
            : recognizedLabel;

        final userMsgIndex = state.messages.indexOf(userMsg);
        if (userMsgIndex != -1) {
          final displayText = usedTranscription
              ? (hasCaption
              ? '$originalCaption\n🎤 "$transcribedText"'
              : '🎤 "$transcribedText"')
              : (hasCaption
              ? '$originalCaption\n🔊 ${detectedSounds.join(", ")}'
              : '🔊 ${detectedSounds.join(", ")}');
          final updatedUserMsg = ChatMessage(
            id: userMsg.id,
            text: displayText,
            user: me,
            userName: me.name,
            createdAt: userMsg.createdAt,
            customProperties: userMsg.customProperties,
            buttons: userMsg.buttons,
          );
          _replaceMessageAt(userMsgIndex, updatedUserMsg);
          await _chatDb.saveMessage(updatedUserMsg);
        }

        _updateLastMessage('...', aiMsg.createdAt);

        final prompt = _buildPrompt(combinedText);

        await for (final token in _engine!.generate(
          prompt,
          params: GenerationParams(
            maxTokens: state.maxTokens,
            temp: 0.1,
            topP: 0.95,
          ),
        )) {
          tokenCount++;
          buffer.write(token);
          final cleaned = _stripThinkingAndStops(buffer.toString());
          _updateLastMessage(cleaned.text, aiMsg.createdAt);
          if (cleaned.stopped) break;
        }
        stopwatch.stop();
        _appendStats(
          stopwatch.elapsedMilliseconds,
          tokenCount,
          aiMsg.createdAt,
          audioAnalysis: AudioAnalysisStats(
            elapsedMs: analysisStopwatch.elapsedMilliseconds,
            durationSeconds: audioDurationSeconds,
          ),
        );
      } else {
        final prompt = _buildPrompt(userMsg.text ?? '');

        await for (final token in _engine!.generate(
          prompt,
          params: GenerationParams(
            maxTokens: state.maxTokens,
            temp: 0.1,
            topP: 0.95,
          ),
        )) {
          tokenCount++;
          buffer.write(token);
          final cleaned = _stripThinkingAndStops(buffer.toString());
          _updateLastMessage(cleaned.text, aiMsg.createdAt);
          if (cleaned.stopped) break;
        }
        stopwatch.stop();
        _appendStats(stopwatch.elapsedMilliseconds, tokenCount, aiMsg.createdAt);
      }
    } catch (e) {
      _updateLastMessage('Error: $e', aiMsg.createdAt);
    }

    if (state.messages.isNotEmpty) {
      await _chatDb.saveMessage(state.messages.last);
    }
    emit(state.copyWith(isGenerating: false));
    if(state.chatSyncEnabled){
    _chatSync.syncExchange(userMsg.text, state.messages.last.text);
  }
  }

  // ====================== IMAGE RESIZE FOR VISION ======================
  // The vision encoder chokes / hangs on full-resolution camera photos
  // (often 3000-4000px). Downscaling to a small max edge before sending is
  // what makes leehack/llamadart's own example chat app work reliably.

  Future<Uint8List> _downscaleImageBytesIfNeeded(
      Uint8List bytes, {
        required int maxEdge,
      }) async {
    ui.Codec? probeCodec;
    ui.Codec? resizedCodec;
    ui.Image? probedImage;
    ui.Image? resizedImage;

    try {
      probeCodec = await ui.instantiateImageCodec(bytes);
      final probeFrame = await probeCodec.getNextFrame();
      probedImage = probeFrame.image;
      final width = probedImage.width;
      final height = probedImage.height;
      final longestEdge = math.max(width, height);
      if (longestEdge <= maxEdge) {
        return bytes;
      }

      final scale = maxEdge / longestEdge;
      final targetWidth = math.max(1, (width * scale).round());
      final targetHeight = math.max(1, (height * scale).round());
      resizedCodec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final resizedFrame = await resizedCodec.getNextFrame();
      resizedImage = resizedFrame.image;
      final byteData = await resizedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      return byteData?.buffer.asUint8List() ?? bytes;
    } catch (_) {
      return bytes;
    } finally {
      resizedImage?.dispose();
      resizedCodec?.dispose();
      probedImage?.dispose();
      probeCodec?.dispose();
    }
  }

  Future<LlamaImageContent> _prepareImagePart(String imagePath) async {
    final originalBytes = await File(imagePath).readAsBytes();
    final resizedBytes = await _downscaleImageBytesIfNeeded(
      originalBytes,
      maxEdge: _multimodalMaxImageEdge,
    );
    (
      '🖼️ Resized image: ${originalBytes.length} bytes -> ${resizedBytes.length} bytes',
    );
    return LlamaImageContent(bytes: resizedBytes);
  }

  String _transcribeWav(String audioPath) {
    final waveData = sherpa_onnx.readWave(audioPath);
    final stream = _recognizer!.createStream();
    stream.acceptWaveform(
      samples: waveData.samples,
      sampleRate: waveData.sampleRate,
    );
    _recognizer!.decode(stream);
    final result = _recognizer!.getResult(stream);
    stream.free();
    return result.text;
  }

  List<String> _detectSoundEvents(String audioPath) {
    final stream = _audioTagger!.createStream();
    final waveData = sherpa_onnx.readWave(audioPath);
    stream.acceptWaveform(
      samples: waveData.samples,
      sampleRate: waveData.sampleRate,
    );
    final events = _audioTagger!.compute(stream: stream, topK: 5);
    stream.free();
    return events
        .map((e) => '${e.name} (${(e.prob * 100).toStringAsFixed(0)}%)')
        .toList();
  }

  /// Duration of a wav file in seconds, used as the denominator of the
  /// Real-Time Factor (RTF) shown alongside audio message stats.
  double _wavDurationSeconds(String audioPath) {
    final waveData = sherpa_onnx.readWave(audioPath);
    return waveData.samples.length / waveData.sampleRate;
  }

  /// Converts a shared audio file of any format (e.g. `.opus` WhatsApp
  /// voice notes, `.mp3`, `.m4a`, etc.) into a 16kHz mono wav via native
  /// platform decoders — matching what [startRecording] already produces,
  /// since sherpa_onnx.readWave() only understands wav. Returns the new
  /// wav path, or null on failure (e.g. an unsupported/corrupt codec).
  Future<String?> _convertSharedAudioToWav(String sourcePath) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final outputPath =
          '${appDir.path}/shared_${DateTime.now().millisecondsSinceEpoch}.wav';
      final wavPath = await AudioDecoder.convertToWav(
        sourcePath,
        outputPath,
        sampleRate: 16000,
        channels: 1,
      );
      ('Converted shared audio to wav: $sourcePath -> $wavPath');
      return wavPath;
    } catch (e) {
      ('Failed to convert shared audio ($sourcePath) to wav: $e');
      return null;
    }
  }

  void _updateLastMessage(String text, DateTime createdAt) {
    if (state.messages.isEmpty) return;
    final safeText = text
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
        .replaceAll(RegExp(r'[^\x09\x0A\x0D\x20-\uD7FF\uE000-\uFFFD]'), '');
    _replaceMessageAt(
      state.messages.length - 1,
      ChatMessage(
        text: safeText.isNotEmpty ? safeText : '...',
        user: ai,
        userName: ai.name,
        createdAt: createdAt,
      ),
    );
  }

  /// Appends generation stats (time + token count) to the end of the
  /// currently displayed AI message, e.g. "(3.2s • 84 tokens)". When
  /// [audioAnalysis] is given (audio messages only), a second line with
  /// the analysis time / audio duration / Real-Time Factor is appended too.
  void _appendStats(
      int elapsedMs,
      int tokenCount,
      DateTime createdAt, {
        AudioAnalysisStats? audioAnalysis,
      }) {
    if (state.messages.isEmpty) return;

    final seconds = elapsedMs / 1000;
    var statsLine = '\n\n— ${seconds.toStringAsFixed(1)}s • $tokenCount tokens';

    if (audioAnalysis != null) {
      statsLine += '\n${audioAnalysis.describe()}';
    }

    final last = state.messages.last;
    _replaceMessageAt(
      state.messages.length - 1,
      ChatMessage(
        id: last.id,
        text: '${last.text ?? ''}$statsLine',
        user: ai,
        userName: ai.name,
        createdAt: createdAt,
      ),
    );
  }

  ({String text, bool stopped}) _stripThinkingAndStops(String raw) {
    final thinkEnd = raw.indexOf('</think>');
    final afterThink = thinkEnd != -1
        ? raw.substring(thinkEnd + 8).trimLeft()
        : raw;
    final stopIndex = afterThink.indexOf('<|im_end|>');
    final displayText = stopIndex != -1
        ? afterThink.substring(0, stopIndex)
        : afterThink;
    return (text: displayText, stopped: stopIndex != -1);
  }

  // ====================== ATTACHMENTS ======================

  /// Returns the picked photo path, or null if permission was denied / the
  /// user cancelled. The caller (UI layer) is responsible for showing the
  /// caption dialog and then calling [sendImageMessage].
  ///
  /// If permission was permanently denied (user tapped "Don't Allow" once
  /// before, or the system otherwise won't show the dialog again), this
  /// sends the user straight to the app's Settings page instead of
  /// silently doing nothing — a `.request()` call alone can never recover
  /// from that state.
  Future<String?> pickCameraImage() async {
    final picker = ImagePicker();

    final image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );

    return image?.path;
  }

  Future<String?> pickGalleryImage() async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    return image?.path;
  }

  void sendImageMessage(String imagePath, String caption) {
    final msg = ChatMessage(
      text: caption.trim(),
      image: imagePath,
      user: me,
      userName: me.name,
      createdAt: DateTime.now(),
    );
    onSend(msg);
  }

  /// Returns the picked wav file's (path, name), or null if cancelled.
  Future<({String path, String name})?> pickAudioFile() async {
    final result = await FilePicker.pickFile(
      type: FileType.audio,
    );

    if (result != null && result.path != null) {
      return (path: result.path!, name: result.name);
    }
    return null;
  }

  void sendAudioMessage(String audioPath, String fileName, String caption) {
    final trimmed = caption.trim();
    final msg = ChatMessage(
      text: trimmed.isNotEmpty ? trimmed : '🎵 $fileName',
      user: me,
      userName: me.name,
      createdAt: DateTime.now(),
      customProperties: {'type': 'audio', 'path': audioPath},
    );
    onSend(msg);
  }

  // ====================== VOICE RECORDING ======================

  /// Same permanently-denied handling as [pickCameraImage] — sends the
  /// user to Settings instead of silently failing.
  Future<void> startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      return;
    }
    final appDir = await getApplicationDocumentsDirectory();
    _recordingPath =
    '${appDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: _recordingPath!,
    );

    emit(state.copyWith(isRecording: true));
  }

  Future<void> stopRecording() async {
    await _recorder.stop();
    emit(state.copyWith(isRecording: false));

    if (_recordingPath != null && File(_recordingPath!).existsSync()) {
      final msg = ChatMessage(
        text: '🎤 Voice message',
        user: me,
        userName: me.name,
        createdAt: DateTime.now(),
        customProperties: {'type': 'audio', 'path': _recordingPath!},
      );
      onSend(msg);
    }
  }

  // ====================== AUDIO PLAYBACK ======================

  Future<void> toggleAudioPlayback(String path) async {
    final isPlaying = state.playingState[path] ?? false;

    if (isPlaying) {
      await _audioPlayer.stop();
      emit(state.copyWith(playingState: {...state.playingState, path: false}));
    } else {
      await _audioPlayer.stop();
      final resetState = <String, bool>{
        for (final key in state.playingState.keys) key: false,
      };
      await _audioPlayer.play(DeviceFileSource(path));
      emit(state.copyWith(playingState: {...resetState, path: true}));
      _audioPlayer.onPlayerComplete.first.then((_) {
        if (isClosed) return;
        emit(state.copyWith(playingState: {...state.playingState, path: false}));
      });
    }
  }

  // ====================== DELETE ======================

  Future<void> deleteMessage(ChatMessage message) async {
    final updated = state.messages.where((m) => m.id != message.id).toList();
    emit(state.copyWith(messages: updated));
    if (message.id != null) {
      await _chatDb.deleteMessage(message.id!);
    }
  }

  Future<void> clearHistory() async {
    await _chatDb.clearAll();
    emit(state.copyWith(messages: []));
  }

  @override
  Future<void> close() {
    _shareIntentSub?.cancel();
    _engine?.dispose();
    _recognizer?.free();
    _audioTagger?.free();
    _recorder.dispose();
    _audioPlayer.dispose();
    chatController.dispose();
    searchController.dispose();
    return super.close();
  }
}

/// Real-Time Factor (RTF) for the audio analysis step (transcription
/// and/or sound tagging) — analysis time divided by the audio clip's own
/// duration.
///
/// RTF < 1 means the analysis ran faster than the audio itself, so it
/// could in principle keep up with a live/streaming feed without falling
/// behind. RTF >= 1 means analysis took as long as (or longer than) the
/// clip, so it could NOT keep up in real time.
class AudioAnalysisStats {
  const AudioAnalysisStats({
    required this.elapsedMs,
    required this.durationSeconds,
  });

  /// How long transcription/tagging actually took, in milliseconds.
  final int elapsedMs;

  /// The audio clip's own duration, in seconds.
  final double durationSeconds;

  double get rtf =>
      durationSeconds > 0 ? (elapsedMs / 1000) / durationSeconds : 0;

  String describe() {
    final analysisSeconds = elapsedMs / 1000;
    return '🎧 ${analysisSeconds.toStringAsFixed(2)}s analysis / '
        '${durationSeconds.toStringAsFixed(2)}s audio • '
        'RTF ${rtf.toStringAsFixed(2)}';
  }
}

/// Which caption dialog the UI should open for an incoming shared file.
enum SharedFileKind { image, audio }

/// A file received via the share intent, waiting for the UI to show its
/// caption dialog. See [AiChatState.pendingSharedFile].
class SharedIncomingFile {
  const SharedIncomingFile({required this.path, required this.kind});

  final String path;
  final SharedFileKind kind;

  @override
  bool operator ==(Object other) =>
      other is SharedIncomingFile && other.path == path && other.kind == kind;

  @override
  int get hashCode => Object.hash(path, kind);
}

/// Sentinel used by [AiChatState.copyWith] to tell "clear this field to
/// null" apart from "leave it as it was" (a plain `null` default can't
/// distinguish the two).
const Object _unset = Object();

/// A shared image or wav file waiting for the UI to show a caption dialog
/// for, set by [AiChatCubit]'s share-intent handling and consumed (then
/// cleared via [AiChatCubit.clearPendingSharedFile]) by the chat screen.
class AiChatState {
  const AiChatState({
    required this.messages,
    required this.modelReady,
    required this.isGenerating,
    required this.loadingText,
    required this.visionReady,
    required this.supportsAudio,
    required this.isRecording,
    required this.playingState,
    required this.loraReady,
    required this.loraScale,
    required this.enableThinking,
    required this.maxTokens,
    required this.availableModelFiles,
    required this.availableLoraFiles,
    required this.selectedModelFile,
    required this.selectedLoraFile,
    required this.isImportingLibraryFile,
    required this.needsModelDownload,
    required this.downloadedAssets,
    required this.downloadProgress,
    this.downloadingFile,
    required this.isSearchActive,
    required this.searchQuery,
    required this.activeModelName,
    required this.activeLoraName,
    required this.activeModelSelection,
    required this.activeLoraSelection,
    required this.useAudioTranscription,
    required this.chatSyncEnabled,
    this.pendingSharedFile,
  });

  factory AiChatState.initial({
    bool enableThinking = true,
    int maxTokens = 1024,
    String selectedModelFile = kDefaultModelSelection,
    String selectedLoraFile = kDefaultModelSelection,
    bool useAudioTranscription = true,
    bool chatSyncEnabled = false,
  }) =>
      AiChatState(
        messages: const [],
        modelReady: false,
        isGenerating: false,
        loadingText: 'Loading AI model...',
        visionReady: false,
        supportsAudio: false,
        isRecording: false,
        playingState: const {},
        loraReady: false,
        loraScale: 1.0,
        enableThinking: enableThinking,
        maxTokens: maxTokens,
        availableModelFiles: const [],
        availableLoraFiles: const [],
        selectedModelFile: selectedModelFile,
        selectedLoraFile: selectedLoraFile,
        isImportingLibraryFile: false,
        needsModelDownload: false,
        downloadedAssets: const {},
        downloadProgress: const {},
        isSearchActive: false,
        searchQuery: '',
        useAudioTranscription: useAudioTranscription,
        chatSyncEnabled: chatSyncEnabled,
        activeModelName: AiModelConfig.modelName,
        activeLoraName: AiModelConfig.loraName,
        activeModelSelection: kDefaultModelSelection,
        activeLoraSelection: kDefaultModelSelection,
      );

  final List<ChatMessage> messages;
  final bool modelReady;
  final bool isGenerating;
  final String loadingText;

  /// Whether the loaded model/mmproj combo actually supports image input.
  final bool visionReady;

  /// Whether the loaded model/mmproj combo actually supports audio input.
  /// (Informational only for now — nothing in the pipeline feeds native
  /// audio input to the engine yet; audio messages still go through the
  /// ASR/tagging path above.)
  final bool supportsAudio;

  final bool isRecording;

  /// Whether a LoRA adapter was successfully loaded and can have its
  /// strength adjusted via [AiChatCubit.setLoraScale].
  final bool loraReady;

  /// Current LoRA adapter strength (1.0 = as trained).
  final double loraScale;

  /// Whether the model is allowed to emit `<think>...</think>` reasoning
  /// before its answer. Editable from Settings via
  /// [AiChatCubit.setEnableThinking], persisted, and applied to every
  /// generation immediately (no restart needed).
  final bool enableThinking;

  /// Max tokens generated per response. Editable from Settings via
  /// [AiChatCubit.setMaxTokens], persisted, and applied immediately.
  final int maxTokens;

  /// `.gguf` filenames found in `<app docs dir>/models/` (adb-pushed extra
  /// models), populated by [AiChatCubit.refreshModelLibrary]. Does NOT
  /// include the bundled default model — see [kDefaultModelSelection].
  final List<String> availableModelFiles;

  /// Same as [availableModelFiles] but for `<app docs dir>/loras/`.
  final List<String> availableLoraFiles;

  /// Currently selected model: [kDefaultModelSelection] or a filename from
  /// [availableModelFiles]. Set via [AiChatCubit.selectModelFile];
  /// persisted, applied on next app restart.
  final String selectedModelFile;

  /// Currently selected LoRA: [kDefaultModelSelection], [kNoLoraSelection],
  /// or a filename from [availableLoraFiles]. Set via
  /// [AiChatCubit.selectLoraFile]; persisted, applied on next app restart.
  final String selectedLoraFile;

  /// True while [AiChatCubit.importModelFile] is copying a picked file into
  /// `models/`/`loras/` — lets Settings disable the import buttons and show
  /// a spinner during the (possibly slow, for multi-GB files) copy.
  final bool isImportingLibraryFile;

  /// True when the main model (AiModelConfig.requiredFileName) isn't
  /// present locally — the chat screen shows a "download it in Settings"
  /// prompt instead of trying to load a missing file. Re-checked by
  /// [AiChatCubit._loadModel], which retries automatically after
  /// [AiChatCubit.downloadAsset] finishes downloading the main model.
  final bool needsModelDownload;

  /// Filenames from [AiModelConfig.allAssets] confirmed present on disk —
  /// refreshed by [AiChatCubit.refreshDownloadedAssets]. Drives the ✓ vs
  /// "Download" button in the Settings download list.
  final Set<String> downloadedAssets;

  /// Download progress (0.0–1.0) keyed by [DownloadableAsset.fileName],
  /// for whichever file(s) are currently downloading. A file with no
  /// entry here is either not downloading or already finished/failed.
  final Map<String, double> downloadProgress;

  /// Filename of the asset currently downloading, or null if none. Only
  /// one download runs at a time — see [AiChatCubit.downloadAsset].
  final String? downloadingFile;

  /// True while the AppBar search field is shown. Toggled via
  /// [AiChatCubit.openSearch]/[AiChatCubit.closeSearch].
  final bool isSearchActive;

  /// Current search text (case-insensitive substring match against each
  /// message's text). Empty means "show everything" — see
  /// [AiChatCubit.updateSearchQuery].
  final String searchQuery;

  /// Display name of the model/LoRA actually loaded into the running
  /// engine right now — as opposed to [selectedModelFile]/
  /// [selectedLoraFile], which is what will load on the *next* restart.
  /// Set once, at the end of [AiChatCubit._loadModel].
  final String activeModelName;
  final String activeLoraName;

  /// Raw selection value (same domain as [selectedModelFile]/
  /// [selectedLoraFile]: [kDefaultModelSelection], [kNoLoraSelection], or a
  /// filename) that was actually used to load this session — compare
  /// against [selectedModelFile]/[selectedLoraFile] to detect a pending,
  /// not-yet-applied change.
  final String activeModelSelection;
  final String activeLoraSelection;

  /// true = transcribe audio messages (ASR); false = tag/identify sounds
  /// instead. Editable from Settings via
  /// [AiChatCubit.setUseAudioTranscription], persisted, applied to the
  /// next audio message immediately.
  final bool useAudioTranscription;
  final bool chatSyncEnabled;

  /// A file just received via the share intent (image or .wav audio) that
  /// the UI still needs to show a caption dialog for. Set by
  /// [AiChatCubit._handleSharedFiles], cleared by
  /// [AiChatCubit.clearPendingSharedFile] once the UI has acted on it.
  final SharedIncomingFile? pendingSharedFile;

  /// Maps an audio file path -> whether it is currently playing.
  final Map<String, bool> playingState;

  AiChatState copyWith({
    List<ChatMessage>? messages,
    bool? modelReady,
    bool? isGenerating,
    String? loadingText,
    bool? visionReady,
    bool? supportsAudio,
    bool? isRecording,
    Map<String, bool>? playingState,
    bool? loraReady,
    double? loraScale,
    bool? enableThinking,
    int? maxTokens,
    List<String>? availableModelFiles,
    List<String>? availableLoraFiles,
    String? selectedModelFile,
    String? selectedLoraFile,
    bool? isImportingLibraryFile,
    bool? isSearchActive,
    String? searchQuery,
    String? activeModelName,
    String? activeLoraName,
    String? activeModelSelection,
    String? activeLoraSelection,
    bool? useAudioTranscription,
    bool? chatSyncEnabled,
    bool? needsModelDownload,
    Set<String>? downloadedAssets,
    Map<String, double>? downloadProgress,
    // Uses the `_unset` sentinel so passing `pendingSharedFile: null` /
    // `downloadingFile: null` explicitly clears them, while omitting the
    // argument leaves them as-is — a plain nullable default can't tell
    // those two calls apart.
    Object? pendingSharedFile = _unset,
    Object? downloadingFile = _unset,
  }) {
    return AiChatState(
      messages: messages ?? this.messages,
      modelReady: modelReady ?? this.modelReady,
      isGenerating: isGenerating ?? this.isGenerating,
      loadingText: loadingText ?? this.loadingText,
      visionReady: visionReady ?? this.visionReady,
      supportsAudio: supportsAudio ?? this.supportsAudio,
      isRecording: isRecording ?? this.isRecording,
      playingState: playingState ?? this.playingState,
      loraReady: loraReady ?? this.loraReady,
      loraScale: loraScale ?? this.loraScale,
      enableThinking: enableThinking ?? this.enableThinking,
      maxTokens: maxTokens ?? this.maxTokens,
      availableModelFiles: availableModelFiles ?? this.availableModelFiles,
      availableLoraFiles: availableLoraFiles ?? this.availableLoraFiles,
      selectedModelFile: selectedModelFile ?? this.selectedModelFile,
      selectedLoraFile: selectedLoraFile ?? this.selectedLoraFile,
      isImportingLibraryFile:
      isImportingLibraryFile ?? this.isImportingLibraryFile,
      isSearchActive: isSearchActive ?? this.isSearchActive,
      searchQuery: searchQuery ?? this.searchQuery,
      activeModelName: activeModelName ?? this.activeModelName,
      activeLoraName: activeLoraName ?? this.activeLoraName,
      activeModelSelection: activeModelSelection ?? this.activeModelSelection,
      activeLoraSelection: activeLoraSelection ?? this.activeLoraSelection,
      useAudioTranscription:
      useAudioTranscription ?? this.useAudioTranscription,
      chatSyncEnabled: chatSyncEnabled ?? this.chatSyncEnabled,
      needsModelDownload: needsModelDownload ?? this.needsModelDownload,
      downloadedAssets: downloadedAssets ?? this.downloadedAssets,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      pendingSharedFile: identical(pendingSharedFile, _unset)
          ? this.pendingSharedFile
          : pendingSharedFile as SharedIncomingFile?,
      downloadingFile: identical(downloadingFile, _unset)
          ? this.downloadingFile
          : downloadingFile as String?,
    );
  }
}