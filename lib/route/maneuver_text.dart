/// v5.9: localized maneuver title — ONE source of text for BOTH the speech
/// (voice.dart) and the compact navigation sheet (route_panel.dart), so the
/// driver never hears one sentence and reads another.
library;

import '../core/strings.dart';

String maneuverTitle(String maneuverKey) {
  final parts = maneuverKey.split('|');
  final type = parts[0];
  final mod = parts.length > 1 ? parts[1] : '';
  switch (type) {
    case 'turn':
      return switch (mod) {
        'left' => S.of('turnLeft'),
        'right' => S.of('turnRight'),
        'sharp left' => S.of('turnSharpLeft'),
        'sharp right' => S.of('turnSharpRight'),
        'slight left' => S.of('slightLeft'),
        'slight right' => S.of('slightRight'),
        'straight' => S.of('straight'),
        'uturn' => S.of('uturn'),
        _ => S.of('straight'),
      };
    case 'new name':
    case 'continue':
      return S.of('straight');
    case 'roundabout' || 'rotary' || 'round about':
      return S.of('roundabout');
    case 'merge':
      return S.of('merge');
    case 'fork':
      return mod.contains('left') ? S.of('forkLeft') : S.of('forkRight');
    case 'exit roundabout' || 'exit rotary':
      return mod.contains('left') ? S.of('exitLeft') : S.of('exitRight');
    case 'on ramp':
      return mod.contains('left') ? S.of('slightLeft') : S.of('slightRight');
    case 'off ramp':
      return mod.contains('left') ? S.of('exitLeft') : S.of('exitRight');
    case 'arrive':
      return S.of('arriveFlag');
    default:
      return S.of('straight');
  }
}
