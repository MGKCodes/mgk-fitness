import 'package:flutter/material.dart';

import '../domain/legal_copy.dart';
import 'legal_document_view.dart';

/// The privacy policy, rendered in-app.
///
/// `docs/compliance.md` requires the policy to be "published and linked in-app".
/// It is rendered from bundled copy rather than fetched, so it is readable
/// offline and cannot silently change under the user.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(privacyPolicy.title)),
      body: SafeArea(child: LegalDocumentView(document: privacyPolicy)),
    );
  }
}
