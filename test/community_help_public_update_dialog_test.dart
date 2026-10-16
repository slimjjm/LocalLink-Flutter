import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The reviewed correction keeps this dialog private. This compiled fixture is
// required to match its actual source exactly, so the two lifecycle scenarios
// cannot silently test a different implementation.
void main() {
  setUpAll(() {
    final production = File(
      'lib/screens/post_service_request_screen.dart',
    ).readAsStringSync();
    final start = production.indexOf(
      'class _PublicUpdateDialog extends StatefulWidget',
    );
    final end = production.indexOf(
      'class _ClosingUpdateDialog extends StatefulWidget',
      start,
    );
    final fixture = File(
      'test/community_help_public_update_dialog_test.dart',
    ).readAsStringSync();
    final fixtureStart = fixture.lastIndexOf(
      'class _PublicUpdateDialog extends StatefulWidget',
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    expect(
      production.substring(start, end).trim(),
      fixture.substring(fixtureStart).trim(),
    );
  });
  for (final action in ['Post update', 'Cancel']) {
    testWidgets('public update dialog closes safely with $action', (
      tester,
    ) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: context,
                    builder: (_) => const _PublicUpdateDialog(),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        '  Synthetic test update only.  ',
      );
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        result,
        action == 'Post update' ? 'Synthetic test update only.' : isNull,
      );
      expect(find.byType(TextField), findsNothing);
    });
  }
}

class _PublicUpdateDialog extends StatefulWidget {
  const _PublicUpdateDialog();

  @override
  State<_PublicUpdateDialog> createState() => _PublicUpdateDialogState();
}

class _PublicUpdateDialogState extends State<_PublicUpdateDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Share an update'),
      content: TextField(
        controller: _controller,
        maxLength: 240,
        minLines: 2,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Short public update for people keeping a lookout',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Post update'),
        ),
      ],
    );
  }
}
