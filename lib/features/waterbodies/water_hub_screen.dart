import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/widgets/apex_app_bar.dart';
import '../spots/spot_list_screen.dart';
import 'waterbodies_screen.dart';

/// Sammelhub für Gewässer **und** Spots — erreichbar über die Hauptnav.
///
/// Tab 1: Gewässer (Seen, Flüsse, …)
/// Tab 2: Spots (eigene Markierungen, optional einem Gewässer zugeordnet)
///
/// Der "+"-Button in der AppBar erstellt — je nach aktivem Tab — ein neues
/// Gewässer bzw. einen neuen Spot. Auf dem Spots-Tab gibt es zusätzlich
/// einen Karten-Button.
class WaterHubScreen extends ConsumerStatefulWidget {
  const WaterHubScreen({super.key});

  @override
  ConsumerState<WaterHubScreen> createState() => _WaterHubScreenState();
}

class _WaterHubScreenState extends ConsumerState<WaterHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: ApexAppBar(
        extraActions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Karte',
            onPressed: () {
              final spots = ref.read(spotProvider).valueOrNull ?? const [];
              final waterbodies =
                  ref.read(waterbodyProvider).valueOrNull ?? const [];
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      SpotsMapScreen(spots: spots, waterbodies: waterbodies),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: c.surface,
            child: TabBar(
              controller: _tab,
              labelColor: ApexColors.primary,
              unselectedLabelColor: c.textMuted,
              indicatorColor: ApexColors.primary,
              indicatorWeight: 2.5,
              labelStyle: const TextStyle(
                fontFamily: 'Rajdhani',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                letterSpacing: 1.2,
              ),
              unselectedLabelStyle: const TextStyle(
                fontFamily: 'Rajdhani',
                fontWeight: FontWeight.w600,
                fontSize: 14,
                letterSpacing: 1.2,
              ),
              tabs: const [
                Tab(
                  icon: Icon(Icons.water_rounded, size: 18),
                  iconMargin: EdgeInsets.only(bottom: 2),
                  text: 'GEWÄSSER',
                ),
                Tab(
                  icon: Icon(Icons.place_rounded, size: 18),
                  iconMargin: EdgeInsets.only(bottom: 2),
                  text: 'SPOTS',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: const [
                WaterbodiesScreen(embedded: true),
                SpotListScreen(embedded: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
