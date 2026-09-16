import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hodhd_ai/main_cubit.dart';
import 'package:hodhd_ai/screens/main_tab_screen.dart';
import 'package:hodhd_ai/service/cache_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  await CacheHelper.init();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => MainCubit(defaultScheme: FlexScheme.brandBlue),
      child: BlocBuilder<MainCubit, MainState>(
        builder: (context, state) {
          final cubit = context.read<MainCubit>();
          return MaterialApp(
            title: "Hodhd AI",
            themeMode: cubit.themeMode,
            debugShowCheckedModeBanner: false,
            home: MainTabScreen(),
            darkTheme: FlexColorScheme.dark(
              fontFamily: 'DINNext',
              fontFamilyFallback: const ['sans-serif'],
              scheme: cubit.selectedScheme,
            ).toTheme,
            theme: FlexColorScheme.light(
              fontFamily: 'DINNext',
              fontFamilyFallback: const ['sans-serif'],
              scheme: cubit.selectedScheme,
            ).toTheme,
          );
        },
      ),
    );
  }
}

int version = 6;
