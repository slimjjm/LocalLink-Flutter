import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

typedef LocalLinkShareInvoker = Future<void> Function(ShareParams params);

enum LocalLinkShareItemType {
  communityHelp,
  activity,
  availability,
  business,
  service,
}

class LocalLinkShareItem {
  const LocalLinkShareItem({
    required this.type,
    required this.id,
    required this.data,
    this.parentId,
  });

  final LocalLinkShareItemType type;
  final String id;
  final Map<String, dynamic> data;
  final String? parentId;
}

class LocalLinkShareService {
  LocalLinkShareService({
    http.Client? httpClient,
    LocalLinkShareInvoker? shareInvoker,
    Directory? tempDirectory,
  }) : _httpClient = httpClient ?? http.Client(),
       _shareInvoker =
           shareInvoker ??
           ((params) async {
             await SharePlus.instance.share(params);
           }),
       _tempDirectory = tempDirectory;

  static const baseUrl = 'https://locallinkapp.co.uk';

  final http.Client _httpClient;
  final LocalLinkShareInvoker _shareInvoker;
  final Directory? _tempDirectory;

  static String urlFor(LocalLinkShareItem item) {
    final id = Uri.encodeComponent(item.id);
    switch (item.type) {
      case LocalLinkShareItemType.communityHelp:
        return '$baseUrl/community-help/$id';
      case LocalLinkShareItemType.activity:
        return '$baseUrl/opportunities/$id';
      case LocalLinkShareItemType.availability:
        return '$baseUrl/availability/$id';
      case LocalLinkShareItemType.business:
        return '$baseUrl/businesses/$id';
      case LocalLinkShareItemType.service:
        final businessId = Uri.encodeComponent(_text(item.parentId));
        return '$baseUrl/services/$businessId/$id';
    }
  }

  static String buildShareText(LocalLinkShareItem item) {
    switch (item.type) {
      case LocalLinkShareItemType.communityHelp:
        return _communityHelpText(item);
      case LocalLinkShareItemType.activity:
        return _activityText(item);
      case LocalLinkShareItemType.availability:
        return _availabilityText(item);
      case LocalLinkShareItemType.business:
        return _businessText(item);
      case LocalLinkShareItemType.service:
        return _serviceText(item);
    }
  }

  Future<void> shareItem({
    required LocalLinkShareItem item,
    Rect? sharePositionOrigin,
  }) async {
    final shareText = buildShareText(item);
    final subject = _shareSubject(item);
    final origin = _resolvedShareOrigin(sharePositionOrigin);
    final photoUrl = _firstText([
      item.data['photoUrl'],
      item.data['imageUrl'],
      item.data['coverPhoto'],
      item.data['logoUrl'],
    ]);

    if (_canDownload(photoUrl)) {
      final file = await _downloadImage(photoUrl, item);
      if (file != null) {
        try {
          await _shareInvoker(
            ShareParams(
              text: shareText,
              subject: subject,
              title: subject,
              files: [XFile(file.path, mimeType: _mimeTypeFor(file.path))],
              fileNameOverrides: [_shareFileName(item, file.path)],
              sharePositionOrigin: origin,
            ),
          );
          await _recordShare(item);
          return;
        } catch (error, stackTrace) {
          _debugLog(
            'Image share failed; falling back to text.',
            error,
            stackTrace,
          );
        } finally {
          _scheduleTempFileCleanup(file);
        }
      }
    }

    try {
      await _shareInvoker(
        ShareParams(
          text: shareText,
          subject: subject,
          title: subject,
          sharePositionOrigin: origin,
        ),
      );
      await _recordShare(item);
    } catch (error, stackTrace) {
      _debugLog('Text share failed.', error, stackTrace);
      try {
        await _shareInvoker(
          ShareParams(
            uri: Uri.parse(urlFor(item)),
            subject: subject,
            title: subject,
            sharePositionOrigin: origin,
          ),
        );
        await _recordShare(item);
      } catch (fallbackError, fallbackStackTrace) {
        _debugLog('URL-only share failed.', fallbackError, fallbackStackTrace);
        rethrow;
      }
    }
  }

