/// Place card: shows the picked POI / dropped pin / SELECTED BUILDING with
/// actions, live photos (Wikimedia Commons) and internet details (OSM).
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../places/photo_cache.dart';
import '../places/place_media.dart';
import '../places/wiki.dart';
import '../route/nav_notifications.dart';
import 'widgets.dart';

/// v5.9: what we know about a picked BUILDING («я сам выбрал на карте
/// какие будут») — filled by the map-tap flow from the tile metadata +
/// the real OSM tags.
class BuildingInfo {
  const BuildingInfo({this.type, this.levels, this.heightM});
  final String? type; // OSM building=* tag (apartments, house, retail…)
  final int? levels;
  final double? heightM;
}

Future<void> showPlaceSheet(
  BuildContext context,
  LuxPlace place, {
  required ValueChanged<LuxPlace> onRoute,
  ValueChanged<LuxPlace>? onPlan,
  BuildingInfo? building,
}) {
  return showLuxSheet(
    context: context,
    tag: 'place',
    builder: (_) => PlaceSheet(
      place: place,
      onRoute: onRoute,
      onPlan: onPlan,
      building: building,
    ),
  );
}

/// v5.9: THE CATEGORY ICON — the user was right: a shop card must show a
/// shop, a bar card must show a bar («если магазин то иконка магазина если
/// бар то иконка бара и так далее чтобы всё соответствовало!»). Maps the
/// OSM/tile class onto a concrete glyph.
IconData placeCategoryIcon(String cls) {
  final c = cls.toLowerCase();
  bool has(List<String> keys) => keys.any(c.contains);
  if (has(['bar', 'pub', 'wine', 'biergarten'])) {
    return Icons.local_bar_rounded;
  }
  if (has(['fast_food', 'burger', 'kebab', 'sandwich'])) {
    return Icons.lunch_dining_rounded;
  }
  if (has(['restaurant', 'food_court', 'food'])) {
    return Icons.restaurant_rounded;
  }
  if (has(['ice_cream'])) return Icons.icecream_rounded;
  if (has(['bakery', 'pastry', 'confectionery'])) {
    return Icons.bakery_dining_rounded;
  }
  if (has(['cafe', 'coffee', 'tea'])) return Icons.local_cafe_rounded;
  if (has([
    'supermarket', 'market', 'greengrocer', 'convenience',
    'department_store', 'mall', 'kiosk', 'newsstand', 'deli',
  ])) {
    return Icons.storefront_rounded;
  }
  if (has([
    'clothes', 'shoes', 'books', 'gift', 'jewelry', 'toys', 'florist',
    'hardware', 'optician', 'charity', 'boutique', 'stationery', 'shop',
  ])) {
    return Icons.shopping_bag_rounded;
  }
  if (has(['fuel', 'petrol', 'gas'])) return Icons.local_gas_station_rounded;
  if (has(['charging'])) return Icons.ev_station_rounded;
  if (has(['parking'])) return Icons.local_parking_rounded;
  if (has(['airport', 'aerodrome'])) return Icons.flight_rounded;
  if (has(['tram', 'light_rail'])) return Icons.tram_rounded;
  if (has(['subway', 'underground', 'metro'])) {
    return Icons.directions_subway_rounded;
  }
  if (has(['train', 'rail', 'station', 'halt'])) return Icons.train_rounded;
  if (has(['bus'])) return Icons.directions_bus_rounded;
  if (has(['ferry', 'dock'])) return Icons.directions_boat_rounded;
  if (has(['pharmacy', 'chemist'])) return Icons.local_pharmacy_rounded;
  if (has(['hospital', 'clinic'])) return Icons.local_hospital_rounded;
  if (has(['dentist', 'doctors', 'medical'])) {
    return Icons.medical_services_rounded;
  }
  if (has(['veterinary', 'pet'])) return Icons.pets_rounded;
  if (has(['hotel', 'hostel', 'motel', 'guest_house', 'lodging'])) {
    return Icons.hotel_rounded;
  }
  if (has(['bank', 'atm', 'bureau_de_change', 'money'])) {
    return Icons.account_balance_rounded;
  }
  if (has(['post'])) return Icons.local_post_office_rounded;
  if (has(['police'])) return Icons.local_police_rounded;
  if (has(['fire_station', 'ambulance', 'emergency'])) {
    return Icons.local_fire_department_rounded;
  }
  if (has(['museum', 'gallery', 'artwork', 'art_'])) return Icons.museum_rounded;
  if (has(['castle', 'fort'])) return Icons.castle_rounded;
  if (has(['theatre', 'theater'])) return Icons.theater_comedy_rounded;
  if (has(['cinema', 'movie'])) return Icons.movie_rounded;
  if (has(['attraction', 'tourist', 'monument', 'memorial', 'viewpoint'])) {
    return Icons.tour_rounded;
  }
  if (has(['mosque'])) return Icons.mosque_rounded;
  if (has(['synagogue'])) return Icons.synagogue_rounded;
  if (has(['church', 'place_of_worship', 'temple', 'chapel', 'religious'])) {
    return Icons.church_rounded;
  }
  if (has(['library'])) return Icons.local_library_rounded;
  if (has(['school', 'university', 'college', 'kindergarten', 'education'])) {
    return Icons.school_rounded;
  }
  if (has(['gym', 'fitness', 'sport'])) return Icons.fitness_center_rounded;
  if (has(['hairdresser', 'beauty', 'salon'])) return Icons.content_cut_rounded;
  if (has(['car_repair', 'car_wash', 'garage', 'tyre'])) {
    return Icons.car_repair_rounded;
  }
  if (has(['bicycle'])) return Icons.pedal_bike_rounded;
  if (has(['park', 'garden', 'playground', 'nature', 'pitch', 'forest'])) {
    return Icons.park_rounded;
  }
  if (has(['drinking_water', 'fountain', 'water'])) {
    return Icons.water_drop_rounded;
  }
  if (has(['government', 'courthouse', 'townhall', 'public_building'])) {
    return Icons.account_balance_rounded;
  }
  if (has(['office', 'company', 'estate'])) {
    return Icons.business_center_rounded;
  }
  return Icons.place_rounded;
}

