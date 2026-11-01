import 'package:flutter/material.dart';

Widget buildLocalCoverImage(
  String path, {
  required BoxFit fit,
  required Widget Function() fallback,
}) {
  return fallback();
}
