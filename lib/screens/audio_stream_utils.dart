import 'dart:typed_data';

/// Converts raw PCM16 bytes (as produced by `record`'s
/// `AudioEncoder.pcm16bits` stream) into normalized Float32 samples in
/// [-1.0, 1.0], the format sherpa_onnx expects.
Float32List convertBytesToFloat32(
    Uint8List bytes, [
      Endian endian = Endian.little,
    ]) {
  final values = Float32List(bytes.length ~/ 2);
  // Respects bytes' own offset/length (it may be a view into a larger
  // buffer), rather than assuming it starts at byte 0 of its buffer.
  final data = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
  for (var i = 0; i < bytes.length; i += 2) {
    final short = data.getInt16(i, endian);
    values[i ~/ 2] = short / 32768.0;
  }
  return values;
}