/// v5.9: icon for the OSM building=* type of a picked footprint.
IconData buildingTypeIcon(String? type) {
  final t = (type ?? '').toLowerCase();
  if (t.contains('apart')) return Icons.apartment_rounded;
  if (t.contains('church') || t.contains('chapel')) {
    return Icons.church_rounded;
  }
  if (t.contains('retail') || t.contains('commercial') || t.contains('kiosk')) {
    return Icons.storefront_rounded;
  }
  if (t.contains('office')) return Icons.business_center_rounded;
  if (t.contains('industrial') ||
      t.contains('factory') ||
      t.contains('warehouse')) {
    return Icons.factory_rounded;
  }
  if (t.contains('hotel')) return Icons.hotel_rounded;
  if (t.contains('garage') || t.contains('carport')) {
    return Icons.garage_rounded;
  }
  if (t.contains('school') ||
      t.contains('university') ||
      t.contains('college')) {
    return Icons.school_rounded;
  }
  if (t.contains('hospital')) return Icons.local_hospital_rounded;
  if (t.contains('government') || t.contains('public')) {
    return Icons.account_balance_rounded;
  }
  if (t.contains('house') ||
      t.contains('detached') ||
      t.contains('bungalow') ||
      t.contains('terrace') ||
      t.contains('hut') ||
      t.contains('shed') ||
      t.contains('residential')) {
    return Icons.cottage_rounded;
  }
  return Icons.location_city_rounded;
}

class PlaceSheet extends StatefulWidget {
  const PlaceSheet({
    super.key,
    required this.place,
    required this.onRoute,
    this.onPlan,
    this.building,
  });

  final LuxPlace place;
  final ValueChanged<LuxPlace> onRoute;

  /// v5.3: opens the full «Откуда → Куда» planner with this place as the
  /// destination (change the start, swap the endpoints).
  final ValueChanged<LuxPlace>? onPlan;

  /// v5.9: building specifics when the user picked a footprint on the map.
  final BuildingInfo? building;

