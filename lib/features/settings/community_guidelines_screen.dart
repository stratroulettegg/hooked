import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/apex_app_bar.dart';

/// Community-Regeln. Wird als interner Screen angezeigt — Inhalt entspricht
/// Apple Guideline 1.2 (UGC): klare Regeln, Melde-Mechanismus, Block-Funktion,
/// Null-Toleranz für anstößige Inhalte.
class CommunityGuidelinesScreen extends StatelessWidget {
  const CommunityGuidelinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Scaffold(
      appBar: const ApexAppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Community-Regeln',
            style: TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Hooked ist eine Community von Anglerinnen und Anglern. '
            'Damit der Feed für alle ein guter Ort bleibt, gelten klare Regeln.',
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          _Rule(
            icon: Icons.block,
            title: 'Null Toleranz für Hass und Hetze',
            body:
                'Rassismus, Antisemitismus, Holocaust-Leugnung, Sexismus, '
                'Homo- und Transphobie sowie verfassungsfeindliche Symbole '
                '(z. B. Hakenkreuz, SS-Runen) sind verboten — in Profil, '
                'Beiträgen, Kommentaren und Profilbildern. Verstöße führen '
                'zur sofortigen Sperrung des Accounts.',
          ),
          _Rule(
            icon: Icons.gavel_outlined,
            title: 'Keine illegalen Inhalte',
            body:
                'Keine Aufrufe zu Gewalt, kein Doxxing, keine Kinderpornografie, '
                'kein Drogenhandel, keine Urheberrechtsverletzungen. '
                'Inhalte werden gemeldet und gelöscht, Accounts bei Bedarf an '
                'Behörden weitergegeben.',
          ),
          _Rule(
            icon: Icons.eco_outlined,
            title: 'Tier- und Naturschutz respektieren',
            body:
                'Geltende Schonzeiten und Mindestmaße einhalten. Kein '
                'Quälen oder unnötiges Stressen von Fischen. Verzichte '
                'auf Inhalte, die offensichtlich gegen Tierschutzgesetze '
                'verstoßen.',
          ),
          _Rule(
            icon: Icons.shield_outlined,
            title: 'Respekt im Ton',
            body:
                'Beleidigungen, gezieltes Mobbing und Belästigung sind '
                'verboten. Auch Kritik geht respektvoll. Bleib sachlich, '
                'auch wenn du anderer Meinung bist.',
          ),
          _Rule(
            icon: Icons.flag_outlined,
            title: 'Inhalte melden',
            body:
                'Über das Drei-Punkte-Menü kannst du Beiträge, Kommentare '
                'und Profile melden. Wir prüfen jede Meldung und reagieren '
                'in der Regel innerhalb von 24 Stunden. Inhalte mit '
                'mehreren Meldungen werden automatisch ausgeblendet.',
          ),
          _Rule(
            icon: Icons.lock_outline,
            title: 'Nutzer blockieren',
            body:
                'Du kannst jeden Nutzer blockieren — du siehst dann keine '
                'Beiträge oder Kommentare mehr von ihm. Verwalte deine '
                'Block-Liste in den Einstellungen.',
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ApexColors.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ApexColors.primary.withAlpha(80)),
            ),
            child: Text(
              'Mit der Nutzung von Hooked akzeptierst du diese Regeln. '
              'Wer dauerhaft oder wiederholt verstößt, verliert sein Konto '
              'ohne Vorwarnung.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: c.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Stand: Mai 2026 · Kontakt: support@hooked-fangtagebuch.de',
            style: TextStyle(fontSize: 11, color: c.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: ApexColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Rajdhani',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
