import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:hodhd_ai/app_drawer.dart';
import 'package:hodhd_ai/font.dart';
import 'package:hodhd_ai/service/ai_model_config.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'audio_stream_utils.dart';
import 'debug_data_screen.dart';

class AudioClassifierResult {
  const AudioClassifierResult(this.label, this.prob);
  final String label;
  final double prob;
}

/// Interface for a real-time audio classifier: initialize once, then feed
/// it fixed-size sample windows to classify. Safe to call classify() back
/// to back from multiple independent callers (e.g. multiple mics) since
/// each call is self-contained — no state carries between calls.
abstract class AudioClassifier {
  Future<void> init();
  List<AudioClassifierResult> classify(Float32List samples, int sampleRate);
  void dispose();
}

/// Thrown by [SherpaZipformerTagger.init] when the audio tagging model
/// hasn't been downloaded yet (see Settings → Model Downloads).
class ModelNotDownloadedException implements Exception {
  const ModelNotDownloadedException();

  @override
  String toString() =>
      'Audio tagging model not downloaded yet. Go to Settings to download it.';
}

class SherpaZipformerTagger implements AudioClassifier {
  sherpa_onnx.AudioTagging? _tagger;

  @override
  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelPath = '${appDir.path}/${AiModelConfig.taggingModelFileName}';
    final labelsPath =
        '${appDir.path}/${AiModelConfig.taggingLabelsFileName}';

    if (!File(modelPath).existsSync() || !File(labelsPath).existsSync()) {
      throw const ModelNotDownloadedException();
    }

    final config = sherpa_onnx.AudioTaggingConfig(
      model: sherpa_onnx.AudioTaggingModelConfig(
        zipformer: sherpa_onnx.OfflineZipformerAudioTaggingModelConfig(
          model: modelPath,
        ),
        numThreads: 1,
        debug: false,
        provider: 'cpu',
      ),
      labels: labelsPath,
    );

    sherpa_onnx.initBindings();
    _tagger = sherpa_onnx.AudioTagging(config: config);
  }

  @override
  List<AudioClassifierResult> classify(Float32List samples, int sampleRate) {
    final stream = _tagger!.createStream();
    stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
    final events = _tagger!.compute(stream: stream, topK: 5);
    stream.free();
    return events.map((e) => AudioClassifierResult(e.name, e.prob)).toList();
  }

  @override
  void dispose() {
    _tagger?.free();
  }
}

/// Per-microphone recording + classification state. One of these exists
/// per input device found on the box; each owns its own AudioRecorder,
/// its own rolling sample buffer, and its own start/stop lifecycle —
/// entirely independent of the other mics. All sessions share the single
/// [classifier] instance passed in (see class-level note on why that's
/// safe) rather than loading the model once per mic.
class MicSession extends ChangeNotifier {
  MicSession({required this.device, required this.classifier});

  final InputDevice device;
  final AudioClassifier classifier;

  final AudioRecorder recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _micSub;
  final List<double> _buffer = [];

  RecordState recordState = RecordState.stop;
  String tagsText = 'Tap the mic to start listening';

  /// Called with (deviceLabel, tagsText) every time this mic's tags
  /// update — used to fan results out into the shared debug log.
  void Function(String micLabel, String text)? onTag;

  String get label => device.label.isNotEmpty ? device.label : device.id;

  static const int sampleRate = 16000;
  static const int windowSize = 16000 * 5; // 5s context
  static const int hopSize = 16000 * 5; // update every 5s
  static const double energyThreshold = 0.0008;
  static const double confThreshold = 0.30;

