// ICD360SVPN — lib/src/api/changelog_service.dart
//
// Fetches CHANGELOG.md from the public update endpoint and parses it
// into a list of ChangelogEntry. Used by ChangelogScreen, which the
// user reaches by tapping the version label in the footer or in
// Settings.
//
// IMPORTANT: like UpdateService, this is a PLAIN HTTPS call against
// the OS root store — NOT mTLS — because it must work BEFORE the
// user has enrolled into the WireGuard tunnel. The CHANGELOG is
// public information so this is fine.
//
// Source-of-truth: the same CHANGELOG.md that release-please writes
// in the repo. The release job in .github/workflows/flutter.yml
// copies it into out/updates/CHANGELOG.md alongside version.json,
// which gets rsynced to the nginx vhost on vpn.icd360s.de.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/changelog_entry.dart';

const String kChangelogUrl = 'https://vpn.icd360s.de/updates/CHANGELOG.md';

class ChangelogService {
  ChangelogService({Dio? client, String url = kChangelogUrl})
      : _dio = client ?? Dio(),
        _url = url;

  final Dio _dio;
  final String _url;

  /// Fetches the markdown body and parses it. Returns the list of
  /// versions newest-first (matching the order in CHANGELOG.md).
  /// Throws on any failure — caller decides whether to surface an
  /// error UI or fall back silently.
  ///
  /// Why ResponseType.bytes instead of plain: nginx serves `.md` with
  /// `Content-Type: application/octet-stream` because the default
  /// mime.types ships no entry for markdown. Dio's plain decoder
  /// stalls on binary content types in some configurations rather
  /// than just utf8-decoding regardless. We sidestep that by
  /// explicitly reading bytes and decoding utf8 ourselves, plus
  /// `validateStatus: (_) => true` so non-2xx responses raise an
  /// explicit Exception path instead of throwing inside Dio (which
  /// the caller might miscatch).
  Future<List<ChangelogEntry>> fetch() async {
    final resp = await _dio.get<List<int>>(
      _url,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 5),
        validateStatus: (_) => true,
      ),
    );
    final code = resp.statusCode ?? 0;
    if (code < 200 || code >= 300) {
      throw Exception('changelog fetch failed: HTTP $code');
    }
    final bytes = resp.data;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('changelog fetch returned empty body');
    }
    final body = utf8.decode(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      allowMalformed: true,
    );
    return parse(body);
  }

  /// Parses Keep a Changelog formatted markdown into a list of
  /// ChangelogEntry. Public + static so unit tests can call it
  /// without spinning up a Dio client.
  ///
  /// Recognized version-header formats:
  ///   ## [X.Y.Z] - YYYY-MM-DD                          (Keep a Changelog manual)
  ///   ## [X.Y.Z]                                       (manual, no date)
  ///   ## [X.Y.Z](https://.../compare/...) (YYYY-MM-DD) (release-please autogen)
  ///
  /// Recognized bullet formats:
  ///   - text          (manual)
  ///   * text          (release-please autogen)
  ///
  /// Inline markdown (`**bold**`, `` `code` ``, `[text](url)`,
  /// trailing `([sha](commit url))`) is stripped to plain text so the
  /// renderer doesn't have to pull in flutter_markdown for two screens.
  ///
  /// Lines that match the link footer (`[1.2.3]: https://...`) or
  /// any other content outside a version section are ignored.
  static List<ChangelogEntry> parse(String markdown) {
    final entries = <ChangelogEntry>[];

    // Working state for the entry currently being built.
    String? curVersion;
    String? curDate;
    final curSections = <ChangelogSection>[];
    String? curSectionTitle;
    final curBullets = <String>[];
    final curBulletAccum = StringBuffer();
    bool inBullet = false;

    void flushBullet() {
      if (inBullet && curBulletAccum.isNotEmpty) {
        curBullets.add(_stripMarkdown(curBulletAccum.toString().trim()));
      }
      curBulletAccum.clear();
      inBullet = false;
    }

    void flushSection() {
      flushBullet();
      if (curSectionTitle != null) {
        curSections.add(ChangelogSection(
          title: curSectionTitle!,
          bullets: List<String>.unmodifiable(curBullets),
        ));
      }
      curSectionTitle = null;
      curBullets.clear();
    }

    void flushEntry() {
      flushSection();
      if (curVersion != null) {
        entries.add(ChangelogEntry(
          version: curVersion!,
          date: curDate,
          sections: List<ChangelogSection>.unmodifiable(curSections),
        ));
      }
      curVersion = null;
      curDate = null;
      curSections.clear();
    }

    // Version-token regex: matches `[X.Y.Z]` (with optional pre-release
    // suffix) anywhere in an `## ...` line. Date is matched
    // independently because release-please writes
    // `## [1.2.0](compare-url) (2026-04-12)` while manual entries use
    // `## [1.2.0] - 2026-04-12`.
    final versionRe = RegExp(
      r'\[(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)\]',
    );
    final dateRe = RegExp(r'(\d{4}-\d{2}-\d{2})');
    final unreleasedRe = RegExp(r'^##\s*\[Unreleased\]', caseSensitive: false);
    final subRe = RegExp(r'^###\s*(.+)$');
    final bulletRe = RegExp(r'^\s*[-*]\s+(.*)$');
    final linkFooterRe = RegExp(r'^\[[^\]]+\]:\s*https?://');

    final lines = markdown.split('\n');
    for (final raw in lines) {
      final line = raw.trimRight();

      // Link footer marks the end of changelog content.
      if (linkFooterRe.hasMatch(line)) {
        flushEntry();
        break;
      }

      // Skip Unreleased — the auto-versioning system never publishes
      // an unreleased section to the rendered viewer.
      if (unreleasedRe.hasMatch(line)) {
        flushEntry();
        continue;
      }

      // Any `## ` line containing a [X.Y.Z] token starts a new entry.
      if (line.startsWith('## ')) {
        final vMatch = versionRe.firstMatch(line);
        if (vMatch != null) {
          flushEntry();
          curVersion = vMatch.group(1);
          final dMatch = dateRe.firstMatch(line);
          curDate = dMatch?.group(1);
          continue;
        }
        // `## ` line without a version → end previous entry, ignore.
        flushEntry();
        continue;
      }

      // Subsection — only valid inside a version section.
      if (curVersion == null) continue;

      final subMatch = subRe.firstMatch(line);
      if (subMatch != null) {
        flushSection();
        curSectionTitle = subMatch.group(1)!.trim();
        continue;
      }

      // Bullet — also only valid inside a version section. If we hit
      // a bullet without a current section title, synthesize a "Notes"
      // bucket so nothing gets dropped.
      final bulletMatch = bulletRe.firstMatch(raw);
      if (bulletMatch != null) {
        flushBullet();
        curSectionTitle ??= 'Notes';
        curBulletAccum.write(bulletMatch.group(1)!);
        inBullet = true;
        continue;
      }

      // Continuation of a bullet (indented line that is not a new
      // bullet, blank line, or header).
      if (inBullet && line.isNotEmpty && raw.startsWith(RegExp(r'\s'))) {
        curBulletAccum.write(' ');
        curBulletAccum.write(line.trim());
        continue;
      }

      // Blank line ends a bullet but does not end a section.
      if (line.isEmpty) {
        flushBullet();
        continue;
      }

      // Plain paragraph text inside a version section: append it as
      // its own bullet under a synthetic "Notes" subsection so the
      // user-facing viewer doesn't drop release narrative paragraphs
      // (the v1.0.1 entry has these).
      curSectionTitle ??= 'Notes';
      flushBullet();
      curBullets.add(_stripMarkdown(line.trim()));
    }
    // Final flush in case the document doesn't end with a link footer.
    flushEntry();

    return List<ChangelogEntry>.unmodifiable(entries);
  }
}

