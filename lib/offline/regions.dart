/// Offline catalog (v5.4, expanded in v6.2): countries and their regions
/// with bounding boxes for the MapLibre offline pack downloader.
///
/// v6.2 («В оффлайн картах страны не все и расставь их по алфавиту а не
/// россия наверху!»): +29 countries (56 total) and every country carries a
/// stable [key] — the DISPLAY name is localized via strings (`c<key>`) and
/// the sheet sorts alphabetically by the user's language.
///
/// Names are NOT stored here anymore — only keys. Region names stay plain
/// strings (recognizable city/region names, mostly international form).
library;

class OfflineRegionInfo {
  const OfflineRegionInfo(this.name, this.south, this.west, this.north, this.east);

  final String name;

  /// Bounding box (slightly padded so the region fits with context).
  final double south, west, north, east;

  /// Rough diagonal size in km — used for the size hint chip.
  double get sizeKm {
    final cos = 0.0 + (1 - ((north + south) / 2 / 90) * ((north + south) / 2 / 90));
    final dLat = (north - south) * 111;
    final dLon = (east - west) * 111 * (cos < 0.05 ? 0.05 : cos);
    final d = (dLat > dLon ? dLat : dLon) * 1.4;
    return d < 0 ? 0 : d;
  }
}

class OfflineCountry {
  const OfflineCountry(this.key, this.regions);

  /// Stable id — the localized display name is `S.of('c$key')`.
  final String key;
  final List<OfflineRegionInfo> regions;
}

