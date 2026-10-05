import 'dart:math';
import 'package:flutter/material.dart';
import '../config/env.dart';
import '../config/theme.dart';
import '../models/event.dart';
import '../models/gelanggang.dart';
import '../models/sponsor.dart';

/// Standby Screen — displayed when waiting for a match to begin.
/// When sponsors are available, shows a sponsor showcase instead of the old
/// "MOHON MENUNGGU" center card. The IPSI logo and event name are kept in the
/// top header; the bottom footer shows arena status and copyright.
class StandbyScreen extends StatelessWidget {
  final Event? eventInfo;
  final Gelanggang? gelanggangInfo;
  final bool? isLargeDisplay;
  final List<Sponsor> sponsors;

  const StandbyScreen({
    super.key,
    this.eventInfo,
    this.gelanggangInfo,
    this.isLargeDisplay,
    this.sponsors = const [],
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final bool isLarge = isLargeDisplay ?? (screenSize.width >= 1000);

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(gradient: PusakaTheme.backgroundGradient),
      child: Stack(
        children: [
          // ── Ambient Glows ──
          Positioned(
            top: screenSize.height * 0.15,
            left: screenSize.width * 0.1,
            child: Container(
              width: isLarge ? 700 : 400,
              height: isLarge ? 700 : 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: PusakaTheme.indigo600.withValues(alpha: isLarge ? 0.18 : 0.12),
              ),
            ),
          ),
          if (isLarge)
            Positioned(
              bottom: 60,
              right: 80,
              child: Container(
                width: 500,
                height: 500,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: PusakaTheme.amber500.withValues(alpha: 0.08),
                ),
              ),
            ),

          // ── Floating particles ──
          ...List.generate(isLarge ? 14 : 8, (i) => _FloatingParticle(index: i)),

          // ── Main Content ──
          Column(
            children: [
              // TOP HEADER — IPSI logo + event name + gelanggang badge
              SafeArea(
                bottom: false,
                child: _TopHeader(
                  eventInfo: eventInfo,
                  gelanggangInfo: gelanggangInfo,
                  isLarge: isLarge,
                ),
              ),

              const SizedBox(height: 8),

              // BODY — Sponsor showcase OR fallback waiting card
              Expanded(
                child: sponsors.isEmpty
                    ? _WaitingCard(
                        gelanggangInfo: gelanggangInfo,
                        isLarge: isLarge,
                      )
                    : _SponsorShowcase(
                        sponsors: sponsors,
                        isLarge: isLarge,
                      ),
              ),

              // BOTTOM FOOTER
              SafeArea(
                top: false,
                child: _BottomFooter(isLarge: isLarge),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// TOP HEADER
// ─────────────────────────────────────────────
class _TopHeader extends StatelessWidget {
  final Event? eventInfo;
  final Gelanggang? gelanggangInfo;
  final bool isLarge;
  const _TopHeader({this.eventInfo, this.gelanggangInfo, required this.isLarge});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isLarge ? 36 : 20,
        vertical: isLarge ? 18 : 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // IPSI Logo
          Container(
            width: isLarge ? 72 : 48,
            height: isLarge ? 72 : 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(isLarge ? 16 : 12),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [PusakaTheme.indigo600, PusakaTheme.amber500],
              ),
              boxShadow: [
                BoxShadow(
                  color: PusakaTheme.indigo500.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(2.5),
            child: Container(
              decoration: BoxDecoration(
                color: PusakaTheme.slate950,
                borderRadius: BorderRadius.circular(isLarge ? 13 : 10),
              ),
              padding: EdgeInsets.all(isLarge ? 8 : 5),
              child: Image.asset(
                'assets/img/logo_ipsi.webp',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.sports_kabaddi,
                  color: PusakaTheme.amber400,
                  size: isLarge ? 32 : 22,
                ),
              ),
            ),
          ),

          SizedBox(width: isLarge ? 20 : 14),

          // Event name + IPSI label
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'IKATAN PENCAK SILAT INDONESIA',
                  style: TextStyle(
                    color: PusakaTheme.slate400,
                    fontSize: isLarge ? 11 : 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: isLarge ? 2.0 : 1.5,
                  ),
                ),
                SizedBox(height: isLarge ? 3 : 2),
                Text(
                  eventInfo?.namaEvent?.toUpperCase() ??
                      'KEJUARAAN PENCAK SILAT DIGITAL',
                  style: TextStyle(
                    color: PusakaTheme.amber400,
                    fontSize: isLarge ? 20 : 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: isLarge ? 1.5 : 1.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          SizedBox(width: isLarge ? 16 : 12),

          // Gelanggang badge
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isLarge ? 20 : 14,
              vertical: isLarge ? 10 : 7,
            ),
            decoration: BoxDecoration(
              color: PusakaTheme.indigo950.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: PusakaTheme.indigo700.withValues(alpha: 0.8),
              ),
            ),
            child: Text(
              'GELANGGANG ${gelanggangInfo?.kodeGelanggang ?? '-'}',
              style: TextStyle(
                color: PusakaTheme.indigo300,
                fontSize: isLarge ? 15 : 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// BOTTOM FOOTER
// ─────────────────────────────────────────────
class _BottomFooter extends StatelessWidget {
  final bool isLarge;
  const _BottomFooter({required this.isLarge});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isLarge ? 36 : 20,
        vertical: isLarge ? 16 : 12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Sistem Scoreboard Digital IPSI © 2026',
            style: TextStyle(
              color: PusakaTheme.slate400,
              fontSize: isLarge ? 13 : 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          Row(
            children: [
              Container(
                width: isLarge ? 9 : 6,
                height: isLarge ? 9 : 6,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: PusakaTheme.emerald400,
                ),
              ),
              SizedBox(width: isLarge ? 8 : 6),
              Text(
                'STATUS ARENA: READY',
                style: TextStyle(
                  color: PusakaTheme.emerald400,
                  fontSize: isLarge ? 13 : 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// FALLBACK — no sponsors
// ─────────────────────────────────────────────
class _WaitingCard extends StatelessWidget {
  final Gelanggang? gelanggangInfo;
  final bool isLarge;
  const _WaitingCard({this.gelanggangInfo, required this.isLarge});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Container(
          constraints: BoxConstraints(maxWidth: isLarge ? 780 : 500),
          margin: EdgeInsets.symmetric(horizontal: isLarge ? 32 : 24, vertical: 16),
          padding: EdgeInsets.symmetric(
            horizontal: isLarge ? 48 : 32,
            vertical: isLarge ? 36 : 28,
          ),
          decoration: BoxDecoration(
            color: PusakaTheme.slate900.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(isLarge ? 32 : PusakaTheme.radius3xl),
            border: Border.all(
              color: PusakaTheme.slate800.withValues(alpha: 0.9),
              width: isLarge ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: isLarge ? 50 : 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BouncingEmblem(isLarge: isLarge),
              SizedBox(height: isLarge ? 24 : 20),
              Text(
                'MOHON\nMENUNGGU',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isLarge ? 52 : 36,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                  letterSpacing: isLarge ? -0.8 : -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: isLarge ? 14 : 10),
              Text(
                'Pertandingan pada Gelanggang ${gelanggangInfo?.kodeGelanggang ?? '-'} akan segera dimulai',
                style: TextStyle(
                  color: PusakaTheme.slate300,
                  fontSize: isLarge ? 17 : 13,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: isLarge ? 24 : 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: isLarge ? 8 : 6,
                  width: isLarge ? 300 : 200,
                  child: const LinearProgressIndicator(
                    backgroundColor: PusakaTheme.slate800,
                    valueColor: AlwaysStoppedAnimation<Color>(PusakaTheme.indigo500),
                  ),
                ),
              ),
              SizedBox(height: isLarge ? 18 : 14),
              Text(
                'STANDBY ARENA • REALTIME BROADCAST ACTIVE',
                style: TextStyle(
                  color: PusakaTheme.slate400,
                  fontSize: isLarge ? 12 : 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: isLarge ? 2.0 : 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SPONSOR SHOWCASE
// ─────────────────────────────────────────────
/// Displays sponsors grouped by level: Platinum → Gold → Silver → Bronze.
/// Layout uses full-height container that scrolls if needed.
class _SponsorShowcase extends StatelessWidget {
  final List<Sponsor> sponsors;
  final bool isLarge;

  const _SponsorShowcase({required this.sponsors, required this.isLarge});

  static const _levelOrder = ['platinum', 'gold', 'silver', 'bronze'];

  @override
  Widget build(BuildContext context) {
    // Group sponsors by level
    final grouped = <String, List<Sponsor>>{};
    for (final level in _levelOrder) {
      final list = sponsors.where((s) => s.level?.toLowerCase() == level).toList();
      if (list.isNotEmpty) grouped[level] = list;
    }
    // Also capture unknown levels at the end
    final known = _levelOrder.toSet();
    final unknown = sponsors
        .where((s) => !known.contains(s.level?.toLowerCase() ?? ''))
        .toList();
    if (unknown.isNotEmpty) grouped['lainnya'] = unknown;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isLarge ? 48 : 20,
        vertical: isLarge ? 16 : 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Section title
          Text(
            'DIDUKUNG OLEH',
            style: TextStyle(
              color: PusakaTheme.slate400,
              fontSize: isLarge ? 13 : 10,
              fontWeight: FontWeight.w800,
              letterSpacing: isLarge ? 4 : 3,
            ),
          ),
          SizedBox(height: isLarge ? 24 : 16),

          // Render each level group
          ...grouped.entries.map(
            (entry) => _SponsorLevelSection(
              level: entry.key,
              sponsors: entry.value,
              isLarge: isLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _SponsorLevelSection extends StatelessWidget {
  final String level;
  final List<Sponsor> sponsors;
  final bool isLarge;

  const _SponsorLevelSection({
    required this.level,
    required this.sponsors,
    required this.isLarge,
  });

  // Returns config for each level: (color gradient, badge text, logo size)
  _LevelConfig get _config {
    switch (level.toLowerCase()) {
      case 'platinum':
        return _LevelConfig(
          label: '✦  PLATINUM',
          gradient: const [Color(0xFFE0E0E0), Color(0xFFBDBDBD)],
          badgeColor: const Color(0xFFE0E0E0),
          glowColor: const Color(0xFFE0E0E0),
          logoSize: 120.0,
          largeLogo: 160.0,
          crossAxisCount: 3,
        );
      case 'gold':
        return _LevelConfig(
          label: '✦  GOLD',
          gradient: const [Color(0xFFFFD700), Color(0xFFFFAA00)],
          badgeColor: const Color(0xFFFFD700),
          glowColor: const Color(0xFFFFD700),
          logoSize: 90.0,
          largeLogo: 120.0,
          crossAxisCount: 4,
        );
      case 'silver':
        return _LevelConfig(
          label: '✦  SILVER',
          gradient: const [Color(0xFFC0C0C0), Color(0xFF909090)],
          badgeColor: const Color(0xFFC0C0C0),
          glowColor: const Color(0xFFC0C0C0),
          logoSize: 70.0,
          largeLogo: 90.0,
          crossAxisCount: 5,
        );
      case 'bronze':
        return _LevelConfig(
          label: '✦  BRONZE',
          gradient: const [Color(0xFFCD7F32), Color(0xFF8B4513)],
          badgeColor: const Color(0xFFCD7F32),
          glowColor: const Color(0xFFCD7F32),
          logoSize: 55.0,
          largeLogo: 70.0,
          crossAxisCount: 6,
        );
      default:
        return _LevelConfig(
          label: level.toUpperCase(),
          gradient: const [Color(0xFF94A3B8), Color(0xFF64748B)],
          badgeColor: const Color(0xFF94A3B8),
          glowColor: const Color(0xFF94A3B8),
          logoSize: 55.0,
          largeLogo: 70.0,
          crossAxisCount: 6,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _config;
    final logoSize = isLarge ? cfg.largeLogo : cfg.logoSize;

    return Padding(
      padding: EdgeInsets.only(bottom: isLarge ? 28 : 16),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: isLarge ? 24 : 14,
        runSpacing: isLarge ? 20 : 12,
        children: sponsors
            .map((s) => _SponsorLogoCard(
                  sponsor: s,
                  logoSize: logoSize,
                  glowColor: cfg.glowColor,
                  isLarge: isLarge,
                ))
            .toList(),
      ),
    );
  }
}

class _LevelConfig {
  final String label;
  final List<Color> gradient;
  final Color badgeColor;
  final Color glowColor;
  final double logoSize;
  final double largeLogo;
  final int crossAxisCount;

  const _LevelConfig({
    required this.label,
    required this.gradient,
    required this.badgeColor,
    required this.glowColor,
    required this.logoSize,
    required this.largeLogo,
    required this.crossAxisCount,
  });
}

/// Single sponsor logo card with glow effect
class _SponsorLogoCard extends StatefulWidget {
  final Sponsor sponsor;
  final double logoSize;
  final Color glowColor;
  final bool isLarge;

  const _SponsorLogoCard({
    required this.sponsor,
    required this.logoSize,
    required this.glowColor,
    required this.isLarge,
  });

  @override
  State<_SponsorLogoCard> createState() => _SponsorLogoCardState();
}

class _SponsorLogoCardState extends State<_SponsorLogoCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    // Slow pulse glow effect
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.2, end: 0.55).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  String? get _logoUrl {
    final raw = widget.sponsor.logo?.url;
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    return '${Env.apiBaseUrl}$raw';
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.logoSize;
    final logoUrl = _logoUrl;

    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (context, child) => Container(
        width: size + (widget.isLarge ? 32 : 20),
        constraints: BoxConstraints(
          minWidth: size + (widget.isLarge ? 32 : 20),
          maxWidth: size + (widget.isLarge ? 32 : 20),
        ),
        decoration: BoxDecoration(
          color: PusakaTheme.slate900.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(widget.isLarge ? 20 : 14),
          border: Border.all(
            color: widget.glowColor.withValues(alpha: 0.25),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.glowColor.withValues(alpha: _glowAnim.value),
              blurRadius: widget.isLarge ? 28 : 20,
              spreadRadius: widget.isLarge ? 2 : 1,
            ),
          ],
        ),
        padding: EdgeInsets.all(widget.isLarge ? 16 : 10),
        child: SizedBox(
          width: size,
          height: size,
          child: logoUrl != null
              ? Image.network(
                  logoUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => _FallbackLogo(
                    label: widget.sponsor.label,
                    size: size,
                    color: widget.glowColor,
                  ),
                )
              : _FallbackLogo(
                  label: widget.sponsor.label,
                  size: size,
                  color: widget.glowColor,
                ),
        ),
      ),
    );
  }
}

/// Fallback when logo image is not available
class _FallbackLogo extends StatelessWidget {
  final String? label;
  final double size;
  final Color color;
  const _FallbackLogo({this.label, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Center(
        child: Text(
          label?.isNotEmpty == true ? label![0].toUpperCase() : '?',
          style: TextStyle(
            color: color,
            fontSize: size * 0.45,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// BOUNCING EMBLEM (kept for fallback card)
// ─────────────────────────────────────────────
class _BouncingEmblem extends StatefulWidget {
  final bool isLarge;
  const _BouncingEmblem({this.isLarge = false});

  @override
  State<_BouncingEmblem> createState() => _BouncingEmblemState();
}

class _BouncingEmblemState extends State<_BouncingEmblem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double size = widget.isLarge ? 115.0 : 72.0;
    final double radius = widget.isLarge ? 32.0 : 22.0;
    final double innerRadius = widget.isLarge ? 30.0 : 20.0;
    final double padding = widget.isLarge ? 14.0 : 8.0;
    final double bounce = widget.isLarge ? -8.0 : -6.0;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, bounce * _controller.value),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [PusakaTheme.indigo600, PusakaTheme.amber500],
              ),
              boxShadow: [
                BoxShadow(
                  color: PusakaTheme.indigo500.withValues(alpha: 0.35),
                  blurRadius: widget.isLarge ? 24 : 18,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            padding: const EdgeInsets.all(2.5),
            child: Container(
              decoration: BoxDecoration(
                color: PusakaTheme.slate950,
                borderRadius: BorderRadius.circular(innerRadius),
              ),
              padding: EdgeInsets.all(padding),
              child: Image.asset(
                'assets/img/logo_ipsi.webp',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.sports_kabaddi,
                  color: PusakaTheme.amber400,
                  size: widget.isLarge ? 48 : 32,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// FLOATING PARTICLE (unchanged)
// ─────────────────────────────────────────────
class _FloatingParticle extends StatefulWidget {
  final int index;
  const _FloatingParticle({required this.index});

  @override
  State<_FloatingParticle> createState() => _FloatingParticleState();
}

class _FloatingParticleState extends State<_FloatingParticle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late double _leftPercent;
  late double _size;
  late Duration _duration;

  @override
  void initState() {
    super.initState();
    final rng = Random(widget.index);
    _leftPercent = rng.nextDouble();
    _size = 15.0 + rng.nextDouble() * 80;
    _duration = Duration(seconds: 12 + rng.nextInt(20));

    _controller = AnimationController(
      vsync: this,
      duration: _duration,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final screenHeight = MediaQuery.of(context).size.height;
        final screenWidth = MediaQuery.of(context).size.width;
        final progress = _controller.value;
        final top = screenHeight * (1.0 - progress);
        final left = screenWidth * _leftPercent + sin(progress * 2 * pi) * 20;
        final opacity = sin(progress * pi) * 0.25;

        return Positioned(
          top: top,
          left: left,
          child: Container(
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: PusakaTheme.indigo500.withValues(alpha: opacity),
            ),
          ),
        );
      },
    );
  }
}
