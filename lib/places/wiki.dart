/// v6: internet enrichment of place cards from FREE, KEYLESS sources —
/// «пусть черпает везде где можно, главное чтобы правильно было!»:
///
///   • Wikipedia REST summary — short description + extract + lead image;
///   • Wikipedia geosearch / search — the page that IS the tapped place
///     (monuments, town halls, churches…);
///   • Wikidata — the EXACT entity of the place (Nominatim hands us the
///     Q-id): P18 photo, P154/P94 coat of arms, P163 flag, P1082
///     population + sitelinks (exact wiki page per language);
///   • Wikimedia Commons — resolves File: titles (OSM tags, P18, flag,
///     emblem) to thumbnail URLs.
///
/// STRICTNESS CONTRACT (the user: «если нету фотографии места по которому
/// тапнул пусть не грузит фотографии места который рядом!»):
///   • OSM tags / Wikidata / the matched wiki page are EXACT sources —
///     no name check needed;
///   • Commons geosearch hits are accepted ONLY when the file title shares
///     significant name tokens with the place («Café de la Paix» never
///     pulls «Place de la Paix»);
///   • an unnamed place gets no geosearch photos at all;
///   • v6.1: maps / plans / flags / coats of arms / logos found by
///     geosearch are NEVER card photos («википедиа… выдает про центр
///     коммунны» — the same correctness-first principle for media).
///
/// v6.1 SPEED («инфа грузится очень долго»): the 5 sequential Wikidata
/// round-trips (P18, P163, P154, P94, P1082 + sitelinks) became ONE
/// wbgetentities call (+ one optional chase call when a flag/coat of arms
/// is a link to another item), and the Wikidata / Commons / page-summary
/// branches now run in PARALLEL instead of a chain.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

/// Everything Wikipedia / Wikidata know about the tapped place.
class PlaceWiki {
  const PlaceWiki({
    this.description,
    this.extract,
    this.pageUrl,
    this.flagUrl,
    this.emblemUrl,
    this.population,
    this.photos = const <String>[],
  });

  /// One-liner: «коммуна во Франции».
  final String? description;

  /// 2–4 sentences of real content.
  final String? extract;

  /// The article on wikipedia.org.
  final String? pageUrl;

  /// P163 flag / P154 coat of arms thumbnails (cities and communes).
  final String? flagUrl;
  final String? emblemUrl;

  /// P1082 — the latest known population figure.
  final int? population;

  /// Photos of THIS place: exact sources first, then strict Commons hits.
  final List<String> photos;

  bool get hasAny =>
      (description != null && description!.isNotEmpty) ||
      (extract != null && extract!.isNotEmpty) ||
      pageUrl != null ||
      population != null ||
      photos.isNotEmpty;
}

class WikiService {
  WikiService({http.Client? client}) : _client = client ?? http.Client();

  static const _ua = {
    // Wikimedia policy (2025): generic UAs get 403 — a URL + contact
    // pattern is REQUIRED for the API to answer at all.
    'User-Agent':
        'Navigo/6.1 (https://github.com/navigo-navigator/navigo; '
        'navigo-navigator@users.noreply.github.com)',
  };

  final http.Client _client;

  // ── matching ────────────────────────────────────────────────────────────

  static const _stop = {
    'de', 'la', 'le', 'les', 'du', 'des', 'd', 'l', 'the', 'and', 'of',
    'a', 'an', 'in', 'at', 'on', 'sur', 'sous', 'en', 'et', 'der', 'die',
    'das', 'und', 'von', 'el', 'los', 'las', 'del', 'и', 'в', 'на', 'с',
    'ст', 'г',
  };

  /// Diacritics fold (é→e, ü→u…) so «Café» matches «Cafe».
  static String _fold(String s) {
    const from = 'àáâäãåāçćčéèêëēęìíîïīłńñòóôöõøśšťùúûüūýžźż';
    const to = 'aaaaaaaccceeeeiiiiilnnoooooosstuuuuuyzzz';
    final sb = StringBuffer();
    for (final rune in s.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      final i = from.indexOf(ch);
      sb.write(i >= 0 ? to[i] : ch);
    }
    return sb.toString();
  }

