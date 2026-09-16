import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hodhd_ai/app_drawer.dart';
import 'package:hodhd_ai/cubits/ai_chat_cubit.dart';
import 'ai_chat.dart';
import 'debug_data_screen.dart';
import 'live_audio_tagging_screen.dart';

/// Root screen: single BlocProvider<AiChatCubit> + single Drawer shared by
/// both tabs (moved up from each screen owning its own). IndexedStack keeps
/// both tabs' state alive when switching, same as before.
class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  int _index = 0;

  // Lifted from LiveAudioTaggingScreen so AppDrawer's "Debug Data" entry
  // works identically from either tab, not just from the tagging tab.
  final ValueNotifier<List<DebugLogEntry>> _debugLog = ValueNotifier(
    <DebugLogEntry>[],
  );

  @override
  void dispose() {
    _debugLog.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AiChatCubit(),
      child: Builder(
        builder: (context) => Scaffold(
          drawer: AppDrawer(debugLogNotifier: _debugLog),
          body: IndexedStack(
            index: _index,
            children: [
              AiChatScreen(debugLog: _debugLog),
              LiveAudioTaggingScreen(debugLog: _debugLog),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline),
                selectedIcon: Icon(Icons.chat_bubble),
                label: 'Chat',
              ),
              NavigationDestination(
                icon: Icon(Icons.graphic_eq_outlined),
                selectedIcon: Icon(Icons.graphic_eq),
                label: 'Live Tagging',
              ),
            ],
          ),
        ),
      ),
    );
  }
}