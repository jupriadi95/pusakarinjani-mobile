import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../models/gelanggang.dart';
import '../../models/peserta.dart';
import '../../providers/gelanggang_provider.dart';
import '../../providers/nilai_provider.dart';
import '../../services/api_service.dart';
import '../../services/socket_service.dart';
import '../../widgets/connection_badge.dart';
import '../../widgets/score_button.dart';
import '../../widgets/standby_screen.dart';

/// Juri Screen — Scoring console for judges.
/// Port of Nuxt's tanding/juri/index.vue
class JuriScreen extends ConsumerStatefulWidget {
  const JuriScreen({super.key});

  @override
  ConsumerState<JuriScreen> createState() => _JuriScreenState();
}

class _JuriScreenState extends ConsumerState<JuriScreen> {
  final _socketService = SocketService();
  final _api = ApiService();

  bool _isConnected = false;
  Gelanggang? _gelanggang;
  Peserta? _atlit1;
  Peserta? _atlit2;

  bool _showSuccessToast = false;
  StreamSubscription? _connectionSub;
  StreamSubscription? _gelanggangSub;

  @override
  void initState() {
    super.initState();
    // Force landscape for juri console (optimized for touch scoring)
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _initSocket();
  }

  void _initSocket() {
    _gelanggang = ref.read(activeGelanggangProvider);

    if (_gelanggang != null) {
      if (_gelanggang!.isBerlangsung) {
        _fetchPeserta(_gelanggang!.atlit1Id ?? '', 1);
        _fetchPeserta(_gelanggang!.atlit2Id ?? '', 2);
      }

      _socketService.connect(
        gelanggangDocumentId: _gelanggang!.documentId,
      );
    }

    _connectionSub = _socketService.onConnectionChanged.listen((connected) {
      if (mounted) setState(() => _isConnected = connected);
    });

    _gelanggangSub = _socketService.onGelanggangUpdated.listen((updated) {
      if (mounted) {
        setState(() => _gelanggang = updated);
        ref.read(activeGelanggangProvider.notifier).updateFromSocket(updated);
        _fetchPeserta(updated.atlit1Id ?? '', 1);
        _fetchPeserta(updated.atlit2Id ?? '', 2);
      }
    });
  }

