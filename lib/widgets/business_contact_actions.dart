import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/business_activation_policy.dart';

/// Contact channels already published by a claimed business. No synthetic service
/// or private conversation is created by these external actions.
class BusinessContactActions extends StatelessWidget {
  const BusinessContactActions({
    super.key,
    required this.businessData,
    this.launchContact,
  });
  final Map<String, dynamic> businessData;
  final Future<bool> Function(Uri)? launchContact;

  @override
  Widget build(BuildContext context) {
    final links = BusinessActivationPolicy.contactLinks(businessData);
    if (links.isEmpty) {
      return const Text(
        'Contact details are not available on this page yet. You can save this business and check back later.',
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: links.entries
          .map(
            (entry) => OutlinedButton.icon(
              icon: Icon(
                entry.value.scheme == 'tel'
                    ? Icons.phone_outlined
                    : entry.value.scheme == 'mailto'
                    ? Icons.email_outlined
                    : Icons.language,
              ),
              label: Text(entry.key),
              onPressed: () async {
                var opened = false;
                try {
                  opened =
                      await (launchContact?.call(entry.value) ??
                          launchUrl(
                            entry.value,
                            mode: LaunchMode.externalApplication,
                          ));
                } catch (_) {
                  /* Unsupported device route: retain the actual details. */
                }
                if (!context.mounted || opened) return;
                await showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Contact details'),
                    content: SelectableText(
                      entry.value.scheme == 'http' ||
                              entry.value.scheme == 'https'
                          ? entry.value.toString()
                          : entry.value.path,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
            ),
          )
          .toList(),
    );
  }
}
