import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('signed-out startup uses real Home through a guest session', () {
    final source = File('lib/core/auth_gate.dart').readAsStringSync();

    expect(source, contains('signInAnonymously'));
    expect(source, contains('MainTabShellScreen'));
    expect(source, isNot(contains('PublicExploreScreen')));
    expect(source, isNot(contains('WelcomeScreen')));
    expect(source, isNot(contains('const LoginScreen()')));
  });

  test('auth-required action is centralised for pending user actions', () {
    final source = File(
      'lib/services/auth_required_action.dart',
    ).readAsStringSync();

    expect(source, contains('class AuthRequiredAction'));
    expect(source, contains('onAuthenticated'));
    expect(source, contains('await action();'));
  });

  test(
    'Home remains browsable while contextual creation actions are gated',
    () {
      final source = File(
        'lib/screens/customer_home_screen.dart',
      ).readAsStringSync();
      final actionStart = source.indexOf('class _HomeContextualAction');
      final actionEnd = source.indexOf(
        'class _ExploreNearbyAction',
        actionStart,
      );
      final actionBody = source.substring(actionStart, actionEnd);

      expect(source, contains('OpportunityFeed('));
      expect(actionBody, contains('AuthRequiredAction.run'));
      expect(actionBody, contains('CustomerServiceRequestScreen'));
      expect(actionBody, contains('PostServiceRequestScreen'));
      expect(actionBody, contains('CreateChoiceScreen'));
      expect(actionBody, contains('BusinessPostAvailabilityGateScreen'));
      expect(actionBody, contains('BusinessOnboardingScreen'));
    },
  );

  test('guest-only preview is not the default app landing experience', () {
    final authGate = File('lib/core/auth_gate.dart').readAsStringSync();
    final publicPreview = File(
      'lib/screens/public_explore_screen.dart',
    ).readAsStringSync();

    expect(authGate, isNot(contains('Browse a limited public preview')));
    expect(publicPreview, contains('Browse a limited public preview'));
  });

  test('public preview helpers avoid private location fallbacks', () {
    final source = File('functions/index.js').readAsStringSync();
    final helperStart = source.indexOf('function publicAreaText');
    final helperEnd = source.indexOf('function matchesPublicArea');
    final helperBody = source.substring(helperStart, helperEnd);

    expect(source, contains('function publicAreaText'));
    expect(helperBody, isNot(contains('data.location,')));
    expect(source, contains('function matchesPublicCommunityHelpArea'));
    expect(source, contains('if (target.length < 3) return false;'));
    expect(source, contains('isPublicAvailabilityPreviewable'));
  });

  test('anonymous share analytics do not attach temporary guest uid', () {
    final source = File(
      'lib/services/local_link_share_service.dart',
    ).readAsStringSync();

    expect(source, contains('user != null && !user.isAnonymous'));
    expect(
      source,
      isNot(contains("'userId': FirebaseAuth.instance.currentUser?.uid")),
    );
  });

  test('guest competition entry actions use the shared auth-return flow', () {
    final source = File(
      'lib/screens/opportunity_detail_screen.dart',
    ).readAsStringSync();

    expect(source, contains("import '../services/auth_required_action.dart';"));
    expect(source, contains('Future<void> _runChallengeEntryAction'));
    expect(source, contains('AuthRequiredAction.run'));
    expect(source, contains('action: _pickEntryImageForRegisteredUser'));
    expect(
      source,
      contains('action: () => _postComment(asChallengeEntry: true)'),
    );
  });

  test('signed-in competition entrants continue without login detour', () {
    final source = File(
      'lib/screens/opportunity_detail_screen.dart',
    ).readAsStringSync();
    final helperStart = source.indexOf('Future<void> _runChallengeEntryAction');
    final pickStart = source.indexOf(
      'Future<void> _pickEntryImage()',
      helperStart,
    );
    final helperBody = source.substring(helperStart, pickStart);

    expect(helperBody, contains('user != null && !user.isAnonymous'));
    expect(helperBody, contains('await action();'));
    expect(
      helperBody.indexOf('await action();'),
      lessThan(helperBody.indexOf('AuthRequiredAction.run')),
    );
  });

  test('guest competition photo picking is gated before image selection', () {
    final source = File(
      'lib/screens/opportunity_detail_screen.dart',
    ).readAsStringSync();
    final pickStart = source.indexOf('Future<void> _pickEntryImage()');
    final pickerStart = source.indexOf(
      'Future<void> _pickEntryImageForRegisteredUser()',
    );
    final pickBody = source.substring(pickStart, pickerStart);

    expect(pickBody, contains('_runChallengeEntryAction'));
    expect(pickBody, isNot(contains('imagePicker.pickImage')));
  });

  test('guest competition submit is gated before Firebase writes', () {
    final source = File(
      'lib/screens/opportunity_detail_screen.dart',
    ).readAsStringSync();
    final postStart = source.indexOf(
      'Future<void> _postComment({bool asChallengeEntry = false})',
    );
    final logStart = source.indexOf('void _logChallengeEntryStage', postStart);
    final postBody = source.substring(postStart, logStart);
    final authGate = postBody.indexOf('_runChallengeEntryAction');
    final storageWrite = postBody.indexOf('FirebaseStorage.instance');
    final firestoreTransaction = postBody.indexOf('commentService.addComment');

    expect(authGate, isNonNegative);
    expect(storageWrite, greaterThan(authGate));
    expect(firestoreTransaction, greaterThan(authGate));
  });

  test('guest competition view remains available', () {
    final source = File(
      'lib/screens/opportunity_detail_screen.dart',
    ).readAsStringSync();
    final buildStart = source.indexOf('@override\n  Widget build');
    final composerStart = source.indexOf(
      '_ChallengeEntryComposer(',
      buildStart,
    );
    final beforeComposer = source.substring(buildStart, composerStart);

    expect(beforeComposer, isNot(contains('AuthRequiredAction.run')));
    expect(beforeComposer, contains('_isCommunityChallenge(opportunity)'));
  });

  test('competition owners are offered entry deletion controls', () {
    final source = File(
      'lib/screens/opportunity_detail_screen.dart',
    ).readAsStringSync();

    expect(source, contains("'Delete entry'"));
    expect(source, contains("data['isChallengeEntry'] == true"));
    expect(source, contains('commentService.deleteComment'));
  });

  test('identity action callables reject anonymous Firebase sessions', () {
    final source = File('functions/index.js').readAsStringSync();

    expect(source, contains('function assertRegisteredAuth'));
    for (final callable in [
      'exports.createServiceEnquiry',
      'exports.createCommunityHelpConversation',
      'exports.followCommunityHelpPost',
      'exports.sendBookingMessage',
      'exports.createConnectedAccount',
    ]) {
      final start = source.indexOf(callable);
      final nextExport = source.indexOf('\nexports.', start + callable.length);
      final end = nextExport == -1 ? source.length : nextExport;
      final body = source.substring(start, end);
      expect(body, contains('assertRegisteredAuth'));
    }
  });
}
