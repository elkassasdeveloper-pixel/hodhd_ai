import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hodhd_ai/cubits/ai_chat_cubit.dart';
import 'package:hodhd_ai/main.dart';
import 'package:hodhd_ai/screens/debug_data_screen.dart';
import 'package:hodhd_ai/screens/settings.dart';
import 'extensions.dart';
import 'font.dart';

/// Single drawer shared by every tab in MainTabScreen, so "Settings" and
/// "Debug Data" are reachable the same way regardless of which tab is
/// active. Needs an AiChatCubit above it in the tree (provided at
/// MainTabScreen level) since Settings requires it.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.debugLogNotifier});

  final ValueListenable<List<DebugLogEntry>> debugLogNotifier;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AiChatCubit>();

    return Drawer(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: BoxDecoration(color: context.colorS.primary),
                  child: Text(
                    'Menu',
                    style: AppFont.w600.getStyle(context, fontSize: 24, color: context.colorS.onPrimary),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: Text('Settings', style: AppFont.w500.getStyle(context, fontSize: 14)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BlocProvider.value(value: cubit, child: const SettingsPage()),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: Text('Debug Data',style: AppFont.w500.getStyle(context, fontSize: 14)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => DebugDataScreen(logNotifier: debugLogNotifier)),
                    );
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 20),
          Text("Version : $version", style: AppFont.w700.getStyle(context, fontSize: 18)),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}