import 'package:shared_preferences/shared_preferences.dart';

/// Persistierter „DB-Anker": die UID, auf die der lokale `apex_<uid>.db`-
/// Slot und der `<docs>/photos/<uid>/`-Ordner aktuell zeigen.
///
/// Hintergrund: Der Firebase-Auth-User kann sich vom DB-Anker
/// unterscheiden — z.B. nach `signOut()` (User=null, lokale Daten sollen
/// trotzdem sichtbar bleiben) oder bei Cold-Restart, wenn
/// `ensureSignedIn()` einen frischen anonymen User anlegt, der nichts
/// mit den lokalen Bestandsdaten zu tun hat.
///
/// Regel für Anker-Updates:
/// - **Initial**: Beim ersten Aktivieren wird die aktuelle Firebase-UID
///   gespeichert (anonym oder echt — egal).
/// - **Sticky**: Solange ein Anker existiert, bleibt er, auch wenn
///   Firebase eine neue Session (anon nach signOut) bringt.
/// - **Update nur bei explizitem Account-Wechsel**: Wenn der User sich
///   in einen *echten* (nicht-anonymen) Account einloggt, dessen UID vom
///   Anker abweicht, wird der Anker auf die neue UID umgesetzt — und der
///   DB-Slot wechselt mit.
class LocalDbAnchor {
  LocalDbAnchor._();

  static const _key = 'local_db_anchor_uid_v1';
  static const _prevAnonKey = 'local_db_previous_anon_uid_v1';
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _p =>
      _prefs ?? (throw StateError('LocalDbAnchor.init() not called'));

  static String? get value => _p.getString(_key);

  static Future<void> set(String uid) => _p.setString(_key, uid);

  static Future<void> clear() => _p.remove(_key);

  /// UID des Anon-Users, der **vor** dem letzten Login aktiv war.
  /// Wird beim Wechsel anon→echt gesetzt und beim Logout (echt→anon)
  /// wieder benutzt, damit der ursprüngliche Anon-DB-Slot wiederhergestellt
  /// werden kann (statt einen frischen, leeren Anon-Slot anzuzeigen oder
  /// — schlimmer — auf der DB des soeben abgemeldeten Users zu bleiben).
  static String? get previousAnonUid => _p.getString(_prevAnonKey);

  static Future<void> setPreviousAnonUid(String uid) =>
      _p.setString(_prevAnonKey, uid);

  static Future<void> clearPreviousAnonUid() => _p.remove(_prevAnonKey);
}
