/// v5.9: интернет-обогащение карточки места — фотографии (Wikimedia
/// Commons) и подробности (OpenStreetMap через Nominatim: часы работы,
/// телефон, сайт, кухня…). Всё бесплатно и без ключей.
///
/// v6.1 CORRECTNESS («выбрал ресторан в Pessac Santocha, а в википедии
/// выдает про центр коммунны!»): Nominatim reverse возвращает объект,
/// БЛИЖАЙШИЙ к точке — это не всегда то место, по которому тапнули
/// (улица, коммуна, соседнее здание). Если имя тапнутого места и имя
/// объекта Nominatim РАСХОДЯТСЯ — все «личные» поля объекта (телефон,
/// сайт, часы, wikidata, image/wikipedia-теги) выбрасываются: они
/// принадлежат ДРУГОМУ объекту. Остаётся только позиционный адрес —
/// он верен для точки всегда. Меньше данных — но НИКОГДА не чужих
/// («главное чтобы правильно было»).
///
/// v6.1 SPEED: подробности и вики-обогащение отдаются как РАЗДЕЛЬНЫЕ
/// future (карточка показывает адрес/телефон сразу, как только пришёл
/// Nominatim, не дожидаясь фото и википедии) + кэш сессии: повторный
/// тап по тому же месту открывается мгновенно.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../route/overpass.dart';
import 'wiki.dart';

/// Подробности места, вытащенные из открытых источников.
class PlaceDetails {
  const PlaceDetails({
    this.address = '',
    this.name,
    this.openingHours,
    this.phone,
    this.website,
    this.cuisine,
    this.wheelchair,
    this.osmType,
    this.osmId,
    this.wikidata,
    this.imageTag,
    this.commonsTag,
    this.wikiTag,
    this.addrType,
    this.identityStripped = false,
  });

  final String address;

  /// OSM-имя объекта (иногда точнее, чем заголовок тайла).
  final String? name;
  final String? openingHours;
  final String? phone;
  final String? website;

  /// Кухня из тега cuisine (кафе/ресторан): «italian;pizza» → «italian».
  final String? cuisine;
  final String? wheelchair;

  /// OSM-идентификация объекта (для подгрузки полных тегов здания).
  final String? osmType;
  final int? osmId;

  // v6: точная идентификация места в Википедии/Викиданных.
  /// Q-id объекта («Q1479» = Бордо) — даёт ФЛАГ, ГЕРБ, население,
  /// точную статью википедии. Точный источник, проверка имени не нужна.
  final String? wikidata;

  /// OSM-тег image (URL или File:…) — фотография ИМЕННО этого объекта.
  final String? imageTag;

  /// OSM-тег wikimedia_commons (File:…) — файл Commons этого объекта.
  final String? commonsTag;

  /// OSM-тег wikipedia («ru:Бордо») — точная статья.
  final String? wikiTag;

  /// Nominatim addresstype (city / town / house…) — город ли это.
  final String? addrType;

  /// v6.1: true when the Nominatim object did NOT match the tapped name —
  /// all personal fields were dropped (they belonged to another object).
  final bool identityStripped;

  bool get hasAny =>
      address.isNotEmpty ||
      (name != null && name!.isNotEmpty) ||
      openingHours != null ||
      phone != null ||
      website != null ||
      cuisine != null ||
      wheelchair != null;
}

/// v6: единый бандл карточки — подробности OSM + вики-обогащение.
class PlaceBundle {
  const PlaceBundle({required this.details, this.wiki});
  final PlaceDetails details;
  final PlaceWiki? wiki;
}

/// v6.1: progressive load — the card shows each block the moment ITS
/// future resolves, instead of waiting for the whole bundle.
class SplitBundle {
  const SplitBundle({required this.details, required this.wiki});

  /// Address / hours / phone / website — usually first (one Nominatim
  /// call).
  final Future<PlaceDetails> details;

  /// Wikipedia block + photos — lands when the enrichment chain is done.
  final Future<PlaceWiki?> wiki;
}

class PlaceMedia {
  PlaceMedia({http.Client? client, Overpass? overpass, WikiService? wiki})
      : _client = client ?? http.Client(),
        _overpass = overpass ?? Overpass(),
        _wiki = wiki ?? WikiService(client: client);

  static const _ua = {
    // Same compliant UA as WikiService — Wikimedia 403s generic clients.
    'User-Agent':
        'Navigo/6.1 (https://github.com/navigo-navigator/navigo; '
        'navigo-navigator@users.noreply.github.com)',
  };

  final http.Client _client;
  final Overpass _overpass;
  final WikiService _wiki;

  /// v6.1: session cache — re-tapping the same place costs ZERO network.
  static final Map<String, PlaceBundle> _cache = {};

