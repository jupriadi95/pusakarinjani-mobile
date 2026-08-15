import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../models/gelanggang.dart';
import '../../models/nilai.dart';
import '../../models/peserta.dart';
import '../../providers/gelanggang_provider.dart';
import '../../providers/nilai_provider.dart';
import '../../services/api_service.dart';
import '../../services/socket_service.dart';
import '../../widgets/standby_screen.dart';
import '../../widgets/timer_widget.dart';

/// Monitor Screen — Live scoreboard display.
/// Port of Nuxt's tanding/monitor/index.vue
class MonitorScreen extends ConsumerStatefulWidget {
  const MonitorScreen({super.key});

  @override
  ConsumerState<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends ConsumerState<MonitorScreen> {
  final _socketService = SocketService();
  final _api = ApiService();

  bool _isConnected = false;
  Gelanggang? _gelanggang;
  Peserta? _atlit1;
  Peserta? _atlit2;

  StreamSubscription? _connectionSub;
  StreamSubscription? _gelanggangSub;
  StreamSubscription? _nilaiSub;

  @override
  void initState() {
    super.initState();
    // Force landscape for monitor scoreboard
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Full-screen immersive mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initData();
  }

  void _initData() {
    _gelanggang = ref.read(activeGelanggangProvider);

    if (_gelanggang != null) {
      if (_gelanggang!.isBerlangsung) {
        _fetchPeserta(_gelanggang!.atlit1Id ?? '', 1);
        _fetchPeserta(_gelanggang!.atlit2Id ?? '', 2);
        _fetchNilai();
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

    _nilaiSub = _socketService.onNilaiCreated.listen((newNilai) {
      ref.read(nilaiListProvider.notifier).addFromSocket(newNilai);
    });
  }

  Future<void> _fetchPeserta(String docId, int dst) async {
    if (docId.isEmpty) return;
    try {
      final response = await _api.findOneProtect('pesertas', docId, params: {
        'populate[0]': 'action_foto',
        'populate[1]': 'pas_foto',
        'populate[2]': 'kelas',
      });
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
      debugPrint('Monitor fetchPeserta error: $e');
    }
  }

  Future<void> _fetchNilai() async {
    if (_gelanggang == null) return;
    final a1 = _gelanggang!.atlit1Id ?? '';
    final a2 = _gelanggang!.atlit2Id ?? '';
    if (a1.isNotEmpty && a2.isNotEmpty) {
      await ref.read(nilaiListProvider.notifier).fetchNilai(a1, a2);
    }
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _gelanggangSub?.cancel();
    _nilaiSub?.cancel();
    _socketService.disconnect();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // STATE 2: STANDBY
    if (_gelanggang?.statusTanding != 'berlangsung') {
      return Scaffold(
        body: StandbyScreen(
          eventInfo: _gelanggang?.event,
          gelanggangInfo: _gelanggang,
        ),
      );
    }

    // STATE 1: ACTIVE SCOREBOARD
    return _buildActiveScoreboard();
  }

  Widget _buildActiveScoreboard() {
    final nilaiList = ref.watch(nilaiListProvider);
    final atlit1Score =
        countNilaiForPeserta(nilaiList, _gelanggang?.atlit1Id ?? '');
    final atlit2Score =
        countNilaiForPeserta(nilaiList, _gelanggang?.atlit2Id ?? '');
    final atlit1Logs =
        recentNilaiForPeserta(nilaiList, _gelanggang?.atlit1Id ?? '');
    final atlit2Logs =
        recentNilaiForPeserta(nilaiList, _gelanggang?.atlit2Id ?? '');

    return Scaffold(
      body: Container(
        decoration:
            const BoxDecoration(gradient: PusakaTheme.backgroundGradient),
        child: Stack(
          children: [
            // Background ambient glows
            Positioned(
              top: MediaQuery.of(context).size.height * 0.3,
              left: MediaQuery.of(context).size.width * 0.15,
              child: Container(
                width: 350,
                height: 350,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: PusakaTheme.blue600.withValues(alpha: 0.15),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).size.height * 0.3,
              right: MediaQuery.of(context).size.width * 0.15,
              child: Container(
                width: 350,
                height: 350,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: PusakaTheme.rose600.withValues(alpha: 0.15),
                ),
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  // Top Header
                  _buildHeader(),

                  // Main Scoreboard Grid
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: Row(
                        children: [
                          // SUDUT BIRU (LEFT)
                          Expanded(
                            child: _buildAtletPanel(
                              atlit: _atlit1,
                              isRed: false,
                              score: atlit1Score,
                              logs: atlit1Logs,
                            ),
                          ),
                          const SizedBox(width: 10),
                          // SUDUT MERAH (RIGHT)
                          Expanded(
                            child: _buildAtletPanel(
                              atlit: _atlit2,
                              isRed: true,
                              score: atlit2Score,
                              logs: atlit2Logs,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Footer
                  _buildFooter(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom:
              BorderSide(color: PusakaTheme.slate800.withValues(alpha: 0.8)),
        ),
      ),
      child: Row(
        children: [
          // Arena Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: PusakaTheme.indigo950,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: PusakaTheme.indigo700),
              boxShadow: [
                BoxShadow(
                  color: PusakaTheme.indigo600.withValues(alpha: 0.2),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Text(
              'GELANGGANG ${_gelanggang?.kodeGelanggang ?? '-'}',
              style: const TextStyle(
                color: PusakaTheme.indigo300,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Event Name
          Expanded(
            child: Text(
              _gelanggang?.event?.namaEvent ?? 'KEJUARAAN PENCAK SILAT',
              style: const TextStyle(
                color: PusakaTheme.amber400,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Timer
          const TimerWidget(
            initialSeconds: 120,
            countdownMode: true,
            autoStart: true,
            hideControls: true,
          ),

          const SizedBox(width: 12),

          // Live Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: PusakaTheme.emerald950.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: PusakaTheme.emerald400.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: PusakaTheme.emerald400.withValues(alpha: 0.15),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: PusakaTheme.emerald400,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'LIVE SCOREBOARD',
                  style: TextStyle(
                    color: PusakaTheme.emerald400,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAtletPanel({
    required Peserta? atlit,
    required bool isRed,
    required int score,
    required List<Nilai> logs,
  }) {
    final borderColor = isRed ? PusakaTheme.rose600 : PusakaTheme.blue600;
    final accentLight = isRed ? PusakaTheme.rose400 : PusakaTheme.blue400;
    final accentDark = isRed ? PusakaTheme.rose600 : PusakaTheme.blue600;
    final scoreGradient = isRed
        ? const [PusakaTheme.rose600, PusakaTheme.rose800]
        : const [PusakaTheme.blue600, PusakaTheme.blue800];

    return Container(
      decoration: BoxDecoration(
        color: PusakaTheme.slate900.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(PusakaTheme.radius2xl),
        border: Border.all(color: borderColor.withValues(alpha: 0.8), width: 2),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.2),
            blurRadius: 40,
            spreadRadius: -5,
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          // Corner Badge Header
          Row(
            mainAxisAlignment:
                isRed ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!isRed) ...[
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentDark,
                    boxShadow: [
                      BoxShadow(
                          color: accentDark.withValues(alpha: 0.5),
                          blurRadius: 4),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                isRed ? 'Sudut Merah' : 'Sudut Biru',
                style: TextStyle(
                  color: accentLight,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              if (isRed) ...[
                const SizedBox(width: 6),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentDark,
                    boxShadow: [
                      BoxShadow(
                          color: accentDark.withValues(alpha: 0.5),
                          blurRadius: 4),
                    ],
                  ),
                ),
              ],
            ],
          ),

          Divider(color: borderColor.withValues(alpha: 0.4), height: 16),

          // Athlete Info + Score
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Athlete Photo / Placeholder
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(PusakaTheme.radiusLg),
                    border: Border.all(
                        color: borderColor.withValues(alpha: 0.6), width: 2),
                    color: PusakaTheme.slate950,
                  ),
                  child: atlit?.actionFoto?.url != null ||
                          atlit?.pasFoto?.url != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(
                              PusakaTheme.radiusLg - 2),
                          child: Image.network(
                            '${_api.toString().isEmpty ? '' : ''}${atlit?.actionFoto?.url ?? atlit?.pasFoto?.url ?? ''}',
                            fit: BoxFit.cover,
                            errorBuilder: (_, e2, s2) =>
                                _buildPhotoPlaceholder(isRed),
                          ),
                        )
                      : _buildPhotoPlaceholder(isRed),
                ),

                const SizedBox(height: 10),

                // Name
                Text(
                  atlit?.namaLengkap ?? (isRed ? 'ATLIT MERAH' : 'ATLIT BIRU'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),

                Text(
                  atlit?.kontingen ?? 'Kontingen -',
                  style: TextStyle(
                    color: accentLight,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 12),

                // Giant Score Box
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: scoreGradient,
                    ),
                    borderRadius:
                        BorderRadius.circular(PusakaTheme.radiusLg),
                    border: Border.all(color: accentLight, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: accentDark.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        'TOTAL POIN',
                        style: TextStyle(
                          color: accentLight,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                      Text(
                        '$score',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 56,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Score Log Feed
          Container(
            padding: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                    color: borderColor.withValues(alpha: 0.3)),
              ),
            ),
            child: Row(
              children: [
                Text(
                  isRed ? 'LOG POIN MERAH:' : 'LOG POIN BIRU:',
                  style: TextStyle(
                    color: accentLight,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: logs.isEmpty
                      ? const Text(
                          'Belum ada poin',
                          style: TextStyle(
                            color: PusakaTheme.slate500,
                            fontSize: 9,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: logs.map((log) {
                              return Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (isRed
                                          ? PusakaTheme.rose950
                                          : PusakaTheme.blue950)
                                      .withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: (isRed
                                          ? PusakaTheme.rose800
                                          : PusakaTheme.blue800)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '+${log.jumlah}',
                                      style: TextStyle(
                                        color: (isRed
                                            ? PusakaTheme.rose400
                                            : PusakaTheme.blue400),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      '(${log.poinLabel})',
                                      style: TextStyle(
                                        color: (isRed
                                                ? PusakaTheme.rose400
                                                : PusakaTheme.blue400)
                                            .withValues(alpha: 0.7),
                                        fontSize: 9,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
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

  Widget _buildPhotoPlaceholder(bool isRed) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.shield,
          size: 36,
          color: (isRed ? PusakaTheme.rose400 : PusakaTheme.blue400)
              .withValues(alpha: 0.4),
        ),
        const SizedBox(height: 4),
        Text(
          isRed ? 'FOTO MERAH' : 'FOTO BIRU',
          style: const TextStyle(
            color: PusakaTheme.slate400,
            fontSize: 8,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: PusakaTheme.slate800.withValues(alpha: 0.8)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Sistem Scoreboard Digital IPSI © 2026',
            style: TextStyle(
              color: PusakaTheme.slate500,
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
          Row(
            children: [
              Icon(Icons.cell_tower,
                  color: _isConnected ? PusakaTheme.emerald400 : PusakaTheme.rose400, size: 12),
              const SizedBox(width: 4),
              Text(
                _isConnected ? 'Penilaian Poin Realtime Terhubung' : 'Koneksi Terputus',
                style: TextStyle(
                  color: _isConnected ? PusakaTheme.slate400 : PusakaTheme.rose400,
                  fontSize: 9,
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
