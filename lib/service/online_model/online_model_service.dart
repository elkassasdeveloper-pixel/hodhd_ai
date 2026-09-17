import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hodhd_ai/service/online_model/online_model_config.dart';

class OnlineModelService {
  final Dio _dio = Dio(BaseOptions(baseUrl: OnlineModelConfig.baseUrl));

  /// Streams response tokens from the online server's OpenAI-compatible
  /// chat completions endpoint. Yields incremental text deltas, same shape
  /// as what the local engine's token stream produces.
  Stream<String> generate(String userText, {int? maxTokens}) async* {
    debugPrint('[OnlineModel] POST ${OnlineModelConfig.baseUrl}${OnlineModelConfig.chatCompletions}');
    debugPrint('[OnlineModel] userText: "$userText" (maxTokens: $maxTokens)');
    Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        OnlineModelConfig.chatCompletions,
        data: {
          'messages': [
            {'role': 'user', 'content': userText},
          ],
          'stream': true,
          'max_tokens': ?maxTokens,
          'temperature': 0.1,
          'top_p': 0.95,
        },
        options: Options(responseType: ResponseType.stream),
      );
      debugPrint('[OnlineModel] response status: ${response.statusCode}');
    } catch (e, st) {
      debugPrint('[OnlineModel] REQUEST FAILED: $e');
      debugPrint('[OnlineModel] stack: $st');
      rethrow;
    }

    final stream = response.data!.stream.cast<List<int>>().transform(utf8.decoder);
    var buffer = '';
    var chunkCount = 0;
    var tokenCount = 0;
    var thinkingOpened = false;
    var thinkingClosed = false;

    await for (final chunk in stream) {
      chunkCount++;
      debugPrint('[OnlineModel] raw chunk #$chunkCount: ${chunk.replaceAll('\n', '\\n')}');
      buffer += chunk;
      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        if (!trimmed.startsWith('data:')) {
          debugPrint('[OnlineModel] non-data line, skipping: "$trimmed"');
          continue;
        }

        final payload = trimmed.substring(5).trim();
        if (payload == '[DONE]') {
          debugPrint('[OnlineModel] received [DONE], stream complete. Total tokens: $tokenCount');
          return;
        }
        if (payload.isEmpty) continue;

        try {
          final json = jsonDecode(payload) as Map<String, dynamic>;
          final choices = json['choices'] as List<dynamic>?;
          if (choices == null || choices.isEmpty) {
            debugPrint('[OnlineModel] no choices in payload: $payload');
            continue;
          }

          final delta = choices[0]['delta'] as Map<String, dynamic>?;
          if (delta == null) continue;
          final reasoning = delta['reasoning_content'] as String?;
          final content = delta['content'] as String?;

          if (reasoning != null && reasoning.isNotEmpty) {
            if (!thinkingOpened) {
              thinkingOpened = true;
              tokenCount++;
              yield '<think>$reasoning';
            } else {
              tokenCount++;
              yield reasoning;
            }
          }

          if (content != null && content.isNotEmpty) {
            if (thinkingOpened && !thinkingClosed) {
              thinkingClosed = true;
              tokenCount++;
              yield '</think>$content';
            } else {
            tokenCount++;
            debugPrint('[OnlineModel] token #$tokenCount: "$content"');
            yield content;}
          } else {
            debugPrint('[OnlineModel] delta with no content: $delta');
          }
        } catch (e) {
          debugPrint('[OnlineModel] FAILED to parse payload: "$payload" — $e');
        }
      }
    }

    debugPrint('[OnlineModel] stream ended without [DONE] marker. Total tokens: $tokenCount');
  }
}