  Future<File?> _downloadImage(String photoUrl, LocalLinkShareItem item) async {
    try {
      final response = await _httpClient.get(Uri.parse(photoUrl));
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          response.bodyBytes.isEmpty) {
        _debugLog(
          'Image download skipped with status ${response.statusCode}.',
          null,
          null,
        );
        return null;
      }

      final contentType = response.headers['content-type'] ?? '';
      final extension = _extensionFor(contentType);
      final directory = _tempDirectory ?? Directory.systemTemp;
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final safeId = '${item.type.name}-${item.id}'.replaceAll(
        RegExp(r'[^a-zA-Z0-9_-]'),
        '_',
      );
      final file = File(
        '${directory.path}/locallink-share-$safeId-${DateTime.now().microsecondsSinceEpoch}.$extension',
      );
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file;
    } catch (error, stackTrace) {
      _debugLog('Image download failed; sharing text only.', error, stackTrace);
      return null;
    }
  }

  void _scheduleTempFileCleanup(File file) {
    if (_tempDirectory != null) {
      return;
    }
    unawaited(_deleteTempFileAfterShare(file));
  }

  Future<void> _deleteTempFileAfterShare(File file) async {
    try {
      await Future<void>.delayed(const Duration(minutes: 5));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (error, stackTrace) {
      _debugLog('Temporary share image cleanup failed.', error, stackTrace);
    }
  }

  Future<void> _recordShare(LocalLinkShareItem item) async {
    if (Firebase.apps.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('shares').add({
        'itemType': item.type.name,
        'itemId': item.id,
        if (_text(item.parentId).isNotEmpty) 'parentId': item.parentId,
        if (item.type == LocalLinkShareItemType.communityHelp)
          'communityHelpPostId': item.id,
        if (item.type == LocalLinkShareItemType.activity)
          'opportunityId': item.id,
        if (item.type == LocalLinkShareItemType.availability)
          'availabilityPostId': item.id,
        if (item.type == LocalLinkShareItemType.business) 'businessId': item.id,
        if (item.type == LocalLinkShareItemType.service) 'serviceId': item.id,
        'userId': FirebaseAuth.instance.currentUser?.uid,
        'createdAt': Timestamp.now(),
      });
    } catch (error, stackTrace) {
      _debugLog('Share analytics could not be recorded.', error, stackTrace);
    }
  }

  static String _communityHelpText(LocalLinkShareItem item) {
    final post = item.data;
    final type = _text(post['type'], fallback: 'lost_found');
    final mode = _text(post['mode'], fallback: 'lost');
    final title = _text(post['title'], fallback: 'Community Help alert');
    final publicLocation = _text(post['publicLocation']);
    final timing = _firstText([post['eventDateText'], post['timing']]);
    final itemCategory = _text(post['itemCategory'], fallback: 'Item');
    final link = urlFor(item);
    final locationSuffix = publicLocation.isEmpty
        ? ''
        : ' — ${publicLocation.toUpperCase()}';

    if (type == 'free_item') {
      return [
        'FREE ITEM$locationSuffix',
        if (timing.isNotEmpty) 'Available: $timing',
        '$title is being offered free on LocalLink.',
        link,
      ].join('\n\n');
    }

    if (mode == 'found') {
      final objectLabel = itemCategory == 'Pet'
          ? 'FOUND PET'
          : 'FOUND ${itemCategory.toUpperCase()}';
      return [
        '$objectLabel$locationSuffix',
        if (timing.isNotEmpty) 'Found: $timing',
        'If this could be yours, view the LocalLink post and contact the poster privately.',
        link,
      ].join('\n\n');
    }

    if (itemCategory == 'Pet') {
      final petType = _petType(post);
      return [
        '🚨 MISSING ${petType.toUpperCase()}$locationSuffix',
        if (timing.isNotEmpty) 'Last seen: $timing',
        "Please keep a lookout. If you've seen this $petType, report a sighting on LocalLink.",
        link,
      ].join('\n\n');
    }

    final objectLabel = itemCategory.trim().isEmpty ? 'OBJECT' : itemCategory;
    return [
      '🚨 LOST ${objectLabel.toUpperCase()}$locationSuffix',
      if (timing.isNotEmpty) 'Last seen: $timing',
      'Please keep a lookout. If you have seen it, report a sighting on LocalLink.',
      link,
    ].join('\n\n');
  }

  static String _activityText(LocalLinkShareItem item) {
    final data = item.data;
    final title = _text(data['title'], fallback: 'Activity on LocalLink');
    final location = _publicLocation(data);
    final date = _dateLabel(data['eventDate']);
    final time = _text(data['eventTime']);
    final distance = _distanceLabel(data['distanceMiles']);
    final heading = location.isEmpty ? title : '$title in $location';
    final details = [
      [date, time].where((part) => part.isNotEmpty).join(' - '),
      distance,
    ].where((part) => part.isNotEmpty).join('\n');

    return [
      heading,
      if (details.isNotEmpty) details,
      'Join or find out more on LocalLink:',
      urlFor(item),
    ].join('\n\n');
  }

  static String _availabilityText(LocalLinkShareItem item) {
    final data = item.data;
    final serviceName = _text(data['serviceName'], fallback: 'Service');
    final businessName = _text(
      data['businessName'],
      fallback: 'Local business',
    );
    final when = _dateTimeLabel(
      data['startDateTime'] ?? data['startTime'] ?? data['availabilityAt'],
    );
    final price = _priceLabel(data['price'] ?? data['priceOverride']);

    return [
      '$serviceName available from $businessName',
      [when, price].where((part) => part.isNotEmpty).join('\n'),
      'Book or ask about this time on LocalLink:',
      urlFor(item),
    ].where((part) => part.isNotEmpty).join('\n\n');
  }

  static String _businessText(LocalLinkShareItem item) {
    final data = item.data;
    final businessName = _text(
      data['businessName'],
      fallback: 'Local business',
    );
    final category = _text(data['category']);
    final serviceArea = _text(data['serviceArea']);

    return [
      '$businessName on LocalLink',
      [category, serviceArea].where((part) => part.isNotEmpty).join(' - '),
      'View services, availability and reviews:',
      urlFor(item),
    ].where((part) => part.isNotEmpty).join('\n\n');
  }

  static String _serviceText(LocalLinkShareItem item) {
    final data = item.data;
    final serviceName = _text(data['name'], fallback: 'Service');
    final businessName = _text(
      data['businessName'],
      fallback: 'Local business',
    );
    final duration = data['durationMinutes'] is num
        ? '${(data['durationMinutes'] as num).round()} minutes'
        : '';
    final price = _priceLabel(data['price']);

    return [
      '$serviceName from $businessName',
      [price, duration].where((part) => part.isNotEmpty).join('\n'),
      'Book or ask a question on LocalLink:',
      urlFor(item),
    ].where((part) => part.isNotEmpty).join('\n\n');
  }

  static String _shareSubject(LocalLinkShareItem item) {
    switch (item.type) {
      case LocalLinkShareItemType.communityHelp:
        final mode = _text(item.data['mode'], fallback: 'lost');
        final category = _text(item.data['itemCategory'], fallback: 'item');
        if (_text(item.data['type']) == 'free_item') {
          return 'Free item on LocalLink';
        }
        return mode == 'found'
            ? 'Found $category on LocalLink'
            : 'Lost $category on LocalLink';
      case LocalLinkShareItemType.activity:
        return '${_text(item.data['title'], fallback: 'Activity')} on LocalLink';
      case LocalLinkShareItemType.availability:
        return '${_text(item.data['serviceName'], fallback: 'Available time')} on LocalLink';
      case LocalLinkShareItemType.business:
        return '${_text(item.data['businessName'], fallback: 'Business')} on LocalLink';
      case LocalLinkShareItemType.service:
        return '${_text(item.data['name'], fallback: 'Service')} on LocalLink';
    }
  }

  static bool _canDownload(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'https' || uri.scheme == 'http');
  }

  static String _petType(Map<String, dynamic> post) {
    final haystack = [
      post['title'],
      post['description'],
      post['keywords'],
    ].join(' ').toLowerCase();

    if (RegExp(
      r'\b(dog|puppy|labrador|spaniel|terrier|bulldog)\b',
    ).hasMatch(haystack)) {
      return 'dog';
    }
    if (RegExp(r'\b(cat|kitten)\b').hasMatch(haystack)) {
      return 'cat';
    }
    return 'pet';
  }

  static String _publicLocation(Map<String, dynamic> data) {
    return _firstText([
      data['publicLocation'],
      data['locationLabel'],
      data['location'],
    ]);
  }

  static String _firstText(Iterable<dynamic> values) {
    for (final value in values) {
      final text = _text(value);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static String _dateLabel(dynamic value) {
    final date = _dateFromValue(value);
    if (date == null) return '';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[date.weekday - 1]} ${date.day}/${date.month}';
  }

  static String _dateTimeLabel(dynamic value) {
    final date = _dateFromValue(value);
    if (date == null) return '';
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${_dateLabel(date)} at $hour:$minute';
  }

  static DateTime? _dateFromValue(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value != null && value.runtimeType.toString() == 'Timestamp') {
      try {
        return dynamicToDate(value);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static DateTime? dynamicToDate(dynamic value) => value.toDate() as DateTime?;

  static String _distanceLabel(dynamic value) {
    if (value is! num) return '';
    return '${value.toStringAsFixed(1)} miles away';
  }

  static String _priceLabel(dynamic value) {
    if (value == null) return '';
    final pence = value is num ? value.toDouble() : double.tryParse('$value');
    if (pence == null || pence <= 0) return '';
    return '£${(pence / 100).toStringAsFixed(2)}';
  }

  static String _extensionFor(String contentType) {
    final lower = contentType.toLowerCase();
    if (lower.contains('png')) return 'png';
    if (lower.contains('webp')) return 'webp';
    if (lower.contains('gif')) return 'gif';
    return 'jpg';
  }

  static String _mimeTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  static String _shareFileName(LocalLinkShareItem item, String path) {
    final extension = path.split('.').last.toLowerCase();
    final safeId = item.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final safeExtension = RegExp(r'^[a-z0-9]+$').hasMatch(extension)
        ? extension
        : 'jpg';
    return 'locallink-${item.type.name}-$safeId.$safeExtension';
  }

  static Rect _resolvedShareOrigin(Rect? provided) {
    if (provided != null &&
        provided.width > 0 &&
        provided.height > 0 &&
        provided.left.isFinite &&
        provided.top.isFinite) {
      return provided;
    }

    final Iterable<FlutterView> views;
    try {
      views = WidgetsBinding.instance.platformDispatcher.views;
    } catch (_) {
      return const Rect.fromLTWH(1, 1, 1, 1);
    }

    if (views.isEmpty) {
      return const Rect.fromLTWH(1, 1, 1, 1);
    }

    final view = views.first;
    final devicePixelRatio = view.devicePixelRatio;
    final logicalSize = devicePixelRatio > 0
        ? view.physicalSize / devicePixelRatio
        : view.physicalSize;

    if (logicalSize.width <= 2 ||
        logicalSize.height <= 2 ||
        !logicalSize.width.isFinite ||
        !logicalSize.height.isFinite) {
      return const Rect.fromLTWH(1, 1, 1, 1);
    }

    return Rect.fromCenter(
      center: Offset(logicalSize.width / 2, logicalSize.height / 2),
      width: 1,
      height: 1,
    );
  }

  static String _text(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static void _debugLog(String message, Object? error, StackTrace? stackTrace) {
    if (!kDebugMode) return;
    debugPrint('LocalLinkShareService: $message');
    if (error != null) debugPrint('LocalLinkShareService error: $error');
    if (stackTrace != null) {
      debugPrint('LocalLinkShareService stack: $stackTrace');
    }
  }
}
