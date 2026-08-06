/// A legal document modelled as structure, not markdown, so it renders with the
/// app's own greyscale typography and needs no parser dependency.
///
/// The **source of truth is `docs/`** — `docs/medical-disclaimer.md` and
/// `docs/privacy-policy.md`. The copy here mirrors those files; a regression
/// test asserts the load-bearing sentences still match, so the two cannot drift
/// silently (see `test/legal/legal_copy_test.dart`).
class LegalDocument {
  const LegalDocument({
    required this.title,
    required this.sections,
    this.lead,
    this.footnote,
  });

  /// Screen title.
  final String title;

  /// An unheaded opening paragraph, shown before the first section.
  final String? lead;

  final List<LegalSection> sections;

  /// Closing line, rendered quieter than body copy.
  final String? footnote;

  /// Every paragraph and bullet in the document, flattened. Used by the
  /// staleness test to check the document against its `docs/` source.
  Iterable<String> get allText => <String>[
    ?lead,
    for (final section in sections) ...<String>[
      ?section.heading,
      ...section.paragraphs,
      ...section.bullets,
    ],
    ?footnote,
  ];
}

/// One block of a [LegalDocument]: an optional heading, then paragraphs, then
/// bullets.
class LegalSection {
  const LegalSection({
    this.heading,
    this.paragraphs = const <String>[],
    this.bullets = const <String>[],
  });

  final String? heading;
  final List<String> paragraphs;
  final List<String> bullets;
}
