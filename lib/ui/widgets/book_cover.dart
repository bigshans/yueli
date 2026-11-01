import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/database.dart';
import 'local_cover_image.dart';

/// 统一的书籍封面：本地上传 → 网络链接 → 首字渐变占位图。
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.book,
    this.width = 56,
    this.height = 80,
    this.borderRadius = 8,
  });

  final Book book;
  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return CoverImage(
      coverPath: book.coverPath,
      coverUrl: book.coverUrl,
      title: book.title,
      width: width,
      height: height,
      borderRadius: borderRadius,
    );
  }
}

/// 可独立使用的封面预览，编辑页也会用到。
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    this.coverPath,
    this.coverUrl,
    required this.title,
    this.width = 56,
    this.height = 80,
    this.borderRadius = 8,
  });

  final String? coverPath;
  final String? coverUrl;
  final String title;
  final double width;
  final double height;
  final double borderRadius;

  Widget _placeholder() =>
      _Placeholder(title: title, width: width, height: height);

  Widget _fallbackCover(String? url) {
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, _) => _placeholder(),
        errorWidget: (_, _, _) => _placeholder(),
      );
    }
    return _placeholder();
  }

  @override
  Widget build(BuildContext context) {
    final path = coverPath?.trim();
    final url = coverUrl?.trim();

    Widget child;
    if (path != null && path.isNotEmpty) {
      if (path.startsWith('data:image')) {
        final comma = path.indexOf(',');
        if (comma > 0) {
          try {
            child = Image.memory(
              base64Decode(path.substring(comma + 1)),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fallbackCover(url),
            );
          } catch (_) {
            child = _placeholder();
          }
        } else {
          child = _placeholder();
        }
      } else {
        child = buildLocalCoverImage(
          path,
          fit: BoxFit.cover,
          fallback: () => _fallbackCover(url),
        );
      }
    } else if (url != null && url.isNotEmpty) {
      child = CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, _) => _placeholder(),
        errorWidget: (_, _, _) => _placeholder(),
      );
    } else {
      child = _placeholder();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(width: width, height: height, child: child),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.title,
    required this.width,
    required this.height,
  });

  final String title;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = title.trim().isEmpty ? '书' : title.trim().characters.first;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.secondaryContainer],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: width * 0.42,
          fontWeight: FontWeight.w700,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
