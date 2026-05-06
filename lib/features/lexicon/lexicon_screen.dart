import 'package:flutter/material.dart';

import '../../core/engines/predator_score_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/apex_app_bar.dart';
import 'species_lexicon.dart';

/// Lexikon der im Predator-Index aufgeführten Fischarten.
class LexiconScreen extends StatelessWidget {
  const LexiconScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final entries = SpeciesLexicon.entries;

    return Scaffold(
      appBar: const ApexAppBar(),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: entries.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          if (i == 0) return _Header(c: c);
          final e = entries[i - 1];
          return _SpeciesCard(entry: e);
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.c});
  final ApexColors c;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.menu_book_rounded, color: ApexColors.primary, size: 28),
            const SizedBox(width: 10),
            Text(
              'Fischlexikon',
              style: TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Quick-Tipps & Fakten zu jeder Art im Predator-Index. '
          'Tippe eine Karte, um Details zu sehen.',
          style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _SpeciesCard extends StatelessWidget {
  const _SpeciesCard({required this.entry});
  final SpeciesLexiconEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => _SpeciesDetailScreen(entry: entry)),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.border),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                  ),
                  child: Container(
                    width: 130,
                    color: ApexColors.primary.withAlpha(20),
                    child: Image.asset(
                      entry.imagePath,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.set_meal,
                        color: ApexColors.primary,
                        size: 28,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.profile.name,
                                style: TextStyle(
                                  fontFamily: 'Rajdhani',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: c.textPrimary,
                                ),
                              ),
                              Text(
                                entry.latin,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  color: c.textMuted,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                entry.summary,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: c.textSecondary,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: c.textMuted),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SpeciesDetailScreen extends StatelessWidget {
  const _SpeciesDetailScreen({required this.entry});
  final SpeciesLexiconEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final p = entry.profile;
    return Scaffold(
      appBar: const ApexAppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Header (Bild oben, voll-Breite)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: ApexColors.primary.withAlpha(20),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.asset(
                  entry.imagePath,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.set_meal, color: ApexColors.primary, size: 64),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: TextStyle(
                    fontFamily: 'Rajdhani',
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                Text(
                  entry.latin,
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: c.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  entry.summary,
                  style: TextStyle(
                    fontSize: 13,
                    color: c.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Quick-Fakten Grid
          _SectionTitle(title: 'STECKBRIEF', c: c),
          const SizedBox(height: 8),
          _FactGrid(
            rows: [
              _FactRow(
                icon: Icons.thermostat,
                label: 'Optimale Temperatur',
                value: '${p.tempOptMin.round()} – ${p.tempOptMax.round()} °C',
              ),
              _FactRow(
                icon: Icons.access_time,
                label: 'Tageszeit',
                value: _activityLabel(p),
              ),
              _FactRow(
                icon: Icons.compress,
                label: 'Druck-Reaktion',
                value: _pressureLabel(p.pressureSensitivity),
              ),
              _FactRow(
                icon: Icons.water,
                label: 'Trübungstoleranz',
                value: _turbidityLabel(p.turbidityTolerance),
              ),
              _FactRow(
                icon: Icons.air,
                label: 'Wind-Grenze',
                value: '${p.windMax.round()} km/h',
              ),
              if (entry.recordSizeCm != null)
                _FactRow(
                  icon: Icons.straighten,
                  label: 'Größe (Maximum)',
                  value: 'bis ~${entry.recordSizeCm} cm',
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Habitat & Saison
          _InfoBlock(
            c: c,
            icon: Icons.terrain,
            title: 'Habitat',
            text: entry.habitat,
          ),
          const SizedBox(height: 10),
          _InfoBlock(
            c: c,
            icon: Icons.calendar_month,
            title: 'Beste Saison',
            text: entry.bestSeason,
          ),
          const SizedBox(height: 14),

          // Köder
          _SectionTitle(title: 'TOP-KÖDER', c: c),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: entry.topLures
                .map((l) => _LureChip(label: l, c: c))
                .toList(),
          ),
          const SizedBox(height: 18),

          // Tipps
          _SectionTitle(title: 'QUICK-TIPPS', c: c),
          const SizedBox(height: 8),
          ...entry.tips.map((t) => _TipRow(text: t, c: c)),
          const SizedBox(height: 18),

          // Recht
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.gavel, color: c.textMuted, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.legalNote,
                    style: TextStyle(
                      fontSize: 11,
                      color: c.textMuted,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _activityLabel(SpeciesProfile p) {
    final values = <(String, double)>[
      ('Morgendämmerung', p.dawnWeight),
      ('Abenddämmerung', p.duskWeight),
      ('Nacht', p.nightWeight),
    ];
    values.sort((a, b) => b.$2.compareTo(a.$2));
    final top = values.where((e) => e.$2 >= 1.4).map((e) => e.$1).toList();
    if (top.isEmpty) return 'Tagaktiv';
    return top.join(' & ');
  }

  String _pressureLabel(double s) {
    if (s >= 0.8) return 'Sehr hoch (physoclist)';
    if (s >= 0.6) return 'Hoch';
    if (s >= 0.4) return 'Mittel';
    return 'Gering';
  }

  String _turbidityLabel(double t) {
    if (t >= 0.7) return 'Trübung von Vorteil';
    if (t >= 0.4) return 'Tolerant';
    return 'Klares Wasser nötig';
  }
}

// Damit der String-Helper auch ohne Import direkt kompiliert

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.c});
  final String title;
  final ApexColors c;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontFamily: 'Rajdhani',
        fontSize: 12,
        letterSpacing: 1.8,
        fontWeight: FontWeight.w700,
        color: c.textMuted,
      ),
    );
  }
}

class _FactGrid extends StatelessWidget {
  const _FactGrid({required this.rows});
  final List<_FactRow> rows;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              Divider(height: 1, color: c.border.withAlpha(120)),
          ],
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: ApexColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: c.textSecondary),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.c,
    required this.icon,
    required this.title,
    required this.text,
  });
  final ApexColors c;
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: ApexColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1,
                    color: c.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    color: c.textPrimary,
                    height: 1.4,
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

class _LureChip extends StatelessWidget {
  const _LureChip({required this.label, required this.c});
  final String label;
  final ApexColors c;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ApexColors.primary.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ApexColors.primary.withAlpha(80)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: c.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  const _TipRow({required this.text, required this.c});
  final String text;
  final ApexColors c;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, size: 16, color: ApexColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: c.textPrimary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