// Strips inline markdown that release-please emits in auto-generated
// bullets, so the plain Text widget renders something readable
// without pulling in flutter_markdown for two screens.
//
// Order matters: trailing commit-hash links go FIRST so the generic
// link rule does not eat the SHA. Bold/code/links are then resolved
// in the order they nest most often (bold containing code containing
// link is rare; we treat them as flat).
String _stripMarkdown(String s) {
  // Trailing `(([abcd1234](https://github.com/.../commit/abcd1234)))`
  // appended by release-please on every bullet.
  s = s.replaceAll(
    RegExp(r'\s*\(\[[0-9a-f]{6,40}\]\([^)]+\)\)\s*$'),
    '',
  );
  // Bold: **text** → text
  s = s.replaceAllMapped(
    RegExp(r'\*\*([^*]+)\*\*'),
    (m) => m.group(1)!,
  );
  // Inline code: `text` → text
  s = s.replaceAllMapped(
    RegExp(r'`([^`]+)`'),
    (m) => m.group(1)!,
  );
  // Links: [text](url) → text
  s = s.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]+\)'),
    (m) => m.group(1)!,
  );
  // Collapse runs of internal whitespace introduced by stripping.
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

// ---------------------------------------------------------------
// Riverpod glue — singleton service + cached future of the parsed
// list. The future is built lazily on first ChangelogScreen open and
// reused thereafter (until the app restarts).
// ---------------------------------------------------------------

final Provider<ChangelogService> changelogServiceProvider =
    Provider<ChangelogService>((ref) => ChangelogService());

final FutureProvider<List<ChangelogEntry>> changelogProvider =
    FutureProvider<List<ChangelogEntry>>((ref) async {
  final svc = ref.read(changelogServiceProvider);
  return svc.fetch();
});
