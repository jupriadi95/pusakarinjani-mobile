import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../config/theme.dart';

/// Home Screen — Portal Pertandingan Tanding.
/// Port of Nuxt's tanding/index.vue
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Force portrait orientation for initial portal screen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: PusakaTheme.backgroundGradient),
        child: Stack(
          children: [
            // Ambient glowing orbs
            Positioned(
              top: MediaQuery.of(context).size.height * 0.15,
              left: MediaQuery.of(context).size.width * 0.3,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: PusakaTheme.indigo600.withValues(alpha: 0.12),
                ),
              ),
            ),
            Positioned(
              bottom: 40,
              right: 20,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: PusakaTheme.rose600.withValues(alpha: 0.08),
                ),
              ),
            ),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    // Top Navigation Header
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // System online badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color:
                                  PusakaTheme.emerald950.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: PusakaTheme.emerald400
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: PusakaTheme.emerald400,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'Sistem Gelanggang Online',
                                  style: TextStyle(
                                    color: PusakaTheme.emerald400,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(flex: 1),

                    // Hero Section — Emblem + Title
                    _buildHeroSection().animate().fadeIn(duration: 600.ms).slideY(
                        begin: 0.1, duration: 600.ms, curve: Curves.easeOut),

                    const SizedBox(height: 32),

                    // Role Selection Cards
                    ..._buildRoleCards(context),

                    const Spacer(flex: 1),

                    // Footer
                    _buildFooter(),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroSection() {
    return Column(
      children: [
        // Emblem
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [PusakaTheme.indigo500, Color(0xFF9333EA)],
            ),
            boxShadow: [
              BoxShadow(
                color: PusakaTheme.indigo500.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(2),
          child: Container(
            decoration: BoxDecoration(
              color: PusakaTheme.slate950,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.emoji_events,
              color: PusakaTheme.amber400,
              size: 26,
            ),
          ),
        ),

        const SizedBox(height: 16),

        const Text(
          'PORTAL PERTANDINGAN\nTANDING',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            height: 1.1,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 8),

        const Text(
          'Silakan pilih akses peran petugas untuk memulai\nsistem manajemen arena.',
          style: TextStyle(
            color: PusakaTheme.slate400,
            fontSize: 12,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  List<Widget> _buildRoleCards(BuildContext context) {
    final roles = [
      _RoleData(
        title: 'Dewan Pertandingan',
        subtitle: 'Manajemen Arena & Alur Tanding',
        description:
            'Kontrol timer, giliran partai, panggilan atlet sudut merah/biru.',
        icon: Icons.shield,
        badge: 'Arena Controller',
        gradient: PusakaTheme.indigoGradient,
        route: '/verify/operator',
      ),
      _RoleData(
        title: 'Juri Pertandingan',
        subtitle: 'Input Nilai & Pelanggaran',
        description:
            'Konsol penilaian juri real-time untuk poin pukulan & tendangan.',
        icon: Icons.sports_esports,
        badge: 'Scoring Keypad',
        gradient: PusakaTheme.roseGradient,
        route: '/verify/juri',
      ),
      _RoleData(
        title: 'Monitoring Nilai',
        subtitle: 'Layar Display Skor Gelanggang',
        description:
            'Papan skor digital layar lebar untuk penonton dan official.',
        icon: Icons.tv,
        badge: 'Live Scoreboard',
        gradient: PusakaTheme.amberGradient,
        route: '/verify/monitor',
      ),
    ];

    return roles.asMap().entries.map((entry) {
      final i = entry.key;
      final role = entry.value;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _RoleCard(role: role)
            .animate()
            .fadeIn(delay: (200 + i * 100).ms, duration: 500.ms)
            .slideX(begin: 0.05, duration: 500.ms, curve: Curves.easeOut),
      );
    }).toList();
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Divider(color: PusakaTheme.slate800.withValues(alpha: 0.6)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Sistem Manajemen Pencak Silat IPSI © 2026',
              style: TextStyle(
                color: PusakaTheme.slate500,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: PusakaTheme.indigo500,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'Gelanggang Digital',
                  style: TextStyle(
                    color: PusakaTheme.slate400,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _RoleData {
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final String badge;
  final LinearGradient gradient;
  final String route;

  const _RoleData({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.badge,
    required this.gradient,
    required this.route,
  });
}

class _RoleCard extends StatelessWidget {
  final _RoleData role;
  const _RoleCard({required this.role});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Extract role from route (e.g., /verify/operator -> operator)
        Navigator.of(context).pushNamed(role.route);
      },
      child: Container(
        decoration: PusakaTheme.cardDecoration(),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: role.gradient,
                boxShadow: [
                  BoxShadow(
                    color: role.gradient.colors.first.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(role.icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),

            // Text Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          role.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: PusakaTheme.slate800,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: PusakaTheme.slate700),
                        ),
                        child: Text(
                          role.badge,
                          style: const TextStyle(
                            color: PusakaTheme.slate300,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    role.description,
                    style: const TextStyle(
                      color: PusakaTheme.slate400,
                      fontSize: 11,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_ios,
              color: PusakaTheme.slate500,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}
