import 'dart:ui';

import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import 'local_link_share_service.dart';

typedef CommunityHelpShareInvoker = Future<void> Function(ShareParams params);

class CommunityHelpShareService {
  CommunityHelpShareService({
    http.Client? httpClient,
    CommunityHelpShareInvoker? shareInvoker,
    dynamic tempDirectory,
  }) : _delegate = LocalLinkShareService(
         httpClient: httpClient,
         shareInvoker: shareInvoker,
         tempDirectory: tempDirectory,
       );

  final LocalLinkShareService _delegate;

  static String postUrl(String postId) {
    return LocalLinkShareService.urlFor(
      LocalLinkShareItem(
        type: LocalLinkShareItemType.communityHelp,
        id: postId,
        data: const {},
      ),
    );
  }

  static String buildShareText({
    required String postId,
    required Map<String, dynamic> post,
  }) {
    return LocalLinkShareService.buildShareText(
      LocalLinkShareItem(
        type: LocalLinkShareItemType.communityHelp,
        id: postId,
        data: post,
      ),
    );
  }

  Future<void> sharePost({
    required String postId,
    required Map<String, dynamic> post,
    Rect? sharePositionOrigin,
  }) async {
    await _delegate.shareItem(
      item: LocalLinkShareItem(
        type: LocalLinkShareItemType.communityHelp,
        id: postId,
        data: post,
      ),
      sharePositionOrigin: sharePositionOrigin,
    );
  }
}
