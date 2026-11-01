import 'dart:io';

import 'package:flutter/material.dart';

Widget buildLocalCoverImage(
  String path, {
  required BoxFit fit,
  required Widget Function() fallback,
}) {
  return Image.file(
    File(path),
    fit: fit,
    errorBuilder: (_, _, _) => fallback(),
  );
}
