import 'package:flutter/foundation.dart';

dynamic getValue(String type, dynamic value, {String caller = '', required String initialValue}) {
  try {
// If value is null, return initialValue according to type
    if (value == null) {
      if (type == "int") {
        return int.tryParse(initialValue) ?? 0;
      } else if (type == "double") {
        return double.tryParse(initialValue) ?? 0.0;
      } else if (type == "bool") {
        return initialValue.toLowerCase() == 'true';
      } else {
        return initialValue;
      }
    }

// If value is not null, validate type
    if ((type == 'int' && value is int) || (type == 'bool' && value is bool) || (type == 'double' && value is double)) {
      return value;
    } else if (type == 'bool' && value is String) {
      return value.toLowerCase() == 'true';
    } else if (type == 'int' && value is String) {
      return int.tryParse(value) ?? 0;
    } else if (type == 'double' && value is String) {
      return double.tryParse(value) ?? 0.0;
    } else if (type == 'String' && value is String) {
      return value.isEmpty ? initialValue : value;
    } else if (type == "double" && value is int) {
      return value.toDouble();
    } else {
      myPrintX('caller:$caller type:$type and valueType:${value.runtimeType.toString()} value:$value');
      return initialValue;
    }
  } catch (ex) {
    myPrintX(ex.toString());
  }
  return initialValue;
}

void myPrintX(String string) {
  if (kDebugMode) print(string);
}
