import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hodhd_ai/service/cache_helper.dart';

class MainCubit extends Cubit<MainState> {
  MainCubit({required this.defaultScheme}) : super(MainInitState()) {
    fontSizeMultiplier = CacheHelper.getData('fontSizeMultiplier') ?? 10;
    themeMode = CacheHelper.getData('themeMode') == 'dark' ? ThemeMode.dark : ThemeMode.light;

    selectedScheme = FlexScheme.values.firstWhere(
          (scheme) => scheme.toString() == CacheHelper.getData('themeScheme'),
      orElse: () => defaultScheme,
    );
  }
  FlexScheme defaultScheme;
  late FlexScheme selectedScheme;

  static MainCubit get(BuildContext context) => BlocProvider.of(context);
  double fontSizeMultiplier = 10;

  void updateThemeScheme(FlexScheme scheme) {
    selectedScheme = scheme;
    CacheHelper.saveData(key: 'themeScheme', value: scheme.toString());
    emit(ChangeThemeSchemeState());
  }

  void updateFontSize(double value) {
    fontSizeMultiplier = value;
    CacheHelper.saveData(key: 'fontSizeMultiplier', value: value);
    emit(MainFontSizeUpdated(fontSizeMultiplier));
  }

  ThemeMode themeMode = ThemeMode.light;

  void changeTheme() {
    if (themeMode == ThemeMode.light) {
      themeMode = ThemeMode.dark;
      CacheHelper.saveData(key: 'themeMode', value: 'dark');
      emit(ChangeThemeState());
    } else {
      themeMode = ThemeMode.light;
      CacheHelper.saveData(key: 'themeMode', value: 'light');
      emit(ChangeThemeState());
    }
  }

  void reloadState() {
    emit(ReloadState());
  }
}

abstract class MainState {}

class MainInitState extends MainState {}

class ReloadState extends MainState {}

class MainFontSizeUpdated extends MainState {
  final double fontSizeMultiplier;

  MainFontSizeUpdated(this.fontSizeMultiplier);
}

class ChangeThemeState extends MainState {}

class ChangeThemeSchemeState extends MainState {}