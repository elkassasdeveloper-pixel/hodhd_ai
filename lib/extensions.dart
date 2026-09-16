import 'package:flutter/material.dart';

extension BuildContextExt on BuildContext {
  ColorScheme get colorS {
    return Theme.of(this).colorScheme;
  }

  double get sizeW {
    return MediaQuery.of(this).size.width;
  }

  double get sizeH {
    return MediaQuery.of(this).size.height;
  }

  bool get isMobile {
    return sizeW < 600;
  }

  bool get isTablet {
    return sizeW >= 600 && sizeW < 1024;
  }

  bool get isDesktop {
    return sizeW >= 1024;
  }
}

extension ColorExt on Color {
  ColorFilter get svgColor {
    return ColorFilter.mode(this, BlendMode.srcIn);
  }
}

extension TextEditingControllerExt on TextEditingController {
  void selectAll() {
    if (text.isEmpty) return;
    selection = TextSelection(baseOffset: 0, extentOffset: text.length);
  }
}

extension Ex on double {
  double toPrecision(int n) => double.parse(toStringAsFixed(n));
}

extension MoveElement<T> on List<T> {
  void move(int from, int to) {
    RangeError.checkValidIndex(from, this, "from", length);
    RangeError.checkValidIndex(to, this, "to", length);
    var element = this[from];
    if (from < to) {
      setRange(from, to, this, from + 1);
    } else {
      setRange(to + 1, from + 1, this, to);
    }
    this[to] = element;
  }
}