/// A curated catalog of the regions people actually navigate in. Bounding
/// boxes are approximate (±0.2°) — the downloader clips tiles to the box,
/// so a generous box only costs a few extra tiles at low zooms.
const List<OfflineCountry> kOfflineCountries = [
  // ── Europe ────────────────────────────────────────────────────────────
  OfflineCountry('Russia', [
    OfflineRegionInfo('Москва и Московская область', 54.3, 35.1, 57.1, 40.3),
    OfflineRegionInfo('Санкт-Петербург и область', 58.5, 28.4, 60.9, 33.5),
    OfflineRegionInfo('Сочи и побережье', 43.3, 38.8, 44.2, 40.5),
    OfflineRegionInfo('Крым и Севастополь', 44.3, 32.4, 46.3, 36.8),
    OfflineRegionInfo('Краснодарский край', 43.3, 37.3, 46.9, 41.5),
    OfflineRegionInfo('Ростовская область', 46.0, 38.3, 49.5, 43.0),
    OfflineRegionInfo('Калининградская область', 54.2, 19.4, 55.4, 22.9),
    OfflineRegionInfo('Нижегородская область', 54.3, 41.7, 58.4, 47.9),
    OfflineRegionInfo('Республика Татарстан', 53.2, 46.6, 56.9, 54.4),
    OfflineRegionInfo('Свердловская область', 56.1, 57.8, 61.6, 66.4),
    OfflineRegionInfo('Челябинская область', 52.6, 57.1, 56.6, 63.3),
    OfflineRegionInfo('Новосибирская область', 53.2, 75.5, 57.9, 85.2),
    OfflineRegionInfo('Иркутская область', 51.2, 95.3, 64.3, 109.6),
    OfflineRegionInfo('Приморский край', 42.2, 130.2, 48.5, 139.4),
    OfflineRegionInfo('Республика Башкортостан', 51.5, 53.2, 56.7, 60.1),
    OfflineRegionInfo('Самарская область', 52.4, 47.4, 54.6, 52.7),
  ]),
  OfflineCountry('Belarus', [
    OfflineRegionInfo('Вся страна (Минск и области)', 51.2, 23.1, 56.3, 32.8),
  ]),
  OfflineCountry('Ukraine', [
    OfflineRegionInfo('Вся страна', 44.3, 22.1, 52.4, 40.4),
    OfflineRegionInfo('Киев и центр', 49.9, 29.2, 51.3, 32.2),
  ]),
  OfflineCountry('Moldova', [
    OfflineRegionInfo('Кишинёв и центр', 46.6, 28.3, 47.5, 29.3),
  ]),
  OfflineCountry('France', [
    OfflineRegionInfo('Île-de-France (Париж)', 48.1, 1.4, 49.2, 3.6),
    OfflineRegionInfo('Provence-Alpes-Côte d’Azur', 42.9, 4.2, 45.3, 7.7),
    OfflineRegionInfo('Auvergne-Rhône-Alpes', 44.1, 2.1, 46.8, 7.9),
    OfflineRegionInfo('Occitanie', 42.3, -0.4, 44.9, 4.9),
    OfflineRegionInfo('Nouvelle-Aquitaine', 42.3, -1.8, 46.3, 2.7),
    OfflineRegionInfo('Grand Est', 47.4, 3.0, 49.9, 8.2),
    OfflineRegionInfo('Hauts-de-France', 48.8, 1.4, 51.1, 4.3),
    OfflineRegionInfo('Bretagne', 47.3, -4.8, 48.9, -0.9),
    OfflineRegionInfo('Normandie', 48.4, -2.0, 50.2, 1.9),
    OfflineRegionInfo('Corse', 41.3, 8.5, 43.1, 9.6),
  ]),
  OfflineCountry('Germany', [
    OfflineRegionInfo('Bayern', 47.3, 8.9, 50.6, 13.9),
    OfflineRegionInfo('Berlin и Brandenburg', 51.9, 12.0, 53.7, 14.8),
    OfflineRegionInfo('Baden-Württemberg', 47.5, 7.5, 49.8, 10.5),
    OfflineRegionInfo('Nordrhein-Westfalen', 50.3, 5.8, 52.6, 9.5),
    OfflineRegionInfo('Hessen', 49.4, 7.7, 51.7, 10.3),
    OfflineRegionInfo('Sachsen', 50.1, 11.8, 51.7, 15.1),
    OfflineRegionInfo('Hamburg и север', 53.1, 8.4, 54.4, 11.3),
    OfflineRegionInfo('Niedersachsen', 52.9, 6.4, 54.2, 11.6),
  ]),
  OfflineCountry('Italy', [
    OfflineRegionInfo('Lazio (Рим)', 41.1, 11.8, 42.9, 13.9),
    OfflineRegionInfo('Lombardia (Милан)', 44.6, 8.6, 46.7, 11.9),
    OfflineRegionInfo('Veneto (Венеция)', 44.7, 10.5, 46.7, 13.5),
    OfflineRegionInfo('Toscana (Флоренция)', 42.2, 9.6, 44.5, 12.4),
    OfflineRegionInfo('Campania (Неаполь)', 39.9, 13.6, 41.9, 15.9),
    OfflineRegionInfo('Sicilia', 36.6, 12.3, 38.3, 15.7),
    OfflineRegionInfo('Sardegna', 38.8, 8.1, 41.3, 10.1),
  ]),
  OfflineCountry('Spain', [
    OfflineRegionInfo('Cataluña (Барселона)', 40.5, -1.0, 42.9, 3.3),
    OfflineRegionInfo('Andalucía', 35.9, -6.9, 38.7, -1.6),
    OfflineRegionInfo('Comunidad de Madrid', 39.8, -4.6, 41.2, -3.0),
    OfflineRegionInfo('Comunitat Valenciana', 37.8, -1.0, 40.8, 0.7),
    OfflineRegionInfo('Islas Baleares', 38.4, 1.1, 40.2, 4.5),
    OfflineRegionInfo('Islas Canarias', 27.6, -18.4, 29.5, -13.3),
  ]),
  OfflineCountry('Portugal', [
    OfflineRegionInfo('Lisboa', 38.4, -9.5, 39.1, -8.7),
    OfflineRegionInfo('Algarve', 36.8, -9.1, 37.5, -7.4),
  ]),
  OfflineCountry('Poland', [
    OfflineRegionInfo('Małopolskie (Краков)', 49.0, 19.1, 50.6, 21.3),
    OfflineRegionInfo('Mazowieckie (Варшава)', 51.4, 19.1, 53.4, 22.9),
    OfflineRegionInfo('Dolnośląskie (Вроцлав)', 50.1, 15.0, 51.9, 17.3),
  ]),
  OfflineCountry('Czechia', [
    OfflineRegionInfo('Praha и Средняя Чехия', 49.5, 13.8, 50.7, 15.4),
  ]),
  OfflineCountry('Slovakia', [
    OfflineRegionInfo('Братислава и запад', 47.9, 16.8, 48.9, 17.9),
  ]),
  OfflineCountry('Austria', [
    OfflineRegionInfo('Wien и окрестности', 47.9, 15.8, 48.5, 16.9),
    OfflineRegionInfo('Tirol (Инсбрук)', 46.9, 10.1, 47.8, 12.9),
  ]),
  OfflineCountry('Switzerland', [
    OfflineRegionInfo('Zürich', 47.1, 8.4, 47.7, 9.0),
    OfflineRegionInfo('Genève', 46.1, 5.9, 46.4, 6.4),
  ]),
  OfflineCountry('Belgium', [
    OfflineRegionInfo('Bruxelles и центр', 50.4, 3.2, 51.4, 5.2),
  ]),
  OfflineCountry('Netherlands', [
    OfflineRegionInfo('Амстердам и Randstad', 51.9, 4.1, 53.1, 5.4),
  ]),
  OfflineCountry('United Kingdom', [
    OfflineRegionInfo('London', 51.3, -0.5, 51.7, 0.3),
    OfflineRegionInfo('Scotland (Edinburgh–Glasgow)', 55.4, -4.6, 56.4, -2.6),
  ]),
  OfflineCountry('Ireland', [
    OfflineRegionInfo('Дублин и восток', 52.9, -6.8, 53.7, -5.9),
  ]),
  OfflineCountry('Denmark', [
    OfflineRegionInfo('Вся страна (Копенгаген)', 54.4, 7.8, 57.9, 13.0),
  ]),
  OfflineCountry('Norway', [
    OfflineRegionInfo('Осло и юг', 58.8, 4.6, 60.5, 12.4),
  ]),
  OfflineCountry('Sweden', [
    OfflineRegionInfo('Stockholm', 59.1, 17.6, 59.7, 18.4),
    OfflineRegionInfo('Гётеборг и юг', 55.2, 10.9, 58.5, 17.4),
  ]),
  OfflineCountry('Finland', [
    OfflineRegionInfo('Helsinki', 59.9, 24.3, 60.6, 25.4),
  ]),
  OfflineCountry('Estonia', [
    OfflineRegionInfo('Таллин и север', 59.1, 24.1, 59.8, 25.6),
  ]),
  OfflineCountry('Latvia', [
    OfflineRegionInfo('Рига', 56.6, 23.7, 57.4, 24.8),
  ]),
  OfflineCountry('Lithuania', [
    OfflineRegionInfo('Вильнюс', 54.3, 24.7, 55.0, 25.8),
  ]),
  OfflineCountry('Greece', [
    OfflineRegionInfo('Афины и Аттика', 37.6, 23.4, 38.4, 24.2),
    OfflineRegionInfo('Крит', 34.8, 23.4, 35.8, 26.4),
  ]),
  OfflineCountry('Hungary', [
    OfflineRegionInfo('Будапешт', 47.1, 18.6, 47.8, 19.6),
  ]),
  OfflineCountry('Romania', [
    OfflineRegionInfo('Бухарест', 44.1, 25.7, 44.9, 26.5),
  ]),
  OfflineCountry('Bulgaria', [
    OfflineRegionInfo('София', 42.4, 22.8, 43.1, 23.8),
  ]),
  OfflineCountry('Serbia', [
    OfflineRegionInfo('Белград', 44.4, 20.1, 45.1, 20.9),
  ]),
  OfflineCountry('Croatia', [
    OfflineRegionInfo('Побережье (Истрия — Дубровник)', 42.2, 13.3, 45.7, 19.3),
  ]),
  OfflineCountry('Slovenia', [
    OfflineRegionInfo('Любляна и запад', 45.8, 13.7, 46.4, 15.0),
  ]),
  OfflineCountry('Montenegro', [
    OfflineRegionInfo('Побережье (Будва, Котор)', 41.7, 18.2, 42.7, 20.1),
  ]),

  // ── Asia / Middle East ────────────────────────────────────────────────
  OfflineCountry('Turkey', [
    OfflineRegionInfo('İstanbul', 40.6, 28.0, 41.6, 29.9),
    OfflineRegionInfo('Antalya и побережье', 36.0, 29.2, 37.5, 32.5),
    OfflineRegionInfo('Ankara', 38.7, 31.1, 40.9, 33.5),
    OfflineRegionInfo('İzmir', 37.7, 26.3, 39.5, 28.5),
    OfflineRegionInfo('Muğla (Бодрум, Мармарис)', 36.1, 27.1, 37.7, 29.3),
  ]),
  OfflineCountry('Georgia', [
    OfflineRegionInfo('Тбилиси и восток', 41.2, 43.9, 42.9, 46.8),
  ]),
  OfflineCountry('Armenia', [
    OfflineRegionInfo('Ереван и центр', 39.9, 43.8, 41.3, 45.5),
  ]),
  OfflineCountry('Azerbaijan', [
    OfflineRegionInfo('Баку', 40.1, 49.5, 40.8, 50.5),
  ]),
  OfflineCountry('Kazakhstan', [
    OfflineRegionInfo('Алматы и область', 42.6, 74.6, 45.2, 79.2),
    OfflineRegionInfo('Астана и север', 50.4, 69.4, 53.2, 73.6),
  ]),
  OfflineCountry('Uzbekistan', [
    OfflineRegionInfo('Ташкент', 40.9, 69.0, 41.5, 70.1),
  ]),
  OfflineCountry('Israel', [
    OfflineRegionInfo('Тель-Авив и Иерусалим', 31.5, 34.5, 32.3, 35.5),
  ]),
  OfflineCountry('UAE', [
    OfflineRegionInfo('Дубай и Шарджа', 24.0, 54.3, 25.4, 56.5),
  ]),
  OfflineCountry('India', [
    OfflineRegionInfo('Дели', 28.1, 76.6, 29.0, 77.7),
    OfflineRegionInfo('Гоа', 14.7, 73.5, 16.0, 74.5),
  ]),
  OfflineCountry('Thailand', [
    OfflineRegionInfo('Бангкок', 13.4, 100.2, 14.1, 100.9),
    OfflineRegionInfo('Пхукет', 7.7, 98.1, 8.3, 98.5),
    OfflineRegionInfo('Паттайя', 12.6, 100.6, 13.3, 101.2),
  ]),
  OfflineCountry('Vietnam', [
    OfflineRegionInfo('Ханой', 20.6, 105.5, 21.3, 106.1),
  ]),
  OfflineCountry('Indonesia', [
    OfflineRegionInfo('Бали', -8.9, 114.8, -8.3, 115.7),
  ]),
  OfflineCountry('China', [
    OfflineRegionInfo('Пекин', 39.5, 115.7, 40.3, 117.0),
    OfflineRegionInfo('Шанхай', 30.7, 121.0, 31.5, 122.0),
  ]),
  OfflineCountry('South Korea', [
    OfflineRegionInfo('Сеул', 37.1, 126.4, 37.9, 127.4),
  ]),
  OfflineCountry('Japan', [
    OfflineRegionInfo('Токио', 35.2, 139.2, 36.1, 140.3),
    OfflineRegionInfo('Осака и Киото', 34.3, 135.0, 35.3, 136.1),
  ]),

  // ── Africa ────────────────────────────────────────────────────────────
  OfflineCountry('Egypt', [
    OfflineRegionInfo('Каир и Гиза', 29.2, 30.9, 30.6, 31.9),
    OfflineRegionInfo('Хургада', 26.5, 33.3, 27.6, 34.4),
  ]),
  OfflineCountry('Morocco', [
    OfflineRegionInfo('Касабланка — Рабат', 33.0, -8.1, 34.1, -6.7),
    OfflineRegionInfo('Марракеш', 31.2, -8.3, 32.0, -7.2),
  ]),
  OfflineCountry('Tunisia', [
    OfflineRegionInfo('Тунис', 36.5, 9.8, 37.1, 10.5),
  ]),

  // ── Americas ──────────────────────────────────────────────────────────
  OfflineCountry('USA', [
    OfflineRegionInfo('New York metro', 40.4, -74.7, 41.4, -72.9),
    OfflineRegionInfo('California (юг, LA–San Diego)', 32.5, -119.2, 35.5, -114.1),
    OfflineRegionInfo('San Francisco Bay Area', 37.2, -122.8, 38.1, -121.8),
    OfflineRegionInfo('Chicago', 41.3, -88.3, 42.2, -87.3),
    OfflineRegionInfo('Seattle', 47.2, -122.8, 48.0, -121.9),
    OfflineRegionInfo('Florida', 24.5, -87.7, 31.0, -79.9),
    OfflineRegionInfo('Nevada (Las Vegas)', 35.0, -116.2, 37.2, -113.9),
  ]),
  OfflineCountry('Canada', [
    OfflineRegionInfo('Торонто', 43.3, -80.0, 44.1, -78.9),
    OfflineRegionInfo('Ванкувер', 48.9, -123.5, 49.5, -122.5),
  ]),
  OfflineCountry('Mexico', [
    OfflineRegionInfo('Мехико', 19.1, -99.5, 19.8, -98.8),
    OfflineRegionInfo('Канкун и Ривьера-Майя', 20.5, -87.5, 21.5, -86.5),
  ]),
  OfflineCountry('Brazil', [
    OfflineRegionInfo('Рио-де-Жанейро', -23.2, -43.5, -22.7, -42.9),
    OfflineRegionInfo('Сан-Паулу', -23.9, -47.0, -23.2, -46.2),
  ]),
  OfflineCountry('Argentina', [
    OfflineRegionInfo('Буэнос-Айрес', -35.0, -58.9, -34.3, -58.1),
  ]),
  OfflineCountry('Chile', [
    OfflineRegionInfo('Сантьяго', -33.8, -71.0, -33.2, -70.3),
  ]),

  // ── Oceania ───────────────────────────────────────────────────────────
  OfflineCountry('Australia', [
    OfflineRegionInfo('Сидней', -34.3, 150.5, -33.5, 151.5),
    OfflineRegionInfo('Мельбурн', -38.2, 144.5, -37.4, 145.4),
  ]),
];
