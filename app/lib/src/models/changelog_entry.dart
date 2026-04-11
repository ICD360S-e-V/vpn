// ICD360SVPN — lib/src/models/changelog_entry.dart
//
// Parsed representation of one version section in CHANGELOG.md.
// Populated by ChangelogService.parse() from a Keep a Changelog
// formatted document. Used by ChangelogScreen to render the
// per-version history when the user taps on the version label in
// the footer or Settings.

import 'package:flutter/foundation.dart';

@immutable
class ChangelogEntry {
  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.sections,
  });

  /// Parsed semver string, e.g. `1.2.3`. No leading `v`.
  final String version;

  /// `YYYY-MM-DD` from the section header, or null if the heading
  /// did not include one.
  final String? date;

  /// Map of section title (e.g. "Features", "Bug Fixes", "Added")
  /// to the list of bullet items under that subsection. Order is
  /// preserved as it appears in the source document.
  final List<ChangelogSection> sections;

  bool get isEmpty => sections.every((s) => s.bullets.isEmpty);
}

@immutable
class ChangelogSection {
  const ChangelogSection({required this.title, required this.bullets});

  final String title;
  final List<String> bullets;
}
