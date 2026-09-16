import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hodhd_ai/cubits/ai_chat_cubit.dart';
import 'package:hodhd_ai/extensions.dart';
import 'package:hodhd_ai/font.dart';
import 'package:hodhd_ai/main_cubit.dart';
import 'package:hodhd_ai/service/chat_database.dart';
import 'package:hodhd_ai/service/ai_model_config.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MainCubit, MainState>(
      builder: (context, state) {
        final cubit = context.read<MainCubit>();
        return Scaffold(
          appBar: AppBar(title: Text('Settings',style: AppFont.w600.getStyle(context, fontSize: 14),), centerTitle: true),
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "choose_color_theme",
                    style: AppFont.w400.getStyle(
                      context,
                      fontSize: 18,
                      color: context.colorS.primary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: FlexScheme.values.length,
                      itemBuilder: (context, index) {
                        final scheme = FlexScheme.values[index];
                        final colors = FlexColorScheme.light(
                          scheme: scheme,
                        ).toTheme.colorScheme;

                        return InkWell(
                          onTap: () {
                            cubit.updateThemeScheme(scheme);
                          },
                          child: Tooltip(
                            message: scheme.name,
                            child: Column(
                              children: [
                                Container(
                                  height: 50,
                                  width: 50,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: colors.primary,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: cubit.selectedScheme == scheme
                                          ? context.colorS.primary
                                          : context.colorS.inversePrimary,
                                      width: cubit.selectedScheme == scheme
                                          ? 3
                                          : 1,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.star,
                                  color: scheme == cubit.selectedScheme
                                      ? FlexColor.goldDarkPrimary
                                      : scheme == cubit.defaultScheme
                                      ? context.colorS.inverseSurface
                                      : Colors.transparent,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'control_size',
                    style: AppFont.w400.getStyle(
                      context,
                      fontSize: 16,
                      color: context.colorS.primary,
                    ),
                  ),
                  Slider(
                    value: cubit.fontSizeMultiplier,
                    min: 5,
                    max: 20,
                    divisions: 15,
                    label: cubit.fontSizeMultiplier.toStringAsFixed(0),
                    onChanged: (value) async {
                      cubit.updateFontSize(value);
                    },
                  ),
                  const SizedBox(height: 24),
                  SwitchListTile(
                    value: cubit.themeMode == ThemeMode.dark,
                    onChanged: (value) => cubit.changeTheme(),
                    title: Text(
                      "theme_mode",
                      style: AppFont.w400.getStyle(
                        context,
                        fontSize: 22,
                        color: context.colorS.primary,
                      ),
                    ),
                    subtitle: Text(
                      cubit.themeMode == ThemeMode.dark
                          ? "dark_mode"
                          : "light_mode",
                      style: AppFont.w400.getStyle(
                        context,
                        fontSize: 16,
                        color: context.colorS.secondary,
                      ),
                    ),
                    thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
                      if (cubit.themeMode == ThemeMode.dark) {
                        return Icon(
                          Icons.dark_mode,
                          color: context.colorS.onPrimaryContainer,
                        );
                      } else {
                        return Icon(
                          Icons.light_mode,
                          color: context.colorS.onPrimaryContainer,
                        );
                      }
                    }),
                  ),
                  const SizedBox(height: 24),
                  const _ModelDownloadSection(),
                  const SizedBox(height: 24),
                   _ModelNamesSection(),
                  const SizedBox(height: 8),
                   _ModelCapabilitiesSection(),
                  const SizedBox(height: 24),
                   _ModelLibrarySection(),
                   _LoraScaleSection(),
                   _GenerationSettingsSection(),
                  _AudioProcessingModeSection(),
                  ListTile(
                    leading: const Icon(Icons.delete_forever, color: Colors.red),
                    title: Text('Clear Chat History',style: AppFont.w500.getStyle(context, fontSize: 14),),
                    onTap: () => _confirmClearHistory(context)
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmClearHistory(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Clear Chat History',style: AppFont.w700.getStyle(context, fontSize: 16),),
        content:  Text(
          'This will permanently delete all messages. Are you sure?',
          style: AppFont.w500.getStyle(context, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child:  Text('Cancel',
              style: AppFont.w500.getStyle(context, fontSize: 14),),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child:  Text('Clear',
              style: AppFont.w500.getStyle(context, fontSize: 14,color: Colors.red),),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    // Prefer clearing through AiChatCubit so its in-memory
    // `state.messages` empties immediately too — hitting ChatDatabase
    // directly leaves stale messages on screen until the app restarts
    // and reloads from disk.
    AiChatCubit? aiChatCubit;
    try {
      aiChatCubit = context.read<AiChatCubit>();
    } catch (_) {
      aiChatCubit = null;
    }

    if (aiChatCubit != null) {
      await aiChatCubit.clearHistory();
    } else {
      await ChatDatabase().clearAll();
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat history cleared')),
      );
    }
  }
}

/// Lists every downloadable asset (AiModelConfig.allAssets) with its
/// download status, a progress bar while downloading, and a Download
/// button. The main model is marked "Required" — everything else is
/// optional and degrades gracefully in the cubit if skipped.
class _ModelDownloadSection extends StatelessWidget {
  const _ModelDownloadSection();

  @override
  Widget build(BuildContext context) {
    AiChatCubit aiChatCubit;
    try {
      aiChatCubit = context.read<AiChatCubit>();
    } catch (_) {
      return const SizedBox.shrink();
    }

    return BlocBuilder<AiChatCubit, AiChatState>(
      bloc: aiChatCubit,
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'model_downloads',
              style: AppFont.w400.getStyle(
                context,
                fontSize: 16,
                color: context.colorS.primary,
              ),
            ),
            const SizedBox(height: 8),
            ...AiModelConfig.allAssets.map(
                  (asset) => _DownloadRow(asset: asset, state: state),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({required this.asset, required this.state});

  final DownloadableAsset asset;
  final AiChatState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AiChatCubit>();
    final isDownloaded = state.downloadedAssets.contains(asset.fileName);
    final progress = state.downloadProgress[asset.fileName];
    final isDownloading = progress != null;
    final anyDownloadInProgress = state.downloadingFile != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        asset.label,
                        overflow: TextOverflow.ellipsis,
                        style: AppFont.w400.getStyle(
                          context,
                          fontSize: 14,
                          color: context.colorS.primary,
                        ),
                      ),
                    ),
                    if (asset.required) ...[
                      const SizedBox(width: 6),
                      Text(
                        '(required)',
                        style: AppFont.w400.getStyle(
                          context,
                          fontSize: 11,
                          color: context.colorS.secondary,
                        ),
                      ),
                    ],
                  ],
                ),
                if (isDownloading)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: LinearProgressIndicator(value: progress),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isDownloaded && !isDownloading)
            Icon(Icons.check_circle, color: Colors.green, size: 20)
          else
            SizedBox(
              height: 32,
              child: OutlinedButton(
                onPressed: anyDownloadInProgress
                    ? null
                    : () => _download(context, cubit),
                child: Text(
                  isDownloading
                      ? '${(progress * 100).toStringAsFixed(0)}%'
                      : 'Download',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _download(BuildContext context, AiChatCubit cubit) async {
    final error = await cubit.downloadAsset(asset);
    if (!context.mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

/// Displays the currently *loaded* model / LoRA / ONNX asset names —
/// i.e. what's actually running in this session
/// (`AiChatState.activeModelName`/`activeLoraName`, set once in
/// `_loadModel()`), not necessarily what's selected in the Model Library
/// section below, since a new selection there only takes effect after an
/// app restart. If they differ, a "pending restart" note is shown.
class _ModelNamesSection extends StatelessWidget {
  const _ModelNamesSection();

  @override
  Widget build(BuildContext context) {
    AiChatCubit? aiChatCubit;
    try {
      aiChatCubit = context.read<AiChatCubit>();
    } catch (_) {
      aiChatCubit = null;
    }

    if (aiChatCubit == null) {
      // No cubit in scope — fall back to the bundled config's names.
      return _ModelNamesBody(
        modelName: AiModelConfig.modelName,
        loraName: AiModelConfig.loraName,
        pendingRestart: false,
      );
    }

    return BlocBuilder<AiChatCubit, AiChatState>(
      bloc: aiChatCubit,
      builder: (context, state) {
        final pendingRestart =
            state.selectedModelFile != state.activeModelSelection ||
                state.selectedLoraFile != state.activeLoraSelection;

        return _ModelNamesBody(
          modelName: state.activeModelName,
          loraName: state.activeLoraName,
          pendingRestart: pendingRestart,
        );
      },
    );
  }
}

class _ModelNamesBody extends StatelessWidget {
  const _ModelNamesBody({
    required this.modelName,
    required this.loraName,
    required this.pendingRestart,
  });

  final String modelName;
  final String loraName;
  final bool pendingRestart;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'active_models',
          style: AppFont.w400.getStyle(
            context,
            fontSize: 16,
            color: context.colorS.primary,
          ),
        ),
        const SizedBox(height: 8),
        _ModelNameRow(label: 'Model', name: modelName),
        _ModelNameRow(label: 'LoRA', name: loraName),
        _ModelNameRow(
          label: 'Speech recognition (ONNX)',
          name: '${AiModelConfig.asrEncoderName} / ${AiModelConfig.asrDecoderName}',
        ),
        _ModelNameRow(
          label: 'Audio tagging (ONNX)',
          name: AiModelConfig.taggingModelName,
        ),
        if (pendingRestart)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'A new model/LoRA selection is pending — restart the app to load it.',
              style: AppFont.w400.getStyle(
                context,
                fontSize: 12,
                color: context.colorS.secondary,
              ),
            ),
          ),
      ],
    );
  }
}

class _ModelNameRow extends StatelessWidget {
  const _ModelNameRow({required this.label, required this.name});

  final String label;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        spacing: 8,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppFont.w400.getStyle(
                    context,
                    fontSize: 14,
                    color: context.colorS.secondary,
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: AppFont.w600.getStyle(
                    context,
                    fontSize: 14,
                    color: context.colorS.primary,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16,)
        ],
      ),
    );
  }
}

/// Read-only "supports vision" / "supports audio" indicators, reported by
/// the loaded model+mmproj combo at load time (`AiChatState.visionReady`
/// and `AiChatState.supportsAudio`).
class _ModelCapabilitiesSection extends StatelessWidget {
  const _ModelCapabilitiesSection();

  @override
  Widget build(BuildContext context) {
    AiChatCubit aiChatCubit;
    try {
      aiChatCubit = context.read<AiChatCubit>();
    } catch (_) {
      return const SizedBox.shrink();
    }

    return BlocBuilder<AiChatCubit, AiChatState>(
      bloc: aiChatCubit,
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CapabilityRow(
              label: 'Supports Vision',
              supported: state.visionReady,
            ),
            _CapabilityRow(
              label: 'Supports Audio',
              supported: state.supportsAudio,
            ),
          ],
        );
      },
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({required this.label, required this.supported});

  final String label;
  final bool supported;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppFont.w400.getStyle(
                context,
                fontSize: 14,
                color: context.colorS.secondary,
              ),
            ),
          ),
          Icon(
            supported ? Icons.check_circle : Icons.cancel,
            size: 24,
            color: supported ? Colors.green : context.colorS.secondary,
          ),
        ],
      ),
    );
  }
}