  Future<void> start() async {
    if (recordState != RecordState.stop) return;
    _buffer.clear();

    if (!await recorder.hasPermission()) return;

    final config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
      device: device, // pins this recorder to THIS mic specifically
    );
    final stream = await recorder.startStream(config);
    _micSub = stream.listen(_onAudioChunk);
    recordState = RecordState.record;
    notifyListeners();
  }

  Future<void> stop() async {
    await _micSub?.cancel();
    await recorder.stop();
    _buffer.clear();
    recordState = RecordState.stop;
    notifyListeners();
  }

  void _onAudioChunk(Uint8List data) {
    _buffer.addAll(convertBytesToFloat32(data));
    if (_buffer.length < windowSize) return;

    final raw = Float32List.fromList(_buffer.sublist(0, windowSize));
    _buffer.removeRange(0, hopSize); // slide forward



    final chunk = _applyGain(raw);
    _debugSaveWav(chunk, sampleRate);
    final results = classifier.classify(chunk, sampleRate);
    final confident = results.where((r) => r.prob >= confThreshold).toList();

    _setTags(
      confident.isEmpty
          ? '(no confident match)'
          : confident
          .map((r) => '${r.label} (${r.prob.toStringAsFixed(2)})')
          .join('\n'),
    );
  }

  void _setTags(String text) {
    tagsText = text;
    notifyListeners();
    onTag?.call(label, text);
  }

  // double _rms(Float32List samples) {
  //   double sum = 0;
  //   for (final s in samples) {
  //     sum += s * s;
  //   }
  //   return samples.isEmpty ? 0 : sum / samples.length;
  // }

  Future<void> _debugSaveWav(Float32List samples, int sampleRate) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/sherpa_debug_capture.wav');

    final pcm16 = Int16List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      pcm16[i] = (samples[i].clamp(-1.0, 1.0) * 32767).toInt();
    }

    final byteData = ByteData(44 + pcm16.length * 2);
    void writeStr(int off, String s) { for (var i = 0; i < s.length; i++) {
      byteData.setUint8(off + i, s.codeUnitAt(i));
    } }
    writeStr(0, 'RIFF');
    byteData.setUint32(4, 36 + pcm16.length * 2, Endian.little);
    writeStr(8, 'WAVE');
    writeStr(12, 'fmt ');
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little);
    byteData.setUint16(22, 1, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * 2, Endian.little);
    byteData.setUint16(32, 2, Endian.little);
    byteData.setUint16(34, 16, Endian.little);
    writeStr(36, 'data');
    byteData.setUint32(40, pcm16.length * 2, Endian.little);
    for (var i = 0; i < pcm16.length; i++) {
      byteData.setInt16(44 + i * 2, pcm16[i], Endian.little);
    }
    debugPrint('Saving wav at $sampleRate Hz');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    debugPrint('Saved debug capture to ${file.path}');
  }

  Float32List _applyGain(
      Float32List samples, {
        double targetRms = 0.12,
        double maxGain = 12.0,
      }) {
    double sumSq = 0;
    double maxAbs = 0;
    for (final s in samples) {
      sumSq += s * s;
      final a = s.abs();
      if (a > maxAbs) maxAbs = a;
    }
    final rms = samples.isEmpty ? 0 : math.sqrt(sumSq / samples.length);
    if (rms < 1e-6) return samples;

    double gain = targetRms / rms;
    gain = gain.clamp(1.0, maxGain);
    if (maxAbs * gain > 0.98) {
      gain = 0.98 / maxAbs;
    }

    final out = Float32List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      out[i] = (samples[i] * gain).clamp(-1.0, 1.0);
    }
    return out;
  }

  @override
  void dispose() {
    _micSub?.cancel();
    recorder.dispose();
    super.dispose();
  }
}

/// Real-time multi-mic audio tagging screen: one grid cell per input
/// device found on the box, each recording and classifying independently.
class LiveAudioTaggingScreen extends StatefulWidget {
  const LiveAudioTaggingScreen({super.key, required this.debugLog});
  final ValueNotifier<List<DebugLogEntry>> debugLog;

  @override
  State<LiveAudioTaggingScreen> createState() =>
      _LiveAudioTaggingScreenState();
}

class _LiveAudioTaggingScreenState extends State<LiveAudioTaggingScreen> {
  final AudioClassifier _classifier = SherpaZipformerTagger();
  List<MicSession> _sessions = [];
  bool _isLoading = true;
  String? _initError;

  static const int _maxDebugLogEntries = 200;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    try {
      await _classifier.init();
    } on ModelNotDownloadedException catch (e) {
      if (mounted) setState(() => _initError = e.toString());
      return;
    }

    final devices = await AudioRecorder().listInputDevices();
    if (!mounted) return;
    setState(() {
      _sessions = devices
          .map(
            (d) => MicSession(device: d, classifier: _classifier)
          ..onTag = _onMicTag,
      )
          .toList();
      _isLoading = false;
    });
  }

  void _onMicTag(String micLabel, String text) {
    final updated = [
      ...widget.debugLog.value,
      DebugLogEntry(timestamp: DateTime.now(), tagsText: '[$micLabel] $text'),
    ];
    if (updated.length > _maxDebugLogEntries) {
      updated.removeRange(0, updated.length - _maxDebugLogEntries);
    }
    widget.debugLog.value = updated;
  }

  @override
  void dispose() {
    for (final s in _sessions) {
      s.dispose();
    }
    _classifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Live Audio Tagging',
          style: AppFont.w700.getStyle(context, fontSize: 14),
        ),
        actions: [IconButton(onPressed: () => _setup(), icon: Icon(Icons.refresh,size: 36,color: Colors.green,))],
      ),
      drawer: AppDrawer(debugLogNotifier: widget.debugLog),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_initError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_initError!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sessions.isEmpty) {
      return const Center(child: Text('No input devices found'));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _crossAxisCountFor(_sessions.length),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio:1.5,
      ),
      itemCount: _sessions.length,
      itemBuilder: (context, index) => _MicGridCell(session: _sessions[index]),
    );
  }

  int _crossAxisCountFor(int count) {
    if (count <= 1) return 1;
    if (count <= 4) return 2;
    return 3;
  }
}

class _MicGridCell extends StatelessWidget {
  const _MicGridCell({required this.session});
  final MicSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final isRecording = session.recordState != RecordState.stop;
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: .min,
              children: [
                Expanded(
                  child: Text(
                    session.label,
                    style: AppFont.w700.getStyle(context, fontSize: 24),
                    softWrap: true,
                  ),
                ),
                const Divider(),
                const SizedBox(height: 16,),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      session.tagsText,
                      textAlign: TextAlign.center,
                      style: AppFont.w500.getStyle(context, fontSize: 30,color: Colors.red),
                      softWrap: true,
                    ),)),

                const SizedBox(height: 8),
                ClipOval(
                  child: Material(
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    child: InkWell(
                      onTap: () =>
                      isRecording ? session.stop() : session.start(),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: isRecording
                            ? const Icon(Icons.stop, color: Colors.red, size: 26)
                            : Icon(Icons.mic, color: theme.primaryColor, size: 26),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}