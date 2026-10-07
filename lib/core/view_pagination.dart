import 'dart:convert';

/// Cursor and page helpers for model-facing read models.
///
/// Cursors encode the collection, offset, and optional search scope. They are
/// opaque to callers, but remain deterministic so a model can pass them back
/// without needing to understand the underlying storage.
class ViewCursor {
  const ViewCursor({
    required this.collection,
    required this.offset,
    this.scope,
  });

  final String collection;
  final int offset;
  final String? scope;

  static String encode(String collection, int offset, {String? scope}) {
    final trimmedScope = scope?.trim();
    if (trimmedScope == null || trimmedScope.isEmpty) {
      return '$collection:$offset';
    }
    final encoded = base64Url.encode(utf8.encode(trimmedScope));
    return '$collection:$offset:$encoded';
  }

  static ViewCursor decode(String raw) {
    final value = raw.trim();
    final parts = value.split(':');
    if (parts.length < 2 || parts.length > 3 || parts[0].isEmpty) {
      throw const FormatException(
        'A view cursor must contain a collection and offset.',
      );
    }
    final collection = parts[0];
    final offset = int.tryParse(parts[1]);
    if (offset == null || offset < 0) {
      throw const FormatException(
        'A view cursor offset must be a non-negative integer.',
      );
    }
    String? scope;
    if (parts.length == 3) {
      if (parts[2].isEmpty) {
        throw const FormatException('A view cursor scope cannot be empty.');
      }
      try {
        scope = utf8.decode(base64Url.decode(parts[2]));
      } on FormatException {
        throw const FormatException('A view cursor scope is malformed.');
      }
    }
    return ViewCursor(collection: collection, offset: offset, scope: scope);
  }
}

class ViewPage<T> {
  const ViewPage({
    required this.collection,
    required this.items,
    required this.total,
    required this.offset,
    required this.limit,
    this.scope,
  });

  final String collection;
  final List<T> items;
  final int total;
  final int offset;
  final int limit;
  final String? scope;

  bool get hasMore => offset + items.length < total;

  String? get nextCursor => hasMore
      ? ViewCursor.encode(collection, offset + items.length, scope: scope)
      : null;

  Map<String, dynamic> toMap({String? cursor}) => {
    'cursor': cursor,
    'offset': offset,
    'limit': limit,
    'total': total,
    'has_more': hasMore,
    'next_cursor': nextCursor,
    if (scope != null) 'scope': scope,
  };
}

ViewPage<T> paginateView<T>({
  required String collection,
  required Iterable<T> values,
  required int limit,
  String? cursor,
  String? scope,
}) {
  final all = values.toList(growable: false);
  var offset = 0;
  if (cursor != null && cursor.trim().isNotEmpty) {
    final decoded = ViewCursor.decode(cursor);
    if (decoded.collection != collection) {
      throw FormatException(
        'Cursor collection ${decoded.collection} does not match $collection.',
      );
    }
    if (decoded.scope != scope) {
      throw FormatException(
        'Cursor scope does not match the requested $collection view.',
      );
    }
    if (decoded.offset > all.length) {
      throw FormatException(
        'Cursor offset ${decoded.offset} is past the end of $collection.',
      );
    }
    offset = decoded.offset;
  }
  return ViewPage<T>(
    collection: collection,
    items: all.skip(offset).take(limit).toList(growable: false),
    total: all.length,
    offset: offset,
    limit: limit,
    scope: scope,
  );
}
