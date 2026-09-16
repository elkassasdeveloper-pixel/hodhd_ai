import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hodhd_ai/main_cubit.dart';

enum AppFont {
  w400(FontWeight.w400),
  w500(FontWeight.w500),
  w600(FontWeight.w600),
  w700(FontWeight.w700);

  final FontWeight fontWeight;

  const AppFont(this.fontWeight);

  TextStyle getStyle(
    BuildContext context, {
    required double fontSize,
    Color? color,
  }) {
    final fontSizeMultiplier = context.read<MainCubit>().fontSizeMultiplier;
    return TextStyle(
      fontSize: fontSize * (fontSizeMultiplier / 10),
      fontFamily: 'DINNext',
      color: color,
      fontWeight: fontWeight,
      fontFamilyFallback: const ['sans-serif']
    );
  }
}