  Future<void> _fetchPeserta(String docId, int dst) async {
    if (docId.isEmpty) return;
    try {
      final response = await _api.findOneProtect('pesertas', docId);
      final data = response['data'];
      if (data is Map<String, dynamic> && mounted) {
        setState(() {
          if (dst == 1) {
            _atlit1 = Peserta.fromJson(data);
          } else {
            _atlit2 = Peserta.fromJson(data);
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching peserta juri: $e');
    }
  }

  Future<void> _addNilai(int jumlah, Peserta? atlit) async {
    if (atlit?.documentId == null) return;
    final nilaiNotifier = ref.read(nilaiListProvider.notifier);
    final ok = await nilaiNotifier.createNilai(
      jumlah: jumlah,
      pesertaDocId: atlit!.documentId!,
    );

    if (ok && mounted) {
      setState(() => _showSuccessToast = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showSuccessToast = false);
      });
    }
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _gelanggangSub?.cancel();
    _socketService.disconnect();
    // Restore orientation
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // STATE 1: STANDBY (waiting for match)
    if (_gelanggang?.statusTanding != 'berlangsung') {
      return _buildStandbyState();
    }

    // STATE 2: ACTIVE SCORING CONSOLE
    return _buildScoringConsole();
  }

  Widget _buildStandbyState() {
    return Scaffold(
      body: Stack(
        children: [
          StandbyScreen(
            eventInfo: _gelanggang?.event,
            gelanggangInfo: _gelanggang,
          ),

          // Header with back button and connection badge
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () {
                      SystemChrome.setPreferredOrientations(
                          DeviceOrientation.values);
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: PusakaTheme.slate900.withValues(alpha: 0.8),
                        borderRadius:
                            BorderRadius.circular(PusakaTheme.radiusMd),
                        border: Border.all(color: PusakaTheme.slate800),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.arrow_back,
                              color: PusakaTheme.slate300, size: 14),
                          SizedBox(width: 6),
                          Text(
                            'Portal Tanding',
                            style: TextStyle(
                              color: PusakaTheme.slate300,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ConnectionBadge(isConnected: _isConnected),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoringConsole() {
    return Scaffold(
      body: Container(
        decoration:
            const BoxDecoration(gradient: PusakaTheme.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              // Compact Top Header
              _buildHeader(),

              // Main 2-column scoring grid
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      // Sudut Biru (Left)
                      Expanded(child: _buildCornerPanel(_atlit1, false)),
                      const SizedBox(width: 8),
                      // Sudut Merah (Right)
                      Expanded(child: _buildCornerPanel(_atlit2, true)),
                    ],
                  ),
                ),
              ),

              // Footer
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom:
              BorderSide(color: PusakaTheme.slate800.withValues(alpha: 0.8)),
        ),
      ),
      child: Row(
        children: [
          // Back
          GestureDetector(
            onTap: () {
              SystemChrome.setPreferredOrientations(DeviceOrientation.values);
              Navigator.of(context).pop();
            },
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: PusakaTheme.slate900,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: PusakaTheme.slate800),
              ),
              child: const Icon(Icons.arrow_back,
                  color: PusakaTheme.slate400, size: 14),
            ),
          ),
          const SizedBox(width: 8),

          // Labels
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: PusakaTheme.indigo950,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: PusakaTheme.indigo700),
            ),
            child: Text(
              'GEL ${_gelanggang?.kodeGelanggang ?? '-'}',
              style: const TextStyle(
                color: PusakaTheme.indigo300,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'KONSOL JURI',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),

          const Spacer(),

          // Toast
          AnimatedOpacity(
            opacity: _showSuccessToast ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: PusakaTheme.emerald600,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: PusakaTheme.emerald600.withValues(alpha: 0.3),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.done_all, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text(
                    'Poin Terkirim',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),
          ConnectionBadge(isConnected: _isConnected, compact: true),
        ],
      ),
    );
  }

  Widget _buildCornerPanel(Peserta? atlit, bool isRed) {
    final borderColor = isRed
        ? PusakaTheme.rose800.withValues(alpha: 0.6)
        : PusakaTheme.blue800.withValues(alpha: 0.6);
    final accentLight = isRed ? PusakaTheme.rose400 : PusakaTheme.blue400;
    final accentDark = isRed ? PusakaTheme.rose600 : PusakaTheme.blue600;

    final buttons = ScoreButtons.getButtons(reversed: isRed);

    return Container(
      decoration: BoxDecoration(
        color: PusakaTheme.slate900.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(PusakaTheme.radiusLg),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
          ),
        ],
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          // Corner Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentDark,
                      boxShadow: [
                        BoxShadow(
                          color: accentDark.withValues(alpha: 0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isRed ? 'Sudut Merah' : 'Sudut Biru',
                    style: TextStyle(
                      color: accentLight,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (isRed ? PusakaTheme.rose950 : PusakaTheme.blue950),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color:
                        (isRed ? PusakaTheme.rose800 : PusakaTheme.blue800),
                  ),
                ),
                child: Text(
                  isRed ? 'ATLIT 2' : 'ATLIT 1',
                  style: TextStyle(
                    color: accentLight,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),

          Divider(color: borderColor, height: 12),

          // Athlete Info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isRed ? PusakaTheme.rose950 : PusakaTheme.blue950)
                  .withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(PusakaTheme.radiusMd),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                // Initials avatar
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accentDark,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: accentLight),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    atlit?.initials ?? '??',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        atlit?.namaLengkap ?? 'Belum Ada Atlet',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${atlit?.kontingen ?? 'Kontingen -'}${atlit?.perguruan != null ? ' • ${atlit!.perguruan}' : ''}',
                        style: const TextStyle(
                          color: PusakaTheme.slate400,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Scoring Buttons Grid (3 columns)
          Expanded(
            child: Row(
              children: buttons.map((btn) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ScoreButton(
                      label: btn.label,
                      value: btn.value,
                      icon: btn.icon,
                      gradientColors: btn.colors,
                      enabled: atlit?.documentId != null,
                      onTap: () => _addNilai(btn.value, atlit),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: PusakaTheme.slate800.withValues(alpha: 0.8)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: const [
          Text(
            'Konsol Juri IPSI © 2026',
            style: TextStyle(
              color: PusakaTheme.slate500,
              fontSize: 8,
              fontWeight: FontWeight.w500,
            ),
          ),
          Row(
            children: [
              Icon(Icons.sports_esports,
                  color: PusakaTheme.indigo400, size: 10),
              SizedBox(width: 4),
              Text(
                'Sentuhan Poin Realtime',
                style: TextStyle(
                  color: PusakaTheme.slate400,
                  fontSize: 8,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