/// "Enable Thinking" switch + "Max Tokens" slider. Both are read/written
/// directly on [AiChatCubit] (persisted + applied immediately to the next
/// generation — see [AiChatCubit.setEnableThinking] /
/// [AiChatCubit.setMaxTokens]).
class _GenerationSettingsSection extends StatelessWidget {
  const _GenerationSettingsSection();

  @override
  Widget build(BuildContext context) {
    AiChatCubit aiChatCubit;
    try {
      aiChatCubit = context.read<AiChatCubit>();
    } catch (_) {
      return const SizedBox.shrink();
    }

    return BlocBuilder<AiChatCubit, AiChatState>(
      bloc: aiChatCubit,
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: state.enableThinking,
              onChanged: (value) => aiChatCubit.setEnableThinking(value),
              title: Text(
                'enable_thinking',
                style: AppFont.w400.getStyle(
                  context,
                  fontSize: 16,
                  color: context.colorS.primary,
                ),
              ),
              subtitle: Text(
                state.enableThinking
                    ? 'Model may reason before answering.'
                    : 'Model answers directly, no reasoning step.',
                style: AppFont.w400.getStyle(
                  context,
                  fontSize: 12,
                  color: context.colorS.secondary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'max_tokens',
              style: AppFont.w400.getStyle(
                context,
                fontSize: 16,
                color: context.colorS.primary,
              ),
            ),
            SizedBox(height: 24,),
            Slider(
              value: state.maxTokens.toDouble().clamp(128, 4096),
              min: 128,
              max: 4096,
              divisions: 31,
              showValueIndicator: ShowValueIndicator.alwaysVisible,
              label: '${state.maxTokens}',
              onChanged: (value) =>
                  aiChatCubit.setMaxTokens(value.round()),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

/// Switch between transcribing audio messages (ASR) and tagging/identifying
/// sounds instead — an explicit user choice via
/// [AiChatCubit.setUseAudioTranscription], replacing the old automatic
/// "try transcription, fall back to tagging if empty" behavior. Applied to
/// the next audio message sent immediately.
class _AudioProcessingModeSection extends StatelessWidget {
  const _AudioProcessingModeSection();

  @override
  Widget build(BuildContext context) {
    AiChatCubit aiChatCubit;
    try {
      aiChatCubit = context.read<AiChatCubit>();
    } catch (_) {
      return const SizedBox.shrink();
    }

    return BlocBuilder<AiChatCubit, AiChatState>(
      bloc: aiChatCubit,
      builder: (context, state) {
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: state.useAudioTranscription,
          onChanged: (value) => aiChatCubit.setUseAudioTranscription(value),
          title: Text(
            'audio_processing_mode',
            style: AppFont.w400.getStyle(
              context,
              fontSize: 16,
              color: context.colorS.primary,
            ),
          ),
          subtitle: Text(
            state.useAudioTranscription
                ? 'Transcribing speech to text.'
                : 'Tagging/identifying sounds instead of transcribing.',
            style: AppFont.w400.getStyle(
              context,
              fontSize: 12,
              color: context.colorS.secondary,
            ),
          ),
        );
      },
    );
  }
}

/// Lets you pick between the bundled model/LoRA and any extra `.gguf`
/// files adb-pushed into `<app docs dir>/models/` or `.../loras/`.
/// Selecting a different one only saves the choice (via
/// [AiChatCubit.selectModelFile] / [AiChatCubit.selectLoraFile]) — it
/// takes effect on the next app restart, not live.
class _ModelLibrarySection extends StatelessWidget {
  const _ModelLibrarySection();

  @override
  Widget build(BuildContext context) {
    AiChatCubit aiChatCubit;
    try {
      aiChatCubit = context.read<AiChatCubit>();
    } catch (_) {
      return const SizedBox.shrink();
    }

    return BlocBuilder<AiChatCubit, AiChatState>(
      bloc: aiChatCubit,
      builder: (context, state) {
        final modelOptions = [
          kDefaultModelSelection,
          ...state.availableModelFiles,
        ];
        final loraOptions = [
          kDefaultModelSelection,
          kNoLoraSelection,
          ...state.availableLoraFiles,
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'model_library',
                    style: AppFont.w400.getStyle(
                      context,
                      fontSize: 16,
                      color: context.colorS.primary,
                    ),
                  ),
                ),
            ]),
            Text(
              'Restart the app after changing model or LoRA for it to take effect.',
              style: AppFont.w400.getStyle(
                context,
                fontSize: 12,
                color: context.colorS.secondary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.file_open, size: 18),
                    label:  Text('Import model',style: AppFont.w500.getStyle(context, fontSize: 14),),
                    onPressed: state.isImportingLibraryFile
                        ? null
                        : () => _importFile(context, aiChatCubit, false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.file_open, size: 18),
                    label:  Text('Import LoRA',style: AppFont.w500.getStyle(context, fontSize: 14),),
                    onPressed: state.isImportingLibraryFile
                        ? null
                        : () => _importFile(context, aiChatCubit, true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ModelPickerRow(
              label: 'Model',
              value: state.selectedModelFile,
              options: modelOptions,
              onChanged: aiChatCubit.selectModelFile,
            ),
            const SizedBox(height: 8),
            _ModelPickerRow(
              label: 'LoRA',
              value: state.selectedLoraFile,
              options: loraOptions,
              onChanged: aiChatCubit.selectLoraFile,
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Future<void> _importFile(
      BuildContext context,
      AiChatCubit aiChatCubit,
      bool isLora,
      ) async {
    final error = await aiChatCubit.importModelFile(isLora: isLora);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? '${isLora ? 'LoRA' : 'Model'} imported.'),
      ),
    );
  }
}

class _ModelPickerRow extends StatelessWidget {
  const _ModelPickerRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  static String _displayName(String fileName) {
    if (fileName == kDefaultModelSelection) return 'Default (bundled)';
    if (fileName == kNoLoraSelection) return 'None';
    return fileName;
  }

  @override
  Widget build(BuildContext context) {
    // Guard against a stale selection that isn't in `options` yet (e.g.
    // right after a file was deleted, before the fallback in _loadModel
    // runs again on next restart) — avoids a DropdownButton assertion.
    final safeValue = options.contains(value) ? value : options.first;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppFont.w400.getStyle(
                  context,
                  fontSize: 14,
                  color: context.colorS.secondary,
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                value: safeValue,
                items: options
                    .map(
                      (option) => DropdownMenuItem(
                    value: option,
                    child: Text(
                      _displayName(option),
                      overflow: TextOverflow.ellipsis,style: AppFont.w500.getStyle(context, fontSize: 14),
                    ),
                  ),
                )
                    .toList(),
                onChanged: (option) {
                  if (option != null) onChanged(option);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// LoRA adapter strength control. Reads/writes [AiChatCubit] directly.
///
/// Guarded with a [Builder] + try/catch so this section quietly disappears
/// (instead of crashing the whole Settings page) if `SettingsPage` is ever
/// opened somewhere that doesn't have an `AiChatCubit` provided above it —
/// e.g. if it's reused as a standalone route elsewhere in the app.
class _LoraScaleSection extends StatelessWidget {
  const _LoraScaleSection();

  @override
  Widget build(BuildContext context) {
    AiChatCubit aiChatCubit;
    try {
      aiChatCubit = context.read<AiChatCubit>();
    } catch (_) {
      return const SizedBox.shrink();
    }

    return BlocBuilder<AiChatCubit, AiChatState>(
      bloc: aiChatCubit,
      builder: (context, aiChatState) {
        final enabled = aiChatState.modelReady && aiChatState.loraReady;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'lora_adapter_strength',
              style: AppFont.w400.getStyle(
                context,
                fontSize: 16,
                color: context.colorS.primary,
              ),
            ),
            SizedBox(height: 24,),
            Slider(
              value: aiChatState.loraScale.clamp(0.0, 2.0),
              min: 0.0,
              max: 2.0,
              divisions: 20,
              label: aiChatState.loraScale.toStringAsFixed(2),
              showValueIndicator: ShowValueIndicator.alwaysVisible,
              onChanged: enabled
                  ? (value) => aiChatCubit.setLoraScale(value)
                  : null,
            ),
            if (!enabled)
              Text(
                aiChatState.modelReady
                    ? 'No LoRA adapter loaded.'
                    : 'Waiting for the model to finish loading...',
                style: AppFont.w400.getStyle(
                  context,
                  fontSize: 12,
                  color: context.colorS.secondary,
                ),
              ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}