  @override
  State<PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends State<PlaceSheet> {
  /// v5.8: the pin color the user picked for this place (favorites).
  int _colorIdx = 0;

  /// v5.9: photo carousel position.
  int _photoPage = 0;

  /// v6.1: the photos that are STILL ALIVE — a URL that fails to download
  /// or decode is dropped from the carousel silently («многие фото не
  /// грузятся показывают битую иконку» — больше НИКОГДА: битой иконке
  /// здесь просто нечего показывать).
  List<String> _photos = const [];

  /// v6.2: THE FLASH-FIX («википедия и фото всплывают в одно время…
  /// сверху макет фото, потом он резко закрывается потому что нету фото»):
  /// candidate URLs join [_photos] ONLY after PhotoCache downloaded AND
  /// decoded the bytes. The section renders from [_photos] — an URL that
  /// never lands simply never shows, so the carousel can no longer pop in
  /// and collapse a second later.
  final Set<String> _queued = {};

  /// v6.7: the RANKED order of every photo candidate. The carousel is
  /// filled by this order — not by which download finished first, which
  /// used to make the same place show a different «первое фото» on every
  /// open («иногда не те фотографии»).
  final List<String> _photoOrder = [];

  /// v6.2: the LIVE header — an instantly-opened card («Выбранная точка»,
  /// «Здание») grows its real name + address when Nominatim answers.
  late String _name;
  late String _subtitle;

  /// v6.2: building specifics that grow when the full OSM tags arrive.
  late BuildingInfo? _bld;

  /// v6.2: the Wikipedia block as STATE (was a FutureBuilder): a pin or a
  /// building tapped WITHOUT a name can only run its strict wiki
  /// enrichment after Nominatim reveals the name — the card updates in
  /// place when that second pass answers.
  PlaceWiki? _wiki;

  /// v6.1: progressive load — details / wiki resolve independently, each
  /// block of the card appears the moment ITS data is ready («инфа
  /// грузится очень долго» — теперь адрес виден сразу, фото/вики
  /// подтягиваются в фоне).
  late final Future<PlaceDetails> _detF;
  late final Future<PlaceWiki?> _wikiF;

  @override
  void initState() {
    super.initState();
    final st = context.read<AppState>();
    for (final f in st.favorites) {
      if (f.name == widget.place.name &&
          (f.lat - widget.place.lat).abs() < 1e-6) {
        _colorIdx = f.colorIdx;
      }
    }
    _name = widget.place.name;
    _subtitle = widget.place.subtitle;
    _bld = widget.building;

    // v6.2: the tile name is authoritative only for POI taps. A bare pin
    // or a building centroid must NOT trip the identity rule — «Здание»
    // vs «12 rue Machin» is not a mismatch, it is the same object before
    // and after enrichment (and the stripped result would kill the
    // building's floors/height fetch entirely).
    // v6.7: a SEARCH pick is authoritative too — its name came from the
    // very object the user chose, so a reverse answer about a different
    // object must not decorate it with someone else's phone / hours / wiki.
    final guarded =
        widget.place.kind == 'poi' || widget.place.kind == 'place';
    final tappedName = guarded ? widget.place.name : '';

    if (st.onlineInfoOn) {
      final split = PlaceMedia().bundleSplit(
        lat: widget.place.lat,
        lon: widget.place.lon,
        name: tappedName,
        category: widget.place.kind == 'poi' ? widget.place.subtitle : null,
        locale: st.locale.languageCode,
      );
      _detF = split.details.timeout(
        const Duration(seconds: 10),
        onTimeout: () => const PlaceDetails(),
      );
      _wikiF = split.wiki.timeout(
        const Duration(seconds: 22),
        onTimeout: () => null,
      );
      // v6.2: the header grows in place — name + address land the moment
      // Nominatim answers, without ever delaying the card itself.
      _detF.then((det) {
        if (!mounted) return;
        setState(() {
          if (det.address.isNotEmpty) _subtitle = det.address;
          final n = det.name;
          if (n != null && n.isNotEmpty && _isGenericName(_name)) {
            _name = n;
          }
        });
        // Buildings additionally resolve the full OSM tags (type, floors,
        // exact height) — this is the fetch that used to BLOCK the tap
        // before the card was even allowed to appear.
        if (widget.place.kind == 'building' &&
            det.osmType != null &&
            det.osmId != null) {
          PlaceMedia()
              .osmTags(det.osmType!, det.osmId!)
              .then((tags) {
            if (!mounted || tags == null) return;
            final levels = int.tryParse('${tags['building:levels'] ?? ''}');
            final hRaw = '${tags['height'] ?? ''}'.replaceAll(',', '.');
            final h = double.tryParse(hRaw);
            final osmName = tags['name'] as String?;
            setState(() {
              if (osmName != null &&
                  osmName.isNotEmpty &&
                  _isGenericName(_name)) {
                _name = osmName;
              }
              _bld = BuildingInfo(
                type: tags['building'] as String?,
                levels: levels,
                heightM: h ?? _bld?.heightM,
              );
            });
          }).catchError((_) {});
        }
      }).catchError((_) {});
      // v6.2: the photo gate — candidates stream in and join the carousel
      // only as really-downloaded bytes; the wiki card lands here too.
      // ignore: discarded_futures
      _wikiF.then((w) {
        if (!mounted) return;
        setState(() => _wiki = w);
        _queuePhotos(w?.photos ?? const <String>[]);
        _lateWikiIfNeeded();
      });
    } else {
      _detF = Future<PlaceDetails>.value(const PlaceDetails());
      _wikiF = Future<PlaceWiki?>.value(null);
    }
  }

  /// v6.2: a bare pin / building footprint starts WITHOUT a name — the
  /// strict wiki match has nothing to hold on to. Once Nominatim reveals
  /// the object's name, run the enrichment again with it: monuments tapped
  /// as footprints keep their Wikipedia card (v6.0 «монументы пусть с
  /// википедии грузится» survives the instant-card redesign).
  void _lateWikiIfNeeded() {
    if (_wiki != null || widget.place.kind == 'poi') return;
    // ignore: discarded_futures
    _detF.then((det) {
      final n = det.name?.trim() ?? '';
      if (n.isEmpty || n.length < 3) return;
      final st = context.read<AppState>();
      PlaceMedia()
          .bundleSplit(
        lat: widget.place.lat,
        lon: widget.place.lon,
        name: n,
        category: det.addrType,
        locale: st.locale.languageCode,
      )
          .wiki
          .timeout(const Duration(seconds: 18), onTimeout: () => null)
          .then((w2) {
        if (!mounted || _wiki != null) return;
        setState(() => _wiki = w2);
        _queuePhotos(w2?.photos ?? const <String>[]);
      });
    }).catchError((_) {});
  }

  /// v6.2: names that a richer answer is allowed to replace.
  bool _isGenericName(String n) =>
      n.isEmpty || n == S.of('droppedPin') || n == S.of('building');

  /// v6.2: download every candidate; a URL joins [_photos] only when its
  /// bytes are in the cache — the section cannot flash and collapse.
  void _queuePhotos(List<String> urls) {
    for (final u in urls) {
      if (!_photoOrder.contains(u)) _photoOrder.add(u);
      if (_queued.contains(u)) continue;
      _queued.add(u);
      // ignore: discarded_futures
      PhotoCache.I.get(u).then((b) {
        if (!mounted) return;
        if (b == null) return; // dead URL — it was never shown at all
        if (_photos.contains(u)) return;
        final ordered = [..._photos, u]..sort(
          (x, y) =>
              _photoOrder.indexOf(x).compareTo(_photoOrder.indexOf(y)),
        );
        setState(() => _photos = ordered);
      });
    }
  }

  String _categoryLabel(String cls) {
    final c = cls.toLowerCase();
    if (c.contains('bar') || c.contains('pub') || c.contains('wine')) {
      return 'Бар';
    }
    if (c.contains('fast_food')) return 'Фастфуд';
    if (c.contains('restaurant') || c.contains('food')) return 'Ресторан';
    if (c.contains('cafe') || c.contains('coffee')) return 'Кафе';
    if (c.contains('bakery') || c.contains('pastry')) return 'Пекарня';
    if (c.contains('supermarket') ||
        c.contains('market') ||
        c.contains('greengrocer') ||
        c.contains('deli')) {
      return 'Магазин';
    }
    if (c.contains('fuel')) return 'АЗС';
    if (c.contains('charging')) return 'Электрозаправка';
    if (c.contains('parking')) return 'Парковка';
    if (c.contains('bus')) return 'Остановка';
    if (c.contains('tram')) return 'Трамвай';
    if (c.contains('subway') || c.contains('metro')) return 'Метро';
    if (c.contains('train') || c.contains('rail') || c.contains('station')) {
      return 'Станция';
    }
    if (c.contains('airport')) return 'Аэропорт';
    if (c.contains('pharmacy') || c.contains('chemist')) return 'Аптека';
    if (c.contains('hospital') || c.contains('clinic')) return 'Больница';
    if (c.contains('dentist') || c.contains('doctors') || c.contains('medical')) {
      return 'Медицина';
    }
    if (c.contains('hotel') || c.contains('hostel') || c.contains('motel')) {
      return 'Отель';
    }
    if (c.contains('bank') || c.contains('atm')) return 'Банк';
    if (c.contains('post')) return 'Почта';
    if (c.contains('police')) return 'Полиция';
    if (c.contains('library')) return 'Библиотека';
    if (c.contains('school') ||
        c.contains('university') ||
        c.contains('college')) {
      return 'Образование';
    }
    if (c.contains('gym') || c.contains('fitness') || c.contains('sport')) {
      return 'Спорт';
    }
    if (c.contains('hairdresser') || c.contains('beauty')) {
      return 'Салон красоты';
    }
    if (c.contains('car_repair') || c.contains('car_wash')) {
      return 'Автосервис';
    }
    if (c.contains('veterinary')) return 'Ветклиника';
    if (c.contains('museum') || c.contains('gallery') || c.contains('artwork')) {
      return 'Музей';
    }
    if (c.contains('castle') || c.contains('fort')) return 'Замок';
    if (c.contains('theatre') || c.contains('theater')) return 'Театр';
    if (c.contains('cinema')) return 'Кинотеатр';
    if (c.contains('attraction') ||
        c.contains('tourist') ||
        c.contains('monument') ||
        c.contains('memorial')) {
      return 'Достопримечательность';
    }
    if (c.contains('mosque')) return 'Мечеть';
    if (c.contains('synagogue')) return 'Синагога';
    if (c.contains('church') ||
        c.contains('place_of_worship') ||
        c.contains('temple')) {
      return 'Храм';
    }
    if (c.contains('park') ||
        c.contains('garden') ||
        c.contains('playground') ||
        c.contains('nature')) {
      return 'Парк';
    }
    if (c == 'shop' || c.contains('shop') || c.contains('clothes')) {
      return 'Магазин';
    }
    return 'Место';
  }

  Future<void> _launch(String url) async {
    try {
      // v6 BUGFIX: a «tel:» row used to open the BROWSER (the helper
      // blindly prefixed https://) — «Телефон при тапе открывает сайт
      // исправь!» Now tel:/mailto: go straight to the OS handler.
      final Uri u;
      if (url.startsWith('tel:') || url.startsWith('mailto:')) {
        u = Uri.parse(url);
      } else {
        u = Uri.parse(url.startsWith('http') ? url : 'https://$url');
      }
      await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of('error')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    // watch (not read): the Home / Work chips must flip to their ✓ state
    // the moment the user taps them.
    final state = context.watch<AppState>();
    final place = widget.place;
    final isFav = state.isFavorite(place);
    final isBuilding = widget.building != null || place.kind == 'building';

    // The headline icon: category glyph (shop → shop, bar → bar…), building
    // glyph for footprints; ONLY a bare dropped pin keeps the classic pin.
    // v6.2: the building glyph refines itself when the OSM tags arrive.
    final IconData headIcon = isBuilding
        ? buildingTypeIcon(_bld?.type)
        : (place.kind == 'poi'
            ? placeCategoryIcon(place.subtitle)
            : Icons.place_rounded);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── v6.2 LIVE PHOTOS — pages join the carousel ONLY after their
        // bytes are downloaded and decoded (see _queuePhotos). The section
        // can neither flash-and-collapse nor show a broken icon; while the
        // first photo travels the card simply has no photo section.
        if (_photos.isNotEmpty) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 176,
                child: Stack(
                  children: [
                    PageView.builder(
                      itemCount: _photos.length,
                      onPageChanged: (i) => setState(() {
                        _photoPage = i.clamp(0, _photos.length - 1);
                      }),
                      itemBuilder: (context, i) {
                        // Capture the URL at build time — the dead-callback
                        // must remove THIS url, not whatever moved into i.
                        final url = _photos[i];
                        return _CachedPhoto(
                          key: ValueKey(url),
                          url: url,
                          onDead: () {
                            if (!mounted) return;
                            setState(() {
                              _photos = List.of(_photos)..remove(url);
                              if (_photoPage >= _photos.length) {
                                _photoPage =
                                    (_photos.length - 1).clamp(0, 1 << 30);
                              }
                            });
                          },
                        );
                      },
                    ),
                    // Page counter badge.
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_photoPage + 1}/${_photos.length}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: t.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(headIcon, color: t.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // v6.2: the LIVE name — generic titles grow into the real
                  // OSM name the moment it arrives.
                  Text(
                    _name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  // v6.2: the LIVE subtitle — for a POI the category label,
                  // otherwise the address that Nominatim fills in (a pin
                  // starts with raw coordinates and upgrades itself).
                  if (place.kind == 'poi'
                      ? place.subtitle.isNotEmpty
                      : (isBuilding && _subtitle.isEmpty
                          ? true
                          : _subtitle.isNotEmpty))
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        place.kind == 'poi'
                            ? _categoryLabel(place.subtitle)
                            : (isBuilding && _subtitle.isEmpty
                                ? S.of('buildingPickSub')
                                : _subtitle),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: t.textMuted),
                      ),
                    ),
                  Text(
                    '${place.lat.toStringAsFixed(5)}, ${place.lon.toStringAsFixed(5)}',
                    style: TextStyle(fontSize: 11.5, color: t.textMuted),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: S.of('favorites'),
              onPressed: () => state.toggleFavorite(
                place,
                colorIdx: _colorIdx,
              ),
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Icon(
                  isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  key: ValueKey(isFav),
                  color: isFav ? kFavPinColors[_colorIdx.clamp(0, kFavPinColors.length - 1)] : t.textMuted,
                ),
              ),
            ),
          ],
        ),

