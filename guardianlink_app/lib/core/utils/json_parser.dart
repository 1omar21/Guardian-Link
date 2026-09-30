import 'dart:convert';
import 'package:flutter/foundation.dart';

class JsonParser {
  /// Decodes JSON string on a background isolate to avoid blocking main thread
  static Future<dynamic> parseJson(String encodedJson) async {
    return compute(_decode, encodedJson);
  }

  /// Private function to be run on isolate
  static dynamic _decode(String encodedJson) {
    return jsonDecode(encodedJson);
  }
}
