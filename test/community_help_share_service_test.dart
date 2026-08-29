import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:locallink_flutter/services/community_help_share_service.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  Map<String, dynamic> post({
    String type = 'lost_found',
    String mode = 'lost',
    String itemCategory = 'Pet',
    String title = 'Milo black Labrador',
    String description = 'Friendly dog with a red collar',
    String publicLocation = 'Burntwood',
    String eventDateText = 'Today at 11:00',
    String photoUrl = '',
  }) {
    return {
      'type': type,
      'mode': mode,
      'itemCategory': itemCategory,
      'title': title,
      'description': description,
      'publicLocation': publicLocation,
      'location': '42 Private Road, Burntwood',
      'approxLatitude': 52.6801,
      'approxLongitude': -1.8302,
      'eventDateText': eventDateText,
      'photoUrl': photoUrl,
    };
  }

  test('missing dog share text uses actual location, time and post link', () {
    final text = CommunityHelpShareService.buildShareText(
      postId: 'post-123',
      post: post(),
    );

    expect(text, contains('🚨 MISSING DOG — BURNTWOOD'));
    expect(text, contains('Last seen: Today at 11:00'));
    expect(text, contains("If you've seen this dog"));
    expect(
      text,
      contains('https://locallinkapp.co.uk/community-help/post-123'),
    );
  });

  test('missing pet without dog or cat wording falls back to pet', () {
    final text = CommunityHelpShareService.buildShareText(
      postId: 'post-123',
      post: post(title: 'Missing rabbit', description: 'Small grey rabbit'),
    );

    expect(text, contains('🚨 MISSING PET — BURNTWOOD'));
    expect(text, contains("If you've seen this pet"));
  });

  test('lost object share text adapts to object category', () {
    final text = CommunityHelpShareService.buildShareText(
      postId: 'keys-1',
      post: post(
        itemCategory: 'Keys',
        title: 'House keys',
        description: 'Set of keys',
      ),
    );

    expect(text, contains('🚨 LOST KEYS — BURNTWOOD'));
    expect(text, contains('Please keep a lookout.'));
  });

  test('found object share text does not ask people to report sightings', () {
    final text = CommunityHelpShareService.buildShareText(
      postId: 'wallet-1',
      post: post(
        mode: 'found',
        itemCategory: 'Wallet',
        title: 'Wallet found',
        eventDateText: 'Found this morning',
      ),
    );

    expect(text, contains('FOUND WALLET — BURNTWOOD'));
    expect(text, contains('Found: Found this morning'));
    expect(text, isNot(contains("If you've seen")));
  });

  test('free item share text adapts to free item posts', () {
    final text = CommunityHelpShareService.buildShareText(
      postId: 'free-1',
      post: post(
        type: 'free_item',
        mode: 'offering',
        itemCategory: 'Free item',
        title: 'Free baby gate',
        eventDateText: 'Available today',
      ),
    );

    expect(text, contains('FREE ITEM — BURNTWOOD'));
    expect(
      text,
      contains('Free baby gate is being offered free on LocalLink.'),
    );
  });

  test(
    'share text uses public approximate location and avoids private fields',
    () {
      final text = CommunityHelpShareService.buildShareText(
        postId: 'privacy-1',
        post: post(),
      );

      expect(text, contains('BURNTWOOD'));
      expect(text, isNot(contains('42 Private Road')));
      expect(text, isNot(contains('52.6801')));
      expect(text, isNot(contains('-1.8302')));
    },
  );

  test('post link identifies the correct Community Help post', () {
    expect(
      CommunityHelpShareService.postUrl('abc_123'),
      'https://locallinkapp.co.uk/community-help/abc_123',
    );
  });

  test('missing pet with photo shares image file plus text', () async {
    final temp = await Directory.systemTemp.createTemp('locallink-share-test-');
    final shared = <ShareParams>[];
    String? sharedPath;
    const origin = Rect.fromLTWH(10, 20, 30, 40);

    final service = CommunityHelpShareService(
      tempDirectory: temp,
      httpClient: _FakeHttpClient(
        (request) async => http.Response.bytes(
          [1, 2, 3, 4],
          200,
          headers: {'content-type': 'image/jpeg'},
        ),
      ),
      shareInvoker: (params) async {
        shared.add(params);
        sharedPath = params.files!.single.path;
        expect(await File(sharedPath!).exists(), isTrue);
      },
    );

    await service.sharePost(
      postId: 'photo-1',
      post: post(photoUrl: 'https://example.com/milo.jpg'),
      sharePositionOrigin: origin,
    );

    expect(shared, hasLength(1));
    expect(shared.single.files, hasLength(1));
    expect(shared.single.fileNameOverrides, [
      'locallink-communityHelp-photo-1.jpg',
    ]);
    expect(shared.single.text, contains('MISSING DOG'));
    expect(shared.single.sharePositionOrigin, origin);
    expect(await File(sharedPath!).exists(), isTrue);

    await temp.delete(recursive: true);
  });

  test('missing pet without photo shares text and link only', () async {
    final shared = <ShareParams>[];
    final service = CommunityHelpShareService(
      httpClient: _FakeHttpClient((request) async => throw StateError('nope')),
      shareInvoker: (params) async => shared.add(params),
    );

    await service.sharePost(postId: 'no-photo', post: post());

    expect(shared, hasLength(1));
    expect(shared.single.files, isNull);
    expect(shared.single.sharePositionOrigin, isNotNull);
    expect(
      shared.single.text,
      contains('https://locallinkapp.co.uk/community-help/no-photo'),
    );
  });

  test('image download failure falls back to text and link sharing', () async {
    final shared = <ShareParams>[];
    final service = CommunityHelpShareService(
      httpClient: _FakeHttpClient(
        (request) async => http.Response('missing', 404),
      ),
      shareInvoker: (params) async => shared.add(params),
    );

    await service.sharePost(
      postId: 'download-fails',
      post: post(photoUrl: 'https://example.com/missing.jpg'),
    );

    expect(shared, hasLength(1));
    expect(shared.single.files, isNull);
    expect(shared.single.sharePositionOrigin, isNotNull);
    expect(shared.single.text, contains('download-fails'));
  });

  test('image share failure falls back to text and link sharing', () async {
    var attempt = 0;
    final shared = <ShareParams>[];
    final temp = await Directory.systemTemp.createTemp('locallink-share-test-');
    final service = CommunityHelpShareService(
      tempDirectory: temp,
      httpClient: _FakeHttpClient(
        (request) async => http.Response.bytes(
          [1, 2, 3, 4],
          200,
          headers: {'content-type': 'image/png'},
        ),
      ),
      shareInvoker: (params) async {
        attempt += 1;
        if (attempt == 1) throw StateError('destination rejected image');
        shared.add(params);
      },
    );

    await service.sharePost(
      postId: 'image-rejected',
      post: post(photoUrl: 'https://example.com/milo.png'),
    );

    expect(attempt, 2);
    expect(shared.single.files, isNull);
    expect(shared.single.sharePositionOrigin, isNotNull);
    expect(shared.single.text, contains('image-rejected'));

    await temp.delete(recursive: true);
  });

  test('text share failure falls back to URL-only sharing', () async {
    var attempt = 0;
    final shared = <ShareParams>[];
    const origin = Rect.fromLTWH(1, 2, 3, 4);
    final service = CommunityHelpShareService(
      shareInvoker: (params) async {
        attempt += 1;
        if (attempt == 1) throw StateError('text rejected');
        shared.add(params);
      },
    );

    await service.sharePost(
      postId: 'url-fallback',
      post: post(),
      sharePositionOrigin: origin,
    );

    expect(attempt, 2);
    expect(shared.single.text, isNull);
    expect(
      shared.single.uri,
      Uri.parse('https://locallinkapp.co.uk/community-help/url-fallback'),
    );
    expect(shared.single.sharePositionOrigin, origin);
  });

  test('native text share failure is surfaced', () async {
    final service = CommunityHelpShareService(
      shareInvoker: (params) async => throw StateError('cannot open sheet'),
    );

    expect(
      () => service.sharePost(postId: 'fail', post: post()),
      throwsA(isA<StateError>()),
    );
  });
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._handler);

  final Future<http.Response> Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _handler(request);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: request,
    );
  }
}