  static String _norm(String s) =>
      _fold(s).replaceAll(RegExp(r"[^\p{L}\p{N}]+", unicode: true), ' ').trim();

  static Set<String> _tokens(String s) {
    final raw = _norm(s)
        .split(' ')
        .where((t) =>
            t.length >= 2 && !_stop.contains(t) && !RegExp(r'^\d+$').hasMatch(t))
        .toSet();
    return raw;
  }

  /// STRICT title↔name match: significant-token inclusion in BOTH
  /// directions plus full-name containment.
  /// «Café de la Paix» vs «Place de la Paix» → {cafe,paix} vs {place,paix}
  /// → REJECTED; «Tour Eiffel» vs «Tour Eiffel, Paris.jpg» → OK;
  /// «Bordeaux» vs «Bordeaux Pont de Pierre.jpg» → REJECTED (a photo of
  /// the bridge is not a photo of the city), «Louvre» vs «Louvre
  /// Museum.jpg» → OK (≤ 1 extra word allowed for one-word names).
  static bool nameMatches(String placeName, String candidate) {
    final a = _tokens(placeName);
    final b = _tokens(candidate);
    if (a.isEmpty || b.isEmpty) return false;
    final fa = _norm(placeName);
    final fb = _norm(candidate);
    if (a.length >= 2 && fa.length >= 4 && fb.contains(fa)) return true;
    if (fb.length >= 4 && fa.contains(fb)) return true;
    if (a.length >= 2 && a.every(b.contains)) return true;
    if (b.every(a.contains)) return true;
    // A one-word place may carry at most ONE extra significant word in
    // the file title — anything richer is a different subject.
    if (a.length == 1 && b.length <= 2 && (fb.contains(fa) || b.contains(a.first))) {
      return true;
    }
    return false;
  }

