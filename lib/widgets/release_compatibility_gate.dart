import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/release_compatibility.dart';

class ReleaseCompatibilityGate extends StatefulWidget {
  const ReleaseCompatibilityGate({
    super.key,
    required this.child,
    this.loadConfiguration,
  });
  final Widget child;
  final Future<Map<String, dynamic>?> Function()? loadConfiguration;
  @override
  State<ReleaseCompatibilityGate> createState() =>
      _ReleaseCompatibilityGateState();
}

class _ReleaseCompatibilityGateState extends State<ReleaseCompatibilityGate> {
  late Future<Map<String, dynamic>?> configuration = load();
  Future<Map<String, dynamic>?> load() async {
    if (widget.loadConfiguration case final loader?) return loader();
    return (await FirebaseFirestore.instance
            .doc('releaseConfig/clients')
            .get(const GetOptions(source: Source.server)))
        .data();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
    future: configuration,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final reason = ReleaseCompatibility.blockingReason(snapshot.data);
      if (!snapshot.hasError && reason == null) return widget.child;
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  reason == 'update'
                      ? 'Please update LocalLink to continue.'
                      : snapshot.hasError
                      ? 'We could not check this LocalLink update. Please try again.'
                      : 'This LocalLink update is being prepared. Please try again shortly.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => setState(() {
                    configuration = load();
                  }),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
