import 'package:flutter/material.dart';

import '../domain/legal_document.dart';
import 'legal_document_view.dart';

/// Any [LegalDocument], full screen.
///
/// One parameterised screen rather than run's three near-identical classes.
/// Nothing about rendering the privacy policy differs from rendering the terms,
/// and three classes is three places for a padding change to be applied twice
/// and forgotten once.
///
/// Rendered from bundled copy rather than fetched, so it is readable offline
/// and cannot silently change under the person who agreed to it.
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: SafeArea(child: LegalDocumentView(document: document)),
    );
  }
}