  // ── v6.2: THE NOMINATIM GATE ──────────────────────────────────────────
  // Nominatim's usage policy is max 1 request per second. Ten fast taps
  // used to fire ten reverse calls back-to-back → throttling → «инфа
  // грузится очень долго» and the dead-tap minute. Every details() call
  // goes through this serial gate: one request in flight, ≥1.05 s apart.
  static Future<void> _nomQueue = Future<void>.value();
  static DateTime _lastNom = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<T> _nominatimGate<T>(Future<T> Function() run) {
    final task = _nomQueue.then((_) async {
      final wait =
          const Duration(milliseconds: 1050) - DateTime.now().difference(_lastNom);
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
      _lastNom = DateTime.now();
      return run();
    });
    // The chain must survive failures of individual tasks.
    _nomQueue = task.then((_) {}, onError: (_) {});
    return task;
  }

  /// v6.1: ONE entry point, split into two futures for progressive UI.
  /// Every source degrades silently: сеть моргнула → карточка просто
  /// без фото / без адреса.
  SplitBundle bundleSplit({
    required double lat,
    required double lon,
    required String name,
    String? category,
    String locale = 'ru',
  }) {
    final key =
        '${lat.toStringAsFixed(5)}|${lon.toStringAsFixed(5)}|'
        '${name.trim().toLowerCase()}|$locale';
    final hit = _cache[key];
    if (hit != null) {
      return SplitBundle(
        details: Future<PlaceDetails>.value(hit.details),
        wiki: Future<PlaceWiki?>.value(hit.wiki),
      );
    }
    // The tile class of the TAP — «city» means the user tapped a city
    // label (translations of settlement names must not be stripped).
    final tapCls = (category ?? '').toLowerCase();
    final tappedCityLike = const [
      'city', 'town', 'village', 'hamlet', 'borough', 'suburb',
      'quarter', 'neighbourhood', 'municipality', 'capital',
    ].any(tapCls.contains);
    final detF = details(
      lat,
      lon,
      tappedName: name,
      tappedCityLike: tappedCityLike,
      locale: locale,
    );
    final wikiF = detF
        .then((det) => _enrichFor(
              lat: lat,
              lon: lon,
              tappedName: name,
              category: category,
              det: det,
              locale: locale,
            ))
        .catchError((_) => null);
    // Store for instant re-taps (bounded).
    Future.wait<dynamic>([detF, wikiF]).then((r) {
      if (_cache.length > 48) _cache.clear();
      _cache[key] = PlaceBundle(
        details: r[0] as PlaceDetails,
        wiki: r[1] as PlaceWiki?,
      );
    }).catchError((_) {});
    return SplitBundle(details: detF, wiki: wikiF);
  }

  /// Legacy wrapper (await-everything) — kept for compatibility.
  Future<PlaceBundle?> bundle({
    required double lat,
    required double lon,
    required String name,
    String? category,
    String locale = 'ru',
  }) async {
    final s = bundleSplit(
      lat: lat,
      lon: lon,
      name: name,
      category: category,
      locale: locale,
    );
    final det = await s.details;
    final wiki = await s.wiki;
    if (wiki == null && !det.hasAny) return null;
    return PlaceBundle(details: det, wiki: wiki);
  }

  Future<PlaceWiki?> _enrichFor({
    required double lat,
    required double lon,
    required String tappedName,
    required String? category,
    required PlaceDetails det,
    required String locale,
  }) async {
    final strip = det.identityStripped;
    // v6.1: the identity rule — see the file header. When Nominatim
    // returned a DIFFERENT object, its personal fields were already
    // stripped in [details]; the enrichment works with the TAPPED name.
    final effName = strip
        ? tappedName
        : (det.name?.isNotEmpty ?? false)
            ? det.name!
            : tappedName;
    try {
      return await _wiki.enrich(
        lat: lat,
        lon: lon,
        name: effName,
        category: category,
        wikidata: strip ? null : det.wikidata,
        imageTag: strip ? null : det.imageTag,
        commonsTag: strip ? null : det.commonsTag,
        wikiTag: strip ? null : det.wikiTag,
        addrType: strip ? null : det.addrType,
        locale: locale,
      );
    } catch (_) {
      return null;
    }
  }

  /// Адрес + полезные теги места через Nominatim reverse.
  ///
  /// [tappedName] — имя места, по которому тапнул юзер (с тайлов); когда
  /// оно задано и НЕ совпадает с именем найденного объекта, личные поля
  /// объекта выбрасываются (чужой телефон/сайт/вики — хуже, чем никаких).
  /// [tappedCityLike] — тапнули по подписи НАСЕЛЁННОГО ПУНКТА (класс тайла
  /// city/town/…): тогда перевод имени («Бордо» vs «Bordeaux») не считается
  /// рассогласованием.
  Future<PlaceDetails> details(
    double lat,
    double lon, {
    String? tappedName,
    bool tappedCityLike = false,
    String locale = 'ru',
  }) {
    // v6.2: behind the 1 req/s gate — rapid multi-tap can no longer trip
    // Nominatim throttling.
    return _nominatimGate<PlaceDetails>(
      () => _detailsUncached(lat, lon,
          tappedName: tappedName,
          tappedCityLike: tappedCityLike,
          locale: locale),
    );
  }

