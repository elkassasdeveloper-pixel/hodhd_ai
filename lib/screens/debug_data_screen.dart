import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hodhd_ai/font.dart';

/// One classification cycle's result, with when it happened.
class DebugLogEntry {
  const DebugLogEntry({required this.timestamp, required this.tagsText});

  final DateTime timestamp;
  final String tagsText;
}

/// Shows every classification result from [LiveAudioTaggingScreen] as a
/// running log, newest first. Reactive via [logNotifier] — stays updated
/// even if tagging is still running underneath while this screen is open
/// (pushing a route doesn't stop the mic stream in the screen below it).
class DebugDataScreen extends StatelessWidget {
  const DebugDataScreen({super.key, required this.logNotifier});

  final ValueListenable<List<DebugLogEntry>> logNotifier;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Debug Data')),
      body: ValueListenableBuilder<List<DebugLogEntry>>(
        valueListenable: logNotifier,
        builder: (context, entries, _) {
          if (entries.isEmpty) {
            return Center(
              child: Text('No classification results yet.',style: AppFont.w500.getStyle(context, fontSize: 30)),
            );
          }

          // Newest first.
          final reversed = entries.reversed.toList();

          return ListView.separated(
            itemCount: reversed.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = reversed[index];
              return ListTile(
                dense: true,
                title: Text(entry.tagsText,style: AppFont.w500.getStyle(context, fontSize: 30),),
                subtitle: Text(_formatTime(entry.timestamp),style: AppFont.w500.getStyle(context, fontSize: 24)),
              );
            },
          );
        },
      ),
    );
  }

  String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}