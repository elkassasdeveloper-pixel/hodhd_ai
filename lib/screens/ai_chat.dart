import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hodhd_ai/app_drawer.dart';
import 'package:hodhd_ai/cubits/ai_chat_cubit.dart';
import 'package:hodhd_ai/dash_chat.dart';
import 'package:hodhd_ai/extensions.dart';
import 'package:hodhd_ai/font.dart';
import 'package:hodhd_ai/screens/settings.dart';
import 'package:share_plus/share_plus.dart';

import 'debug_data_screen.dart';

class AiChatScreen extends StatelessWidget {
  const AiChatScreen({super.key,required this.debugLog});
  final ValueListenable<List<DebugLogEntry>> debugLog;
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _AiChatView(debugLog: debugLog),
    );
  }
}

class _AiChatView extends StatelessWidget {
  const _AiChatView({required this.debugLog});
  final ValueListenable<List<DebugLogEntry>> debugLog;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AiChatCubit>();

    return Scaffold(
      drawer: AppDrawer(debugLogNotifier: debugLog),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: BlocBuilder<AiChatCubit, AiChatState>(
          buildWhen: (previous, current) =>
          previous.isSearchActive != current.isSearchActive,
          builder: (context, state) {
            if (state.isSearchActive) {
              return AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => cubit.closeSearch(),
                ),
                title: TextField(
                  controller: cubit.searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search messages...',
                    border: InputBorder.none,
                  ),
                  onChanged: cubit.updateSearchQuery,
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      cubit.searchController.clear();
                      cubit.updateSearchQuery('');
                    },
                  ),
                ],
              );
            }
            return AppBar(
              title: Text(
                'AI Assistant',
                style: AppFont.w700.getStyle(context, fontSize: 14),
              ),
              centerTitle: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => cubit.openSearch(),
                ),
              ],
            );
          },
        ),
      ),
      body: BlocConsumer<AiChatCubit, AiChatState>(
        listenWhen: (previous, current) =>
        previous.pendingSharedFile != current.pendingSharedFile,
        listener: (context, state) {
          final pending = state.pendingSharedFile;
          if (pending == null) return;

          if (pending.kind == SharedFileKind.image) {
            _showImageCaptionDialog(context, pending.path);
          } else {
            final fileName = pending.path.split('/').last;
            _showAudioCaptionDialog(context, pending.path, fileName);
          }
          // Consume it so the dialog doesn't reopen on the next rebuild.
          cubit.clearPendingSharedFile();
        },
        builder: (context, state) {
          if (state.needsModelDownload) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_download_outlined,
                      size: 64,
                      color: context.colorS.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No AI model yet',
                      style: AppFont.w600.getStyle(
                        context,
                        fontSize: 20,
                        color: context.colorS.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "This app runs its AI model fully on your device, "
                          "so the model has to be downloaded once before you "
                          "can start chatting. It's a one-time download — "
                          "head to Settings to get it.",
                      textAlign: TextAlign.center,
                      style: AppFont.w400.getStyle(
                        context,
                        fontSize: 14,
                        color: context.colorS.secondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.settings),
                      label: const Text('Open Settings'),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BlocProvider.value(
                              value: cubit,
                              child: const SettingsPage(),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          }

          if (!state.modelReady) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    state.loadingText,
                    style: AppFont.w500.getStyle(context, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          }

          final allMessages = _withAudioButtons(context, state);
          final query = state.searchQuery.trim().toLowerCase();
          final visibleMessages = query.isEmpty
              ? allMessages
              : allMessages
              .where(
                (m) => (m.text ?? '').toLowerCase().contains(query),
          )
              .toList();

          if (query.isNotEmpty && visibleMessages.isEmpty) {
            return Center(
              child: Text('No messages found for "${state.searchQuery}"',style: AppFont.w600.getStyle(context, fontSize: 14),),
            );
          }

          return DashChat(
            textController: cubit.chatController,
            messages: visibleMessages,
            user: cubit.me,
            inputDisabled: state.isGenerating || state.isSearchActive,
            onSend: cubit.onSend,
            sendIcon: state.isGenerating ?  Center(child: CircularProgressIndicator()): null,
            onLongPressMessage: (message) =>
                _showMessageOptions(context, message),
            leading: [
              IconButton(
                icon: const Icon(Icons.attach_file),
                color: state.isGenerating
                    ? context.colorS.onSurface.withValues(alpha: 0.3)
                    : context.colorS.onSurface,
                onPressed: state.isGenerating
                    ? null
                    : () => _showAttachmentOptions(context),
              ),
            ],
            showTraillingBeforeSend: true,
            trailing: [
              GestureDetector(
                onTap: state.isGenerating
                    ? null
                    : () => state.isRecording
                    ? cubit.stopRecording()
                    : cubit.startRecording(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: state.isRecording
                        ? Colors.red
                        : context.colorS.primary.withValues(
                      alpha: state.isGenerating ? 0.05 : 0.1,
                    ),
                  ),
                  child: Icon(
                    state.isRecording ? Icons.fiber_manual_record : Icons.mic,
                    color: state.isGenerating
                        ? context.colorS.onSurface.withValues(alpha: 0.3)
                        : (state.isRecording
                        ? context.colorS.surface
                        : context.colorS.onSurface),
                  ),
                ),
              ),
            ],
            messageImageBuilder: (url, [ChatMessage? message]) {
              if (url != null && File(url).existsSync()) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: GestureDetector(
                    onTap: () => _openImageViewer(context, url),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(url),
                        width: 200,
                        height: 200,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          );
        },
      ),
    );
  }

  // ====================== ATTACHMENT SHEET ======================

  void _showAttachmentOptions(BuildContext context) {
    final cubit = context.read<AiChatCubit>();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            spacing: 8,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _attachmentOption(
                    context: sheetContext,
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final path = await cubit.pickCameraImage();
                      if (path != null && context.mounted) {
                        _showImageCaptionDialog(context, path);
                      }
                    },
                  ),
                  _attachmentOption(
                    context: sheetContext,
                    icon: Icons.photo_library,
                    label: 'Gallery',
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final path = await cubit.pickGalleryImage();
                      if (path != null && context.mounted) {
                        _showImageCaptionDialog(context, path);
                      }
                    },
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _attachmentOption(
                    context: sheetContext,
                    icon: Icons.audio_file,
                    label: 'Wav Audio File',
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final picked = await cubit.pickAudioFile();
                      if (picked != null && context.mounted) {
                        _showAudioCaptionDialog(
                          context,
                          picked.path,
                          picked.name,
                        );
                      }
                    },
                  ),
                  _attachmentOption(
                    context: sheetContext,
                    icon: Icons.data_object,
                    label: 'Extract to JSON',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      cubit.extractStoryToJson();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachmentOption({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Theme.of(
              context,
            ).primaryColor.withValues(alpha: 0.1),
            child: Icon(icon, color: Theme.of(context).primaryColor, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: AppFont.w400.getStyle(context, fontSize: 12)),
        ],
      ),
    );
  }

  // ====================== IMAGE CAPTION DIALOG ======================

  void _showImageCaptionDialog(BuildContext context, String imagePath) {
    final cubit = context.read<AiChatCubit>();
    final TextEditingController captionController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: cubit,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: BlocBuilder<AiChatCubit, AiChatState>(
                builder: (context, state) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(imagePath),
                        height: 250,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!state.visionReady)
                       Text(
                        'Note: vision adapter not active, only the caption text will be sent.',
                        style: AppFont.w400.getStyle(context, fontSize: 14,color: context.colorS.onSurfaceVariant),
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: captionController,
                      decoration: InputDecoration(
                        hintText: 'Add a caption or question (optional)...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      maxLines: 3,
                      minLines: 1,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child:  Text('Cancel',style: AppFont.w500.getStyle(context, fontSize: 14),),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(dialogContext);
                              cubit.sendImageMessage(
                                imagePath,
                                captionController.text,
                              );
                            },
                            child: Text('Send',style: AppFont.w500.getStyle(context, fontSize: 14),),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ====================== AUDIO CAPTION DIALOG ======================

  void _showAudioCaptionDialog(
      BuildContext context,
      String audioPath,
      String fileName,
      ) {
    final cubit = context.read<AiChatCubit>();
    final TextEditingController captionController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.audio_file,
                    size: 40,
                    color: Theme.of(dialogContext).primaryColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      fileName,
                      overflow: TextOverflow.ellipsis,
                      style: AppFont.w600.getStyle(context, fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: captionController,
                decoration: InputDecoration(
                  hintText: 'Add a caption or question (optional)...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                maxLines: 3,
                minLines: 1,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text('Cancel',style: AppFont.w500.getStyle(context, fontSize: 14),),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        cubit.sendAudioMessage(
                          audioPath,
                          fileName,
                          captionController.text,
                        );
                      },
                      child:  Text('Send',style: AppFont.w500.getStyle(context, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ====================== MESSAGE OPTIONS / DELETE ======================

  void _showMessageOptions(BuildContext context, ChatMessage message) {
    final cubit = context.read<AiChatCubit>();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.content_copy),
              title: const Text('Copy to clipboard'),
              titleTextStyle: AppFont.w500.getStyle(context, fontSize: 14,color: context.colorS.onSurface),
              onTap: () {
                Clipboard.setData(ClipboardData(text: message.text ?? ''));
                Navigator.pop(sheetContext);
                ScaffoldMessenger.of(context).showSnackBar(
                   SnackBar(content: Text('Copied to clipboard',style: AppFont.w500.getStyle(context, fontSize: 14),)),
                );
              },
            ),
          if(message.customProperties?['type'] == 'audio' || message.image != null)  ListTile(
              leading: const Icon(Icons.share),
              title:  Text('Share'),
              titleTextStyle: AppFont.w500.getStyle(context, fontSize: 14,color: context.colorS.onSurface),
              onTap: () {
                Navigator.pop(sheetContext);
                _shareMessage(message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title:  Text('Delete', style: AppFont.w500.getStyle(context, fontSize: 14,color: Colors.red)),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDeleteMessage(context, cubit, message);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Shares the message's underlying image/audio file if it has one,
  /// otherwise shares its text.
  void _shareMessage(ChatMessage message) {
    final audioPath = message.customProperties?['type'] == 'audio'
        ? (message.customProperties?['path']) as String?
        : null;

    if (message.image != null && File(message.image!).existsSync()) {
      SharePlus.instance.share(
        ShareParams(
          files: [XFile(message.image!)],
          text: (message.text?.isNotEmpty ?? false) ? message.text : null,
        ),
      );
    } else if (audioPath != null && File(audioPath).existsSync()) {
      SharePlus.instance.share(ShareParams(files: [XFile(audioPath)]));
    } else {
      SharePlus.instance.share(ShareParams(text: message.text ?? ''));
    }
  }

  Future<void> _confirmDeleteMessage(
      BuildContext context,
      AiChatCubit cubit,
      ChatMessage message,
      ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title:  Text('Delete Message'),
        titleTextStyle: AppFont.w700.getStyle(context, fontSize: 16,color: context.colorS.onSurface),
        content:  Text('Are you sure you want to delete this message?'),
        contentTextStyle: AppFont.w500.getStyle(context, fontSize: 14,color: context.colorS.onSurface),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child:  Text('Cancel',style: AppFont.w500.getStyle(context, fontSize: 14),),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child:  Text('Delete', style: AppFont.w500.getStyle(context, fontSize: 14,color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await cubit.deleteMessage(message);
    }
  }

  /// Opens an image message full-screen with pinch-to-zoom. Uses Flutter's
  /// built-in [InteractiveViewer] — no extra package needed for this part.
  void _openImageViewer(BuildContext context, String imagePath) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Image.file(File(imagePath)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Returns [state.messages] with a play/stop button attached to every
/// audio-type message (recorded, uploaded, or restored from history).
/// Recomputed on every rebuild, so it stays in sync with
/// `state.playingState` without the cubit needing to hold any widgets.
List<ChatMessage> _withAudioButtons(BuildContext context, AiChatState state) {
  return state.messages.map((m) {
    if (m.customProperties?['type'] != 'audio') return m;
    final path = m.customProperties!['path'] as String;
    return ChatMessage(
      id: m.id,
      text: m.text,
      user: m.user,
      userName: m.userName,
      createdAt: m.createdAt,
      image: m.image,
      customProperties: m.customProperties,
      buttons: [buildAudioPlayButton(context, path)],
    );
  }).toList();
}

/// Builds the play/stop button for an audio-type [ChatMessage] at [path].
Widget buildAudioPlayButton(BuildContext context, String path) {
  final cubit = context.read<AiChatCubit>();
  return BlocBuilder<AiChatCubit, AiChatState>(
    buildWhen: (previous, current) =>
    previous.playingState[path] != current.playingState[path],
    builder: (context, state) {
      final isPlaying = state.playingState[path] ?? false;
      return IconButton(
        icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
        color: context.colorS.onPrimary,
        onPressed: () => cubit.toggleAudioPlayback(path),
      );
    },
  );
}