  Future<PlaceDetails> _detailsUncached(
    double lat,
    double lon, {
    String? tappedName,
    bool tappedCityLike = false,
    String locale = 'ru',
  }) async {
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse'
      '?lat=$lat&lon=$lon&format=jsonv2&zoom=18'
      '&addressdetails=1&extratags=1'
      '&accept-language=$locale',
    );
    try {
      final res = await _client
          .get(url, headers: _ua)
          .timeout(const Duration(seconds: 7));
      if (res.statusCode != 200) return const PlaceDetails();
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final addr = (j['address'] as Map?)?.cast<String, dynamic>() ?? const {};
      String two(String? a, String? b) =>
          [a, b].whereType<String>().where((s) => s.isNotEmpty).join(' ');
      final street =
          two(addr['road'] as String?, addr['house_number'] as String?);
      final city = (addr['city'] ?? addr['town'] ?? addr['village'] ??
              addr['municipality'])
          as String?;
      final postcode = addr['postcode'] as String?;
      final address = [
        if (street.isNotEmpty) street,
        if (postcode != null && city != null && city.isNotEmpty)
          '$postcode $city'
        else if (city != null && city.isNotEmpty) city,
      ].join(', ');

      final extra =
          (j['extratags'] as Map?)?.cast<String, dynamic>() ?? const {};
      String? pick(String a, String b) {
        final v = (extra[a] ?? extra[b]) as String?;
        return (v == null || v.isEmpty) ? null : v;
      }

      final osmName = (j['name'] as String?)?.trim();
      final tap = tappedName?.trim() ?? '';

      // ── v6.1 IDENTITY RULE ────────────────────────────────────────────
      // The tile gave us a name; Nominatim answered with a DIFFERENT one
      // (a street, the commune, a neighbour). Everything personal belongs
      // to that other object — keep the positional address only.
      // A city-like answer for a city-like tap is fine (the names may be
      // translations of each other — «Бордо» vs «Bordeaux»), a city for a
      // restaurant tap is NOT.
      final addrType = (j['addresstype'] as String?)?.trim() ?? '';
      final cityLike = const [
        'city', 'town', 'village', 'municipality', 'borough', 'suburb',
        'quarter', 'hamlet', 'neighbourhood', 'isolated_dwelling',
      ].any(addrType.toLowerCase().contains);
      final mismatch = tap.isNotEmpty &&
          osmName != null &&
          osmName.isNotEmpty &&
          !WikiService.nameMatches(tap, osmName) &&
          !(cityLike && tappedCityLike);
      if (mismatch) {
        // v6.7: the file header promises «остаётся только позиционный
        // адрес» — the old `const PlaceDetails()` threw the address away
        // too, so a mismatched tap showed an empty card instead of the
        // one fact that is always true for the tapped point.
        return PlaceDetails(address: address, identityStripped: true);
      }

      final cuisineRaw = pick('cuisine', 'cuisine:*');
      return PlaceDetails(
        address: address,
        name: osmName,
        openingHours: pick('opening_hours', 'opening_hours:url'),
        phone: pick('phone', 'contact:phone'),
        website: pick('website', 'contact:website'),
        cuisine: (cuisineRaw == null || cuisineRaw.isEmpty)
            ? null
            : cuisineRaw.split(';').first.trim(),
        wheelchair: pick('wheelchair', 'wheelchair:description'),
        osmType: j['osm_type'] as String?,
        osmId: (j['osm_id'] as num?)?.toInt(),
        wikidata: pick('wikidata', 'wikidata'),
        imageTag: pick('image', 'image'),
        commonsTag: pick('wikimedia_commons', 'wikimedia_commons'),
        wikiTag: pick('wikipedia', 'wikipedia'),
        addrType: addrType,
      );
    } catch (_) {
      return const PlaceDetails();
    }
  }

  /// Полные теги объекта OSM (здания: тип, этажи, высота). null → Overpass
  /// недоступен, карточка покажет то, что дали тайлы.
  Future<Map<String, dynamic>?> osmTags(String osmType, int osmId) async {
    final prefix = switch (osmType) {
      'relation' => 'r',
      'node' => 'n',
      _ => 'w',
    };
    final j = await _overpass.query(
      '[out:json][timeout:20];$prefix($osmId);out tags;',
      minGap: Duration.zero,
    );
    try {
      final elements = (j as Map?)?['elements'] as List?;
      if (elements == null || elements.isEmpty) return null;
      final el = elements.first as Map<String, dynamic>;
      final tags = el['tags'] as Map<String, dynamic>?;
      return tags;
    } catch (_) {
      return null;
    }
  }
}