  // ── http helpers ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _getJson(
    String url, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    try {
      final res = await _client
          .get(Uri.parse(url), headers: _ua)
          .timeout(timeout);
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  // ── Wikipedia ─────────────────────────────────────────────────────────

  /// REST summary of one page: description + extract + lead image.
  Future<_Sum?> _summary(String lang, String title) async {
    final j = await _getJson(
      'https://$lang.wikipedia.org/api/rest_v1/page/summary/'
      '${Uri.encodeComponent(title)}',
    );
    if (j == null) return null;
    final type = '${j['type']}';
    // A disambiguation page tells nothing about THIS place.
    if (type == 'disambiguation') return null;
    final extract = j['extract'] as String?;
    final desc = j['description'] as String?;
    final thumb = (j['thumbnail']?['source']) as String?;
    final origSrc = (j['originalimage']?['source']) as String?;
    final origW = (j['originalimage']?['width'] as num?)?.toInt() ?? 0;
    final page = (j['content_urls']?['desktop']?['page']) as String?;
    // v6.7: the page's own geolocation. A plain name search has no geo
    // bound at all, so this is the ONLY thing that can prove the article
    // is about THIS place and not the homonym in another city (the
    // «Auchan» company article attached to a Bordeaux hypermarket).
    final coords = j['coordinates'] as Map?;
    final lat = (coords?['lat'] as num?)?.toDouble();
    final lon = (coords?['lon'] as num?)?.toDouble();
    // v6.1: do NOT blindly upscale the 320 px thumb to 900 px — for a
    // small original MediaWiki refuses the oversized thumb and the URL
    // 404s (= the broken-image icon the user reported). A small original
    // is used as-is; a big one gets a proper 900 px thumb.
    String? image;
    if (origW > 0 && origW <= 900 && origSrc != null) {
      image = origSrc;
    } else if (thumb != null) {
      image = thumb.replaceFirst(RegExp(r'/(\d+)px-'), '/900px-');
    }
    return _Sum(
      title: title,
      lang: lang,
      description: (desc == null || desc.isEmpty) ? null : desc,
      extract: (extract == null || extract.isEmpty) ? null : extract,
      image: image,
      pageUrl: page,
      lat: lat,
      lon: lon,
    );
  }

  /// Pages geolocated near the point — candidates for «this exact place».
  Future<List<String>> _geoTitles(
    String lang,
    double lat,
    double lon,
    int radiusM,
  ) async {
    final j = await _getJson(
      'https://$lang.wikipedia.org/w/api.php'
      '?action=query&format=json&origin=*'
      '&list=geosearch&gscoord=$lat%7C$lon'
      '&gsradius=${radiusM.clamp(10, 10000)}&gslimit=25',
    );
    final list = ((j?['query'] as Map?)?['geosearch'] as List?)
        ?.cast<Map<String, dynamic>>();
    if (list == null) return const [];
    return [for (final p in list) '${p['title']}'];
  }

  /// Plain full-text search — last resort, still name-checked. Titles are
  /// ranked inline by the caller.
  Future<List<String>> _searchTitles(String lang, String name) async {
    final j = await _getJson(
      'https://$lang.wikipedia.org/w/api.php'
      '?action=query&format=json&origin=*'
      '&list=search&srlimit=5&srnamespace=0'
      '&srsearch=${Uri.encodeComponent(name)}',
    );
    final list = ((j?['query'] as Map?)?['search'] as List?)
        ?.cast<Map<String, dynamic>>();
    if (list == null || list.isEmpty) return const [];
    return [for (final p in list) '${p['title']}'];
  }

  // ── Wikidata ──────────────────────────────────────────────────────────

  /// v6.1: ONE call for everything the entity has — claims (P18 photo,
  /// P163 flag, P154/P94 coat of arms, P1082 population) AND sitelinks
  /// (the exact wiki page per language). The old code did 5+ sequential
  /// round-trips; this is the single biggest latency win.
  Future<_Ent?> _entityFull(String qid) async {
    final j = await _getJson(
      'https://www.wikidata.org/w/api.php'
      '?action=wbgetentities&format=json&origin=*'
      '&ids=${Uri.encodeComponent(qid)}&props=claims%7Csitelinks'
      '&sitefilter=ruwiki%7Cfrwiki%7Cenwiki%7Cdewiki%7Ceswiki',
      timeout: const Duration(seconds: 8),
    );
    final e = j?['entities']?[qid];
    if (e is! Map<String, dynamic>) return null;
    return _Ent(
      claims:
          (e['claims'] as Map?)?.cast<String, dynamic>() ?? const {},
      sitelinks:
          (e['sitelinks'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  /// The best-ranked claim value of one property (preferred rank wins —
  /// fresh population figures, current flag designs).
  static dynamic _bestClaim(Map<String, dynamic> claims, String prop) {
    final list = claims[prop] as List?;
    if (list == null || list.isEmpty) return null;
    Map<String, dynamic>? best;
    for (final c in list.cast<Map<String, dynamic>>()) {
      if ('${c['rank']}' == 'preferred') {
        best = c;
        break;
      }
    }
    best ??= list.first as Map<String, dynamic>;
    return best['mainsnak']?['datavalue']?['value'];
  }

  /// A media property holds either a Commons file name (string) or a LINK
  /// to another item («флаг Бордо» is an item whose P18 carries the
  /// image). Returns (fileName | linkedQid | null).
  static (String?, String?) _mediaValue(dynamic v) {
    if (v is String && v.isNotEmpty) return (v, null);
    if (v is Map && '${v['id']}'.startsWith('Q')) {
      return (null, '${v['id']}');
    }
    return (null, null);
  }

  /// v6.1: the flag/coat-of-arms chase — ONE extra call for ALL linked
  /// items at once (the old code awaited one round-trip per property).
  Future<Map<String, String>> _linkedP18(Set<String> qids) async {
    if (qids.isEmpty) return const {};
    final j = await _getJson(
      'https://www.wikidata.org/w/api.php'
      '?action=wbgetentities&format=json&origin=*'
      '&ids=${qids.map(Uri.encodeComponent).join('%7C')}&props=claims',
    );
    final ents = j?['entities'] as Map?;
    final out = <String, String>{};
    if (ents == null) return out;
    for (final qid in qids) {
      final e = ents[qid];
      if (e is! Map<String, dynamic>) continue;
      final claims =
          (e['claims'] as Map?)?.cast<String, dynamic>() ?? const {};
      final v = _bestClaim(claims, 'P18');
      if (v is String && v.isNotEmpty) out[qid] = v;
    }
    return out;
  }

  // ── Commons ───────────────────────────────────────────────────────────

  /// Resolves a batch of File: titles to thumbnail URLs in ONE call.
  /// [allowSvg] for flags / coats of arms — Commons rasterizes them into
  /// PNG thumbnails on the fly (the card shows the raster).
  Future<Map<String, String>> _fileThumbs(
    Set<String> files,
    int width, {
    bool allowSvg = false,
  }) async {
    if (files.isEmpty) return const {};
    final titles = files
        .map((f) => f.startsWith('File:') ? f : 'File:$f')
        .map(Uri.encodeComponent)
        .join('%7C');
    final j = await _getJson(
      'https://commons.wikimedia.org/w/api.php'
      '?action=query&format=json&origin=*'
      '&titles=$titles&prop=imageinfo&iiprop=url%7Cmime&iiurlwidth=$width',
      timeout: const Duration(seconds: 8),
    );
    final pages = (j?['query']?['pages'] as Map?)?.values;
    final out = <String, String>{};
    if (pages == null) return out;
    for (final p in pages) {
      if (p is! Map<String, dynamic>) continue;
      final title = '${p['title']}';
      final ii = (p['imageinfo'] as List?)?.cast<Map<String, dynamic>>();
      if (ii == null || ii.isEmpty) continue;
      final mime = '${ii.first['mime']}';
      final okMime = mime == 'image/jpeg' ||
          mime == 'image/png' ||
          (allowSvg && mime == 'image/svg+xml');
      if (!okMime) continue;
      final thumb =
          (ii.first['thumburl'] ?? ii.first['url']) as String?;
      if (thumb != null && thumb.isNotEmpty) out[title] = thumb;
    }
    return out;
  }

  /// v6.1: files that are NOT place photos — a map/plan/flag/logo in the
  /// carousel is exactly the «википедиа выдает про центр коммунны» class
  /// of wrongness. Flags & coats of arms reach the card through dedicated
  /// slots (flagUrl / emblemUrl), so they are skipped here for everyone.
  static final RegExp _junkFile = RegExp(
    r'(flag|blason|coat[\s_-]?of[\s_-]?arms|logo|logotype|locator|'
    r'\bmap\b|\bplan\b|\bplans\b|situation|blank|armorial|'
    r'карта|план|герб|флаг)',
    caseSensitive: false,
  );

  /// Commons files geolocated around the point — accepted ONLY when the
  /// title passes [nameMatches].
  Future<List<String>> _commonsAround(
    double lat,
    double lon,
    String name, {
    int radiusM = 160,
  }) async {
    final j = await _getJson(
      'https://commons.wikimedia.org/w/api.php'
      '?action=query&format=json&origin=*'
      '&generator=geosearch&ggscoord=$lat%7C$lon'
      '&ggsradius=${radiusM.clamp(10, 10000)}&ggslimit=30&ggsnamespace=6'
      '&prop=imageinfo&iiprop=url%7Cmime&iiurlwidth=900',
      timeout: const Duration(seconds: 7),
    );
    final pages = (j?['query']?['pages'] as Map?)?.values;
    if (pages == null) return const [];
    final out = <String>[];
    for (final p in pages) {
      if (p is! Map<String, dynamic>) continue;
      final title = '${p['title']}';
      final low = title.toLowerCase();
      if (low.endsWith('.svg') || low.endsWith('.gif')) continue;
      if (_junkFile.hasMatch(low)) continue;
      if (!nameMatches(
        name,
        title.replaceFirst(
          RegExp(r'\.(jpe?g|png|tiff?)$', caseSensitive: false),
          '',
        ),
      )) {
        continue; // A NEIGHBOUR's photo — the user said NO.
      }
      final ii = (p['imageinfo'] as List?)?.cast<Map<String, dynamic>>();
      if (ii == null || ii.isEmpty) continue;
      final mime = '${ii.first['mime']}';
      if (mime != 'image/jpeg' && mime != 'image/png') continue;
      final thumb =
          (ii.first['thumburl'] ?? ii.first['url']) as String?;
      if (thumb != null && thumb.isNotEmpty) out.add(thumb);
    }
    return out;
  }

  // ── the orchestrator ──────────────────────────────────────────────────

  /// Gathers everything about the place. Never throws; any failing source
  /// degrades silently to a smaller card.
  ///
  /// v6.1: the three independent branches (Wikidata entity, Commons
  /// geosearch, the wiki page chain) run in PARALLEL; the Wikidata part is
  /// ONE call (+optional chase). A city card now needs ~4 sequential
  /// round-trips instead of ~9.
  Future<PlaceWiki?> enrich({
    required double lat,
    required double lon,
    required String? name,
    required String? category,
    String? wikidata,
    String? imageTag,
    String? commonsTag,
    String? wikiTag,
    String? addrType,
    String locale = 'ru',
  }) async {
    final placeName = (name ?? '').trim();
    final cls = (category ?? '').toLowerCase();
    final isCityLike = const [
      'city', 'town', 'village', 'municipality', 'borough', 'suburb',
      'quarter', 'hamlet',
    ].any(addrType?.toLowerCase().contains ?? (String _) => false);
    final isLandmark = const [
      'monument', 'memorial', 'attraction', 'castle', 'fort', 'museum',
      'historic', 'church', 'cathedral', 'tower', 'palace', 'artwork',
      'ruins', 'archaeological',
    ].any(cls.contains);

    final langOrder = <String>[
      locale,
      'ru', 'fr', 'en',
    ].toSet().toList();

    _Sum? sum;
    final files = <String>{}; // File: titles needing Commons thumbs
    final photos = <String>[];

    // 0 ── kick off the two independent branches NOW.
    // (a) Strict Commons geosearch — extra angles of THIS place.
    final commonsF = placeName.isNotEmpty &&
            (isCityLike || isLandmark || placeName.length >= 4)
        ? _commonsAround(lat, lon, placeName)
        : Future<List<String>>.value(const []);
    // (b) The Wikidata entity — claims + sitelinks in one shot.
    final qid = wikidata?.trim() ?? '';
    final entF = qid.isNotEmpty
        ? _entityFull(qid)
        : Future<_Ent?>.value(null);

    // 1 ── EXACT image sources: OSM image / wikimedia_commons first.
    String? imageFile;
    String? imageUrl;
    if (imageTag != null && imageTag.isNotEmpty) {
      if (imageTag.toLowerCase().startsWith('file:')) {
        imageFile = imageTag;
      } else if (imageTag.startsWith('http')) {
        imageUrl = imageTag;
      }
    }
    if (imageFile == null && commonsTag != null && commonsTag.isNotEmpty) {
      if (commonsTag.toLowerCase().startsWith('file:')) {
        imageFile = commonsTag;
      } else if (!commonsTag.contains('/')) {
        imageFile = 'File:$commonsTag';
      }
    }
    String? flagFile;
    String? emblemFile;
    int? population;

    final ent = await entF;
    if (ent != null) {
      // P18 photo of the entity; flag/coat of arms may be a file name OR a
      // link to the «flag of X» item (P163 → Q… → P18); P94 is the legacy
      // «coat of arms image» still populated for most French communes.
      final (p18File, _) = _mediaValue(_bestClaim(ent.claims, 'P18'));
      final (flagVal, flagQ) = _mediaValue(_bestClaim(ent.claims, 'P163'));
      final (embVal, embQ) = _mediaValue(
        _bestClaim(ent.claims, 'P154') ?? _bestClaim(ent.claims, 'P94'),
      );
      final popVal = _bestClaim(ent.claims, 'P1082');
      if (popVal is Map) {
        population = int.tryParse(
          '${popVal['amount']}'.replaceAll(RegExp(r'[^\d-]'), ''),
        );
      }
      // ONE chase call for every linked flag/emblem item.
      final linked = {
        if (flagQ != null) flagQ,
        if (embQ != null) embQ,
      };
      final chased = await _linkedP18(linked);
      flagFile = flagVal ?? (flagQ == null ? null : chased[flagQ]);
      emblemFile = embVal ?? (embQ == null ? null : chased[embQ]);
      if (p18File != null && imageFile == null) {
        imageFile = p18File.toLowerCase().startsWith('file:')
            ? p18File
            : 'File:$p18File';
      }
    }

    // 2 ── The wiki PAGE: sitelinks (exact) → geosearch (strict) → search.
    if (ent != null) {
      for (final l in langOrder) {
        final link = ent.sitelinks['${l}wiki']?['title'] as String?;
        if (link != null && link.isNotEmpty) {
          sum = await _summary(l, link);
          if (sum != null) break;
        }
      }
    }
    sum ??= await _pageByPlace(
      lat: lat,
      lon: lon,
      name: placeName,
      langOrder: langOrder,
      isCityLike: isCityLike,
      isLandmark: isLandmark,
    );

    // OSM «wikipedia» tag (lang:Title) is exact too.
    if (sum == null && wikiTag != null && wikiTag.contains(':')) {
      final i = wikiTag.indexOf(':');
      final l = wikiTag.substring(0, i).toLowerCase();
      final t = wikiTag.substring(i + 1);
      if (t.isNotEmpty && t.length < 120) {
        sum = await _summary(l, t);
      }
    }

    // The page lead image is exact (the page IS the place).
    final pageImage = sum?.image;

    // 3 ── collect the strict geosearch photos (already running).
    photos.addAll(await commonsF);

    // 4 ── Resolve File: titles → thumb URLs (ONE batched call) and the
    // flag/emblem thumbs — both branches were independent, now parallel.
    if (imageFile != null) files.add(imageFile);
    final thumbsF = _fileThumbs(files, 900);
    final flagThumbFile = flagFile == null
        ? null
        : (flagFile.startsWith('File:') ? flagFile : 'File:$flagFile');
    final emblemThumbFile = emblemFile == null
        ? null
        : (emblemFile.startsWith('File:') ? emblemFile : 'File:$emblemFile');
    final smallFiles = <String>{
      if (flagThumbFile != null) flagThumbFile,
      if (emblemThumbFile != null) emblemThumbFile,
    };
    final smallF = smallFiles.isEmpty
        ? Future<Map<String, String>>.value(const {})
        : _fileThumbs(smallFiles, 320, allowSvg: true);
    final thumbs = await thumbsF;
    if (imageFile != null) {
      final t = thumbs[imageFile.startsWith('File:') ? imageFile : 'File:$imageFile'];
      if (t != null) photos.insert(0, t);
    }
    if (imageUrl != null) photos.insert(0, imageUrl);
    // v6.7: the article image goes through the SAME junk filter the
    // geosearch photos do. Cities and companies lead with a locator map, a
    // coat of arms or a LOGO — and the user already banned exactly that
    // class («википедиа выдает про центр коммунны»). Flags and emblems have
    // their own slots, so nothing is lost here.
    if (pageImage != null && !_junkFile.hasMatch(Uri.tryParse(pageImage)?.path ?? pageImage)) {
      photos.removeWhere((p) => p == pageImage);
      photos.insert(imageUrl != null || imageFile != null ? 1 : 0, pageImage);
    }

    // Dedupe, cap the carousel.
    final seen = <String>{};
    final unique = <String>[];
    for (final p in photos) {
      if (seen.add(p)) unique.add(p);
      if (unique.length >= 8) break;
    }

    final small = await smallF;
    final wiki = PlaceWiki(
      description: sum?.description,
      extract: sum?.extract,
      pageUrl: sum?.pageUrl,
      flagUrl: flagThumbFile == null ? null : small[flagThumbFile],
      emblemUrl: emblemThumbFile == null ? null : small[emblemThumbFile],
      population: population,
      photos: unique,
    );
    return wiki.hasAny ? wiki : null;
  }

  /// Finds the wiki page of THIS place without a wikidata id:
  /// geosearch + strict title match, then a name search (also checked).
  /// Candidates are RANKED — «L'Arc de Triomphe, Wrapped» (the Christo
  /// art event) must never beat «Arc de triomphe de l'Étoile»: comma
  /// titles look like qualifiers for a DIFFERENT subject, and fewer
  /// extra words means a closer subject.
  Future<_Sum?> _pageByPlace({
    required double lat,
    required double lon,
    required String name,
    required List<String> langOrder,
    required bool isCityLike,
    required bool isLandmark,
  }) async {
    if (name.isEmpty || name.length < 3) return null;
    final radius = isCityLike
        ? 8000
        : isLandmark
            ? 600
            : 350;
    for (final lang in langOrder) {
      final titles = await _geoTitles(lang, lat, lon, radius);
      final cands = [
        for (final t in titles)
          if (nameMatches(name, t)) t,
      ];
      if (cands.isEmpty) continue;
      cands.sort((x, y) => _rankCand(name, x, y));
      for (final t in cands.take(2)) {
        final s = await _summary(lang, t);
        if (s != null) return s;
      }
    }
    // v6.7 GEO PROOF for name-only candidates. A full-text search has NO
    // geo bound: «Auchan» answers with the retail COMPANY article (HQ in
    // Roubaix) and its photo landed on a Bordeaux hypermarket card — the
    // «иногда не та информация и не те фотографии» report. A page reached
    // this way is accepted ONLY when the article's own coordinates are
    // actually at the tapped place; no coordinates → not the same place.
    final proofM = isCityLike ? 15000.0 : isLandmark ? 3000.0 : 1500.0;
    for (final lang in langOrder) {
      final titles = await _searchTitles(lang, name);
      final cands = [
        for (final t in titles)
          if (nameMatches(name, t)) t,
      ];
      if (cands.isEmpty) continue;
      cands.sort((x, y) => _rankCand(name, x, y));
      for (final t in cands.take(2)) {
        final s = await _summary(lang, t);
        if (s != null && _articleIsHere(s, lat, lon, proofM)) return s;
      }
    }
    return null;
  }

  /// Does this article describe the place at (lat, lon)?
  static bool _articleIsHere(_Sum s, double lat, double lon, double maxM) {
    final la = s.lat;
    final lo = s.lon;
    if (la == null || lo == null) return false;
    return _meters(lat, lon, la, lo) <= maxM;
  }

  static double _meters(double aLat, double aLon, double bLat, double bLon) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180.0;
    final dLat = rad(bLat - aLat);
    final dLon = rad(bLon - aLon);
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(aLat)) * math.cos(rad(bLat)) * math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.asin(math.min(1.0, math.sqrt(h)));
  }

  /// -1 when [x] is a better candidate than [y]: comma-free titles first,
  /// then fewer extra significant words, then shorter.
  int _rankCand(String name, String x, String y) {
    final cx = ','.allMatches(x).length;
    final cy = ','.allMatches(y).length;
    if (cx != cy) return cx - cy;
    final ex = _tokens(x).length - _tokens(name).length;
    final ey = _tokens(y).length - _tokens(name).length;
    if (ex != ey) return ex - ey;
    return x.length - y.length;
  }
}

/// v6.1: the parsed Wikidata entity (one wbgetentities response).
class _Ent {
  const _Ent({required this.claims, required this.sitelinks});
  final Map<String, dynamic> claims;
  final Map<String, dynamic> sitelinks;
}

/// Internal: one Wikipedia page summary.
class _Sum {
  const _Sum({
    required this.title,
    required this.lang,
    this.description,
    this.extract,
    this.image,
    this.pageUrl,
    this.lat,
    this.lon,
  });
  final String title;
  final String lang;
  final String? description;
  final String? extract;
  final String? image;
  final String? pageUrl;

  /// v6.7: the article's own geolocation (null when it has none) — the geo
  /// proof that a NAME-matched page is about THIS place.
  final double? lat;
  final double? lon;
}