        // ── v6: THE WIKI BLOCK — description, story, flag, coat of arms,
        // population («когда тапаю по городам можно и с википедии в
        // карточки выводить инфу … флаг герб … максимально премиум!»).
        // v6.2: from state — a nameless pin/building gets its wiki when
        // the late enrichment pass answers (see _lateWikiIfNeeded).
        if (_wiki != null && _wiki!.hasAny)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _WikiCard(
              wiki: _wiki!,
              onOpen: _wiki!.pageUrl == null
                  ? null
                  : () => _launch(_wiki!.pageUrl!),
            ),
          ),

        // ── v5.9: building stat chips (этажи · высота) — v6.2: from the
        // LIVE _bld state (the tile height shows immediately, the real
        // OSM floors/height land when Overpass answers).
        if (isBuilding &&
            ((_bld?.levels ?? 0) > 0 || (_bld?.heightM ?? 0) > 0)) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              if ((_bld?.levels ?? 0) > 0)
                _InfoChip(
                  icon: Icons.layers_rounded,
                  label: '${S.of('floors')}: ${_bld!.levels}',
                ),
              if ((_bld?.levels ?? 0) > 0 && (_bld?.heightM ?? 0) > 0)
                const SizedBox(width: 8),
              if ((_bld?.heightM ?? 0) > 0)
                _InfoChip(
                  icon: Icons.height_rounded,
                  label:
                      '${S.of('heightM')}: ${_bld!.heightM!.round()} ${S.of('m')}',
                ),
            ],
          ),
        ],

        const SizedBox(height: 14),
        // v5: home / work can finally be SET from this card (the missing
        // entry point — the user could never add the house / work icons).
        Row(
          children: [
            Expanded(
              child: _SaveChip(
                icon: Icons.home_rounded,
                label: S.of('home'),
                active: state.home != null &&
                    (state.home!.lat - place.lat).abs() < 1e-6 &&
                    (state.home!.lon - place.lon).abs() < 1e-6,
                onTap: () {
                  state.setHome(
                    place.copyWith(name: place.name, kind: 'home'),
                  );
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(S.of('homeSet')),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SaveChip(
                icon: Icons.work_rounded,
                label: S.of('work'),
                active: state.work != null &&
                    (state.work!.lat - place.lat).abs() < 1e-6 &&
                    (state.work!.lon - place.lon).abs() < 1e-6,
                onTap: () {
                  state.setWork(
                    place.copyWith(name: place.name, kind: 'work'),
                  );
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(S.of('workSet')),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ),
          ],
        ),

        // ── v5.9: the pin COLOR picker — shown ONLY for favorites with an
        // explicit caption. The user asked «что означают цвета на этом
        // окне? там 7 разных цветов зачем они?» — now the row appears only
        // when it actually does something (после сохранения в избранное).
        if (isFav) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 30,
            child: Row(
              children: [
                Text(
                  S.of('pinColor'),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: t.textMuted,
                  ),
                ),
                const Spacer(),
                for (var i = 0; i < kFavPinColors.length; i++)
                  GestureDetector(
                    onTap: () {
                      final wasFav = state.isFavorite(place);
                      final prev = _colorIdx;
                      setState(() => _colorIdx = i);
                      if (wasFav && prev != i) {
                        // Re-color live: remove + re-add with the new color.
                        state.toggleFavorite(place);
                        state.toggleFavorite(place, colorIdx: i);
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(left: 6),
                      width: _colorIdx == i ? 28 : 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: kFavPinColors[i],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _colorIdx == i
                              ? t.onBackground
                              : Colors.white.withValues(alpha: 0.85),
                          width: _colorIdx == i ? 2.4 : 2,
                        ),
                      ),
                      child: _colorIdx == i
                          ? const Icon(Icons.check_rounded,
                              size: 14, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ],

        // ── v5.9: INTERNET DETAILS (hours · phone · website · address) ────
        // v6.1: progressive — lands as soon as Nominatim answers, it no
        // longer waits for photos / Wikipedia to finish.
        FutureBuilder<PlaceDetails>(
          future: _detF,
          builder: (context, snap) {
            final det = snap.data;
            if (snap.connectionState != ConnectionState.done ||
                det == null ||
                !det.hasAny) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: t.surfaceAlt,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: t.outline.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    if (det.address.isNotEmpty)
                      _InfoRow(
                        icon: Icons.location_on_rounded,
                        label: det.address,
                      ),
                    if (det.openingHours != null)
                      _InfoRow(
                        icon: Icons.schedule_rounded,
                        label: '${S.of('openingHours')}: ${det.openingHours}',
                      ),
                    if (det.cuisine != null)
                      _InfoRow(
                        icon: Icons.restaurant_menu_rounded,
                        label: det.cuisine!,
                      ),
                    if (det.phone != null)
                      _InfoRow(
                        icon: Icons.call_rounded,
                        label: '${S.of('phone')}: ${det.phone}',
                        value: det.phone,
                        onTap: () => _launch(
                          'tel:${det.phone!.replaceAll(RegExp(r'[^+\d]'), '')}',
                        ),
                      ),
                    if (det.website != null)
                      _InfoRow(
                        icon: Icons.language_rounded,
                        label:
                            '${S.of('website')}: ${Uri.tryParse(det.website!)?.host ?? det.website}',
                        value: det.website,
                        onTap: () => _launch(det.website!),
                      ),
                  ],
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 10),
        PrimaryButton(
          label: S.of('routeTo'),
          icon: Icons.navigation_rounded,
          onTap: () {
            Navigator.of(context).pop();
            widget.onRoute(place);
          },
        ),
        if (widget.onPlan != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: t.outline),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                widget.onPlan!(place);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.alt_route_rounded,
                      size: 18, color: t.textMuted),
                  const SizedBox(width: 8),
                  Text(
                    S.of('planRoute'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t.onBackground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        // v5.8: SHARE — the system sheet with the place name + geo link.
        SizedBox(
          height: 44,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: t.outline),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () => NavNotifications.shareText(
              place.name,
              '${place.name}\n'
              'https://www.openstreetmap.org/?mlat=${place.lat}&mlon=${place.lon}#map=17/${place.lat}/${place.lon}',
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.share_rounded, size: 18, color: t.textMuted),
                const SizedBox(width: 8),
                Text(
                  S.of('share'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.onBackground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// v6.1: ONE carousel page. Downloads through [PhotoCache] (disk +
/// memory), shows the glowing shimmer while the real bytes are on their
/// way («пока фото не появилось делай заглушку светящуюся»), and if the
/// download/decode FAILS the page removes itself — the broken-image icon
/// can no longer exist in this UI.
class _CachedPhoto extends StatefulWidget {
  const _CachedPhoto({
    super.key,
    required this.url,
    required this.onDead,
  });

  final String url;
  final VoidCallback onDead;

  @override
  State<_CachedPhoto> createState() => _CachedPhotoState();
}

class _CachedPhotoState extends State<_CachedPhoto> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await PhotoCache.I.get(widget.url);
    if (!mounted) return;
    if (b == null) {
      // A dead URL is silently removed from the carousel by the parent.
      widget.onDead();
      return;
    }
    setState(() => _bytes = b);
  }

  @override
  Widget build(BuildContext context) {
    final b = _bytes;
    if (b == null) {
      // Real photo incoming — the glowing placeholder lives INSIDE the
      // section, never instead of it.
      return const _ShimmerBox(height: double.infinity, radius: 0);
    }
    return Image.memory(
      b,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) {
        // Decoding failed although the download succeeded — same rule:
        // drop the page instead of showing a broken icon.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onDead();
        });
        return const SizedBox.shrink();
      },
    );
  }
}

/// v6: a GLOWING skeleton placeholder — the user: «пока фото не появилось
/// делай заглушку светящуюся чтобы видно было что загрузка идет». A soft
/// base + a light sweep that runs while the network works.
class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox({
    required this.height,
    required this.radius,
  });

  final double height;
  final double radius;

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final glow = t.primary.withValues(alpha: 0.16);
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Container(
        height: widget.height,
        color: t.surfaceAlt,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => LayoutBuilder(
            builder: (context, box) {
              // The sweep travels from -40% to +140% of the width.
              final w = box.maxWidth;
              final dx = -0.4 * w + 1.8 * w * _c.value;
              return Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          glow.withValues(alpha: 0.0),
                          glow,
                          Colors.white.withValues(alpha: t.isDark ? 0.06 : 0.55),
                          glow,
                          glow.withValues(alpha: 0.0),
                        ],
                        stops: const [0.0, 0.32, 0.5, 0.68, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    left: dx,
                    top: 0,
                    bottom: 0,
                    width: w * 0.7,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.transparent,
                              Colors.white.withValues(
                                  alpha: t.isDark ? 0.10 : 0.75),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// v6: THE WIKI CARD — what Wikipedia / Wikidata know about the place:
/// one-line description, a short story, the flag + coat of arms of a city
/// and its population. Tap the header to open the full article.
class _WikiCard extends StatelessWidget {
  const _WikiCard({required this.wiki, this.onOpen});

  final PlaceWiki wiki;
  final VoidCallback? onOpen;

  String _fmt(int n) =>
      n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ' ');

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.outline.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: source + open-the-article action.
          InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(10),
            child: Row(
              children: [
                Icon(Icons.menu_book_rounded, size: 16, color: t.primary),
                const SizedBox(width: 7),
                Text(
                  S.of('fromWikipedia'),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: t.primary,
                  ),
                ),
                const Spacer(),
                if (onOpen != null) ...[
                  Text(
                    S.of('readMore'),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: t.primary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded,
                      size: 17, color: t.primary),
                ],
              ],
            ),
          ),
          // Flag + coat of arms + the one-line description.
          if (wiki.flagUrl != null ||
              wiki.emblemUrl != null ||
              (wiki.description != null && wiki.description!.isNotEmpty) ||
              wiki.population != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (wiki.flagUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Image.network(
                      wiki.flagUrl!,
                      width: 42,
                      height: 28,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                if (wiki.flagUrl != null && wiki.emblemUrl != null)
                  const SizedBox(width: 8),
                if (wiki.emblemUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      wiki.emblemUrl!,
                      width: 30,
                      height: 30,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                if ((wiki.flagUrl != null || wiki.emblemUrl != null) &&
                    (wiki.description != null && wiki.description!.isNotEmpty))
                  const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (wiki.description != null &&
                          wiki.description!.isNotEmpty)
                        Text(
                          wiki.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      if (wiki.population != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.groups_rounded,
                                size: 13, color: t.textMuted),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '${S.of('population')}: ${_fmt(wiki.population!)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: t.textMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
          // The story.
          if (wiki.extract != null && wiki.extract!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              wiki.extract!,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: t.onBackground.withValues(alpha: 0.88),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// v5.9: one tappable detail row inside the info card.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;

  /// When set the whole row is a launch action (tel / website).
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: onTap != null ? t.primary : t.textMuted,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: onTap != null ? FontWeight.w600 : FontWeight.w500,
                  color: onTap != null ? t.primary : t.onBackground,
                ),
              ),
            ),
            if (onTap != null)
              Icon(Icons.open_in_new_rounded, size: 14, color: t.primary),
          ],
        ),
      ),
    );
  }
}

/// v5.9: small stat chip (этажей / высота) on the building card.
class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: t.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: t.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip that assigns the place as home / work. Green/red accents mirror the
/// map icons (lux-home / lux-work) so the connection is obvious.
class _SaveChip extends StatelessWidget {
  const _SaveChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final accent = icon == Icons.home_rounded
        ? const Color(0xFF2E9E62)
        : const Color(0xFFE2543E);
    return Material(
      color: active ? accent.withValues(alpha: 0.16) : t.surfaceAlt,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? accent : t.outline.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: active ? accent : t.textMuted),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  active ? '${S.of('set')} ✓' : label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                    color: active ? accent : t.onBackground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
