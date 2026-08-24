import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/theme.dart';
import '../../models/gelanggang.dart';
import '../../models/peserta.dart';
import '../../providers/gelanggang_provider.dart';
import '../../providers/jadwal_provider.dart';
import '../../providers/socket_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/connection_badge.dart';
import '../../widgets/standby_screen.dart';

enum VoteStatusType { none, buffered, confirmed, rejected }

/// Juri Screen — Scoring console for judges.
/// Features vibrant dynamic background gradients for Sudut Biru & Sudut Merah,
/// extra-large rounded rectangular Pukulan (+1) & Tendangan (+2) scoring buttons,
/// a central vertical Babak/Round indicator panel, and interactive Dewan Verification popup.
class JuriScreen extends ConsumerStatefulWidget {
  const JuriScreen({super.key});

  @override
  ConsumerState<JuriScreen> createState() => _JuriScreenState();
}

class _JuriScreenState extends ConsumerState<JuriScreen> {
  late final SocketService _socketService;
  final _api = ApiService();

  bool _isConnected = false;
  Gelanggang? _gelanggang;
  Peserta? _atlit1;
  Peserta? _atlit2;

  // ── Selected Juri ID ('juri_1' | 'juri_2' | 'juri_3') ──
  String _selectedJuriId = 'juri_1';

  // ── Feedback Toast / Banner state ──
  VoteStatusType _voteStatus = VoteStatusType.none;
  String _voteMessage = '';
  Timer? _voteBannerTimer;

  // ── Verification Dialog State ──
  bool _isVerifikasiOpen = false;
  String? _myVerifikasiVote;
  String? _verifikasiFinalVerdict;
  StateSetter? _verifikasiDialogSetState;
  String? _liveBabakOverride;

  StreamSubscription? _connectionSub;
  StreamSubscription? _gelanggangSub;
  StreamSubscription? _voteBufferedSub;
  StreamSubscription? _voteConfirmSub;
  StreamSubscription? _voteRejectedSub;
  StreamSubscription? _verifikasiMulaiSub;
  StreamSubscription? _verifikasiSelesaiSub;
  StreamSubscription? _babakChangedSub;
  StreamSubscription? _timerControlSub;
  StreamSubscription? _pertandinganSelesaiSub;

  @override
  void initState() {
    super.initState();
    // Resolve shared singleton socket service
    _socketService = ref.read(socketServiceProvider);
    // Force landscape for juri console (optimized for touch scoring)
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _loadSavedJuriId();
    _initSocket();
  }

  Future<void> _loadSavedJuriId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('saved_juri_id');
    if (saved != null && ['juri_1', 'juri_2', 'juri_3'].contains(saved)) {
      if (mounted) setState(() => _selectedJuriId = saved);
    } else {
      // Prompt user to pick their Juri ID on first launch
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showJuriSelectorDialog();
      });
    }
  }

  Future<void> _setJuriId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_juri_id', id);
    if (mounted) setState(() => _selectedJuriId = id);
  }

  void _initSocket() {
    _gelanggang = ref.read(activeGelanggangProvider);

    if (_gelanggang != null) {
      ref.read(jadwalListProvider.notifier).fetchJadwal(_gelanggang!);

      if (_gelanggang!.isBerlangsung) {
        _fetchPeserta(_gelanggang!.atlit1Id ?? '', 1);
        _fetchPeserta(_gelanggang!.atlit2Id ?? '', 2);
      }

      _socketService.connect(gelanggangDocumentId: _gelanggang!.documentId);
    }

    _connectionSub = _socketService.onConnectionChanged.listen((connected) {
      if (mounted) setState(() => _isConnected = connected);
    });

    _gelanggangSub = _socketService.onGelanggangUpdated.listen((updated) {
      if (mounted) {
        setState(() => _gelanggang = updated);
        ref.read(activeGelanggangProvider.notifier).updateFromSocket(updated);
        ref.read(jadwalListProvider.notifier).fetchJadwal(updated);
        _fetchPeserta(updated.atlit1Id ?? '', 1);
        _fetchPeserta(updated.atlit2Id ?? '', 2);
      }
    });

    // ── Consensus Voting Feedback Listeners ──
    _voteBufferedSub = _socketService.onJuriVoteBuffered.listen((data) {
      _showVoteBanner(
        VoteStatusType.buffered,
        'Menunggu juri lain (< 1s)...',
        durationMs: 1500,
      );
    });

    _voteConfirmSub = _socketService.onJuriVoteConfirm.listen((data) {
      final juriCount = data['juri_count'] ?? data['count'] ?? '2+';
      _showVoteBanner(
        VoteStatusType.confirmed,
        'Poin SAH ($juriCount Juri Sepakat)',
        durationMs: 2000,
      );
    });

    _voteRejectedSub = _socketService.onJuriVoteRejected.listen((data) {
      _showVoteBanner(
        VoteStatusType.rejected,
        'Poin Ditolak (Tidak ada juri lain yang sepakat)',
        durationMs: 2000,
      );
    });

    // ── Dewan Verification Socket Listeners ──
    _verifikasiMulaiSub = _socketService.onVerifikasiMulai.listen((data) {
      if (!mounted) return;
      _showVerifikasiJuriDialog(data);
    });

    _verifikasiSelesaiSub = _socketService.onVerifikasiSelesai.listen((data) {
      if (!mounted || !_isVerifikasiOpen) return;
      final hasil = data['hasil']?.toString() ?? '';
      setState(() {
        _verifikasiFinalVerdict = hasil;
      });
      _verifikasiDialogSetState?.call(() {});

      // Auto close after 2.5s
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted && _isVerifikasiOpen) {
          setState(() => _isVerifikasiOpen = false);
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        }
      });
    });

    // ── Babak / Round Change Sync Listener ──
    _babakChangedSub = _socketService.onBabakChanged.listen((data) {
      if (!mounted) return;
      final babak = data['babak']?.toString();
      if (babak != null && babak.isNotEmpty) {
        setState(() {
          _liveBabakOverride = babak;
        });
      }
    });

    // ── Timer Control Sync Listener (Start -> Scoring Console, Stop -> Standby) ──
    _timerControlSub = _socketService.onTimerControl.listen((data) {
      if (!mounted) return;
      final action = data['action']?.toString();
      if (action == 'stop') {
        setState(() {
          if (_gelanggang != null) {
            _gelanggang = _gelanggang!.copyWith(statusTanding: 'standby');
          }
        });
      } else if (action == 'start') {
        setState(() {
          if (_gelanggang != null) {
            _gelanggang = _gelanggang!.copyWith(statusTanding: 'berlangsung');
          }
        });
      }
    });

    // ── Match Completion / Finished Listener ──
    _pertandinganSelesaiSub = _socketService.onPertandinganSelesai.listen((
      data,
    ) {
      if (!mounted) return;
      setState(() {
        if (_gelanggang != null) {
          _gelanggang = _gelanggang!.copyWith(statusTanding: 'standby');
        }
      });
    });
  }

  void _showVoteBanner(
    VoteStatusType type,
    String message, {
    int durationMs = 1500,
  }) {
    if (!mounted) return;
    _voteBannerTimer?.cancel();
    setState(() {
      _voteStatus = type;
      _voteMessage = message;
    });

    _voteBannerTimer = Timer(Duration(milliseconds: durationMs), () {
      if (mounted) {
        setState(() => _voteStatus = VoteStatusType.none);
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

  /// Get currently active match Jadwal documentId (if any)
  String _resolveActiveJadwalDocId() {
    final list = ref.read(jadwalListProvider).valueOrNull ?? [];
    if (list.isEmpty) return '';

    final a1 = _gelanggang?.atlit1Id;
    final a2 = _gelanggang?.atlit2Id;

    final match = list.where((j) {
      final mId = j.merahPeserta?.documentId ?? j.merahPeserta?.id?.toString();
      final bId = j.biruPeserta?.documentId ?? j.biruPeserta?.id?.toString();
      return (mId == a1 && bId == a2) ||
          (mId == a2 && bId == a1) ||
          j.statusTanding == 'berlangsung';
    }).firstOrNull;

    return match?.documentId ?? '';
  }

  /// Resolve current active match round (babak)
  String _resolveActiveBabak() {
    if (_liveBabakOverride != null && _liveBabakOverride!.isNotEmpty) {
      return _liveBabakOverride!;
    }
    final list = ref.read(jadwalListProvider).valueOrNull ?? [];
    if (list.isEmpty) return '1';

    final a1 = _gelanggang?.atlit1Id;
    final a2 = _gelanggang?.atlit2Id;

    final match = list.where((j) {
      final mId = j.merahPeserta?.documentId ?? j.merahPeserta?.id?.toString();
      final bId = j.biruPeserta?.documentId ?? j.biruPeserta?.id?.toString();
      return (mId == a1 && bId == a2) ||
          (mId == a2 && bId == a1) ||
          j.statusTanding == 'berlangsung';
    }).firstOrNull;

    return match?.babak ?? '1';
  }

  /// Emit jury vote via Socket.io
  void _submitVote({
    required int jumlah,
    required String jenis,
    required Peserta? atlit,
    required bool isRed,
  }) {
    if (atlit?.documentId == null && atlit?.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Atlet belum siap / belum ada pertandingan aktif.'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    final atlitDocId = atlit?.documentId ?? atlit?.id?.toString() ?? '';
    final jadwalId = _resolveActiveJadwalDocId();
    final babak = _resolveActiveBabak();

    final payload = {
      'gelanggangId': _gelanggang?.documentId ?? '',
      'jadwalId': jadwalId,
      'atletId': atlitDocId,
      'sudut': isRed ? 'merah' : 'biru',
      'jenis': jenis, // 'pukulan' | 'tendangan'
      'jumlah': jumlah, // 1 | 2
      'juriId': _selectedJuriId,
      'babak': babak,
      'menit_ke': '01:30',
    };

    _socketService.emitJuriVote(payload);

    // Immediate local feedback
    _showVoteBanner(
      VoteStatusType.buffered,
      'Input ${jenis.toUpperCase()} (+$jumlah) terkirim. Menunggu juri lain...',
      durationMs: 1200,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ── DEWAN VERIFIKASI POPUP FOR JUDGES ──
  // ══════════════════════════════════════════════════════════════════════════
  void _showVerifikasiJuriDialog(Map<String, dynamic> data) {
    if (_isVerifikasiOpen) return;

    setState(() {
      _isVerifikasiOpen = true;
      _myVerifikasiVote = null;
      _verifikasiFinalVerdict = null;
    });

    final atlitBiruName =
        data['atlitBiru']?['nama'] ?? _atlit1?.namaLengkap ?? 'Sudut Biru';
    final atlitMerahName =
        data['atlitMerah']?['nama'] ?? _atlit2?.namaLengkap ?? 'Sudut Merah';
    final jenisTitle = (data['jenis'] ?? 'jatuhan').toString().toUpperCase();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            _verifikasiDialogSetState = setModalState;

            return Dialog(
              backgroundColor: const Color(0xFF090D16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: Color(0xFF0284C7), width: 2.5),
              ),
              child: Container(
                width: 780,
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF0284C7,
                                ).withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.verified_user_rounded,
                                color: Color(0xFF38BDF8),
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'VERIFIKASI $jenisTitle OLEH DEWAN',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const Text(
                                  'Dewan Pertandingan meminta keputusan verifikasi dari para Juri',
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        _buildJuriBadgeButton(),
                      ],
                    ),

                    const SizedBox(height: 16),
                    const Divider(color: Color(0xFF1E293B), height: 1),
                    const SizedBox(height: 16),

                    // Verdict Notification if already reached
                    if (_verifikasiFinalVerdict != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: _verifikasiFinalVerdict == 'biru'
                              ? const Color(0xFF0369A1).withValues(alpha: 0.4)
                              : _verifikasiFinalVerdict == 'merah'
                              ? const Color(0xFF9F1239).withValues(alpha: 0.4)
                              : const Color(0xFF334155).withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _verifikasiFinalVerdict == 'biru'
                                ? const Color(0xFF38BDF8)
                                : _verifikasiFinalVerdict == 'merah'
                                ? const Color(0xFFFB7185)
                                : const Color(0xFFCBD5E1),
                            width: 2.0,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _verifikasiFinalVerdict == 'invalid'
                                  ? Icons.cancel_outlined
                                  : Icons.check_circle_rounded,
                              color: _verifikasiFinalVerdict == 'biru'
                                  ? const Color(0xFF38BDF8)
                                  : _verifikasiFinalVerdict == 'merah'
                                  ? const Color(0xFFFB7185)
                                  : const Color(0xFFCBD5E1),
                              size: 26,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _verifikasiFinalVerdict == 'invalid'
                                  ? 'KEPUTUSAN KONSENSUS: JATUHAN INVALID (TIDAK SAH)'
                                  : 'KEPUTUSAN KONSENSUS: JATUHAN SAH SUDUT ${_verifikasiFinalVerdict!.toUpperCase()} (+3)',
                              style: TextStyle(
                                color: _verifikasiFinalVerdict == 'biru'
                                    ? const Color(0xFF38BDF8)
                                    : _verifikasiFinalVerdict == 'merah'
                                    ? const Color(0xFFFB7185)
                                    : const Color(0xFFCBD5E1),
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 3 Large Action Buttons (Blue Left, Yellow/Invalid Center, Red Right)
                    Row(
                      children: [
                        // 1. BLUE BUTTON: JATUHAN SUDUT BIRU (+3) (LEFT)
                        Expanded(
                          child: _buildVerifikasiActionButton(
                            label: 'JATUHAN BIRU (+3)',
                            sublabel: atlitBiruName,
                            icon: Icons.sports_martial_arts,
                            baseColor: const Color(0xFF0284C7),
                            gradientColors: [
                              const Color(0xFF0284C7),
                              const Color(0xFF0369A1),
                            ],
                            isSelected: _myVerifikasiVote == 'biru',
                            onTap: _verifikasiFinalVerdict != null
                                ? null
                                : () => _sendVerifikasiVote(
                                    'biru',
                                    setModalState,
                                  ),
                          ),
                        ),

                        const SizedBox(width: 12),

                        // 2. YELLOW / AMBER BUTTON: INVALID / TIDAK SAH (CENTER)
                        Expanded(
                          child: _buildVerifikasiActionButton(
                            label: 'INVALID / TIDAK SAH',
                            sublabel: 'Tidak ada poin jatuhan',
                            icon: Icons.cancel_outlined,
                            baseColor: const Color(0xFFD97706),
                            gradientColors: [
                              const Color(0xFFF59E0B),
                              const Color(0xFFD97706),
                            ],
                            isSelected: _myVerifikasiVote == 'invalid',
                            onTap: _verifikasiFinalVerdict != null
                                ? null
                                : () => _sendVerifikasiVote(
                                    'invalid',
                                    setModalState,
                                  ),
                          ),
                        ),

                        const SizedBox(width: 12),

                        // 3. RED BUTTON: JATUHAN SUDUT MERAH (+3) (RIGHT)
                        Expanded(
                          child: _buildVerifikasiActionButton(
                            label: 'JATUHAN MERAH (+3)',
                            sublabel: atlitMerahName,
                            icon: Icons.sports_martial_arts,
                            baseColor: const Color(0xFFE11D48),
                            gradientColors: [
                              const Color(0xFFE11D48),
                              const Color(0xFFBE123C),
                            ],
                            isSelected: _myVerifikasiVote == 'merah',
                            onTap: _verifikasiFinalVerdict != null
                                ? null
                                : () => _sendVerifikasiVote(
                                    'merah',
                                    setModalState,
                                  ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Status footer
                    if (_myVerifikasiVote != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF064E3B).withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.6),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.check_circle_outline,
                              color: Color(0xFF34D399),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Pilihan Anda [${_myVerifikasiVote!.toUpperCase()}] telah terkirim. Menunggu hasil konsensus juri lain...',
                              style: const TextStyle(
                                color: Color(0xFF6EE7B7),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      const Text(
                        'Silakan tekan salah satu tombol di atas untuk menentukan keputusan Anda',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildVerifikasiActionButton({
    required String label,
    required String sublabel,
    required IconData icon,
    required Color baseColor,
    required List<Color> gradientColors,
    required bool isSelected,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: gradientColors,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? Colors.white
                  : baseColor.withValues(alpha: 0.8),
              width: isSelected ? 3.0 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: baseColor.withValues(alpha: isSelected ? 0.6 : 0.35),
                blurRadius: isSelected ? 18 : 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 38),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                sublabel,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              if (isSelected) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'DIPILIH',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _sendVerifikasiVote(String vote, StateSetter setModalState) {
    setState(() => _myVerifikasiVote = vote);
    setModalState(() {});

    final payload = {
      'gelanggangId': _gelanggang?.documentId ?? '',
      'jadwalId': _resolveActiveJadwalDocId(),
      'jenis': 'jatuhan',
      'pilihan': vote, // 'invalid' | 'biru' | 'merah'
      'juriId': _selectedJuriId,
    };

    _socketService.emitVerifikasiVote(payload);
  }

  void _showJuriSelectorDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: PusakaTheme.slate900,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: PusakaTheme.slate800),
        ),
        title: Row(
          children: const [
            Icon(Icons.badge, color: PusakaTheme.indigo400, size: 22),
            SizedBox(width: 8),
            Text(
              'Pilih Identitas Juri',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Pilih posisi juri Anda di gelanggang ini untuk sistem konsensus skor & verifikasi dewan:',
              style: TextStyle(color: PusakaTheme.slate400, fontSize: 12),
            ),
            const SizedBox(height: 16),
            _buildJuriChoiceTile(ctx, 'Juri 1', 'juri_1', Icons.looks_one),
            const SizedBox(height: 8),
            _buildJuriChoiceTile(ctx, 'Juri 2', 'juri_2', Icons.looks_two),
            const SizedBox(height: 8),
            _buildJuriChoiceTile(ctx, 'Juri 3', 'juri_3', Icons.looks_3),
          ],
        ),
      ),
    );
  }

  Widget _buildJuriChoiceTile(
    BuildContext ctx,
    String title,
    String id,
    IconData icon,
  ) {
    final isSelected = _selectedJuriId == id;
    return InkWell(
      onTap: () {
        _setJuriId(id);
        Navigator.pop(ctx);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? PusakaTheme.indigo950.withValues(alpha: 0.6)
              : PusakaTheme.slate950,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? PusakaTheme.indigo500 : PusakaTheme.slate800,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? PusakaTheme.indigo400 : PusakaTheme.slate400,
              size: 22,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : PusakaTheme.slate300,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: PusakaTheme.indigo400,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _voteBannerTimer?.cancel();
    _connectionSub?.cancel();
    _gelanggangSub?.cancel();
    _voteBufferedSub?.cancel();
    _voteConfirmSub?.cancel();
    _voteRejectedSub?.cancel();
    _verifikasiMulaiSub?.cancel();
    _verifikasiSelesaiSub?.cancel();
    _babakChangedSub?.cancel();
    _timerControlSub?.cancel();
    _pertandinganSelesaiSub?.cancel();
    // Do NOT call _socketService.disconnect() — socket is a shared singleton via Riverpod provider
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

          // Header with back button, Juri selector, and connection badge
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pushReplacementNamed('/');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: PusakaTheme.slate900.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: PusakaTheme.slate800),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_back,
                            color: PusakaTheme.slate400,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Keluar',
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
                  Row(
                    children: [
                      _buildJuriBadgeButton(),
                      const SizedBox(width: 8),
                      ConnectionBadge(isConnected: _isConnected),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJuriBadgeButton() {
    final juriNum = _selectedJuriId.replaceAll('juri_', '');
    return GestureDetector(
      onTap: _showJuriSelectorDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: PusakaTheme.indigo950.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: PusakaTheme.indigo500.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield, color: PusakaTheme.indigo400, size: 13),
            const SizedBox(width: 5),
            Text(
              'JURI $juriNum',
              style: const TextStyle(
                color: PusakaTheme.indigo300,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 3),
            const Icon(
              Icons.arrow_drop_down,
              color: PusakaTheme.indigo400,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoringConsole() {
    final currentBabak = _resolveActiveBabak();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF030712),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F172A), Color(0xFF020617), Color(0xFF000000)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top Bar
              _buildTopBar(),

              // Floating Consensus Feedback Banner
              _buildConsensusBanner(),

              // Dual Scoring Columns with Center Round/Babak Divider
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Sudut Biru (Left)
                      Expanded(
                        flex: 5,
                        child: _buildCornerPanel(
                          atlit: _atlit1,
                          isRed: false,
                          label: 'Sudut Biru',
                          atlitLabel: 'ATLIT 1',
                        ),
                      ),

                      // Center Vertical Babak/Round Divider
                      _buildCenterRoundDivider(currentBabak),

                      // Sudut Merah (Right)
                      Expanded(
                        flex: 5,
                        child: _buildCornerPanel(
                          atlit: _atlit2,
                          isRed: true,
                          label: 'Sudut Merah',
                          atlitLabel: 'ATLIT 2',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom Status Bar
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConsensusBanner() {
    if (_voteStatus == VoteStatusType.none) {
      return const SizedBox.shrink();
    }

    Color bgColor;
    Color borderColor;
    IconData icon;

    switch (_voteStatus) {
      case VoteStatusType.buffered:
        bgColor = PusakaTheme.amber950.withValues(alpha: 0.9);
        borderColor = PusakaTheme.amber400;
        icon = Icons.hourglass_top;
        break;
      case VoteStatusType.confirmed:
        bgColor = PusakaTheme.emerald950.withValues(alpha: 0.9);
        borderColor = PusakaTheme.emerald400;
        icon = Icons.check_circle;
        break;
      case VoteStatusType.rejected:
        bgColor = PusakaTheme.rose950.withValues(alpha: 0.9);
        borderColor = PusakaTheme.rose400;
        icon = Icons.cancel;
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: borderColor, size: 14),
          const SizedBox(width: 6),
          Text(
            _voteMessage,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF090D16).withValues(alpha: 0.95),
        border: const Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.of(context).pushReplacementNamed('/');
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: Colors.white70,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _gelanggang?.event?.namaEvent ?? 'EVENT SILAT 2026',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Arena ${_gelanggang?.keterangan ?? _gelanggang?.kodeGelanggang ?? '-'}',
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            ],
          ),

          Row(
            children: [
              _buildJuriBadgeButton(),
              const SizedBox(width: 8),
              ConnectionBadge(isConnected: _isConnected),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ── CENTER ROUND/BABAK VERTICAL DIVIDER ──
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildCenterRoundDivider(String currentBabak) {
    return Container(
      width: 96,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF090D16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B), width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Header Icon & Title
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1B4B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF4338CA).withValues(alpha: 0.5),
              ),
            ),
            child: const Icon(
              Icons.timer_outlined,
              color: Color(0xFFA78BFA),
              size: 18,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'RONDE',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),

          const SizedBox(height: 10),

          // Babak 1, Babak 2, Babak 3 stacked vertically
          Expanded(child: _buildRoundBadgeItem('1', currentBabak == '1')),
          const SizedBox(height: 6),
          Expanded(child: _buildRoundBadgeItem('2', currentBabak == '2')),
          const SizedBox(height: 6),
          Expanded(child: _buildRoundBadgeItem('3', currentBabak == '3')),
        ],
      ),
    );
  }

  Widget _buildRoundBadgeItem(String roundNumber, bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        gradient: isActive
            ? const LinearGradient(
                colors: [Color(0xFFD97706), Color(0xFFB45309)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              )
            : null,
        color: isActive ? null : const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? const Color(0xFFFBBF24) : const Color(0xFF1E293B),
          width: isActive ? 2.0 : 1.0,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: const Color(0xFFFBBF24).withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'BABAK',
            style: TextStyle(
              color: isActive ? Colors.white : const Color(0xFF64748B),
              fontSize: 8.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            roundNumber,
            style: TextStyle(
              color: isActive ? Colors.white : const Color(0xFF94A3B8),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (isActive) ...[
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'AKTIF',
                style: TextStyle(
                  color: Color(0xFFFDE68A),
                  fontSize: 7.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ── CORNER PANELS (SUDUT BIRU & SUDUT MERAH) ──
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildCornerPanel({
    required Peserta? atlit,
    required bool isRed,
    required String label,
    required String atlitLabel,
  }) {
    final gradientColors = isRed
        ? const [
            Color(0xFFE11D48), // Vibrant bright red (Right)
            Color(0xFFBE123C), // Deep crimson
            Color(0xFF4C0519), // Dark burgundy
            Color(0xFF1C0208), // Deep shadow edge (Left towards center)
          ]
        : const [
            Color(0xFF0284C7), // Vibrant bright blue (Left)
            Color(0xFF0369A1), // Deep royal blue
            Color(0xFF07274E), // Dark navy
            Color(0xFF051329), // Deep shadow edge (Right towards center)
          ];
    final gradientBegin = isRed ? Alignment.centerRight : Alignment.centerLeft;
    final gradientEnd = isRed ? Alignment.centerLeft : Alignment.centerRight;
    final borderColor = isRed
        ? const Color(0xFFFB7185)
        : const Color(0xFF38BDF8);
    final glowColor = isRed ? const Color(0xFFE11D48) : const Color(0xFF0284C7);
    final watermarkText = isRed ? 'MERAH' : 'BIRU';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: gradientBegin,
          end: gradientEnd,
          colors: gradientColors,
          stops: const [0.0, 0.35, 0.75, 1.0],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 2.0),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.35),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Large Faint Watermark
          Positioned(
            left: isRed ? null : 14,
            right: isRed ? 14 : null,
            top: 4,
            child: Text(
              watermarkText,
              style: TextStyle(
                fontSize: 84,
                fontWeight: FontWeight.w900,
                color: Colors.white.withValues(alpha: 0.12),
                letterSpacing: 6,
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header: Corner Name + Athlete Info ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: borderColor.withValues(alpha: 0.7),
                        ),
                      ),
                      child: Text(
                        isRed ? 'SUDUT MERAH' : 'SUDUT BIRU',
                        style: TextStyle(
                          color: isRed
                              ? const Color(0xFFFB7185)
                              : const Color(0xFF38BDF8),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        atlitLabel,
                        style: TextStyle(
                          color: isRed
                              ? const Color(0xFFFECDD3)
                              : const Color(0xFFBAE6FD),
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                // ── Athlete Bar (Name + Contingent) ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        atlit?.namaLengkap?.toUpperCase() ?? 'BELUM ADA ATLET',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        atlit?.kontingen?.toUpperCase() ?? 'KONTINGEN -',
                        style: TextStyle(
                          color: isRed
                              ? const Color(0xFFFECDD3)
                              : const Color(0xFFBAE6FD),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // ── Large Rounded Rectangular Scoring Touch Cards (Pukulan & Tendangan) ──
                Expanded(
                  child: Column(
                    children: [
                      // 1. PUKULAN (+1)
                      _buildJuriScoreTile(
                        label: 'PUKULAN',
                        poinBadge: '+1',
                        icon: Icons.sports_mma_rounded,
                        isRed: isRed,
                        enabled: atlit != null,
                        onTap: () => _submitVote(
                          jumlah: 1,
                          jenis: 'pukulan',
                          atlit: atlit,
                          isRed: isRed,
                        ),
                      ),

                      const SizedBox(height: 8),

                      // 2. TENDANGAN (+2)
                      _buildJuriScoreTile(
                        label: 'TENDANGAN',
                        poinBadge: '+2',
                        icon: Icons.sports_martial_arts_rounded,
                        isRed: isRed,
                        enabled: atlit != null,
                        onTap: () => _submitVote(
                          jumlah: 2,
                          jenis: 'tendangan',
                          atlit: atlit,
                          isRed: isRed,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ── REUSABLE FULL-WIDTH ROUNDED RECTANGULAR SCORING TOUCH CARD ──
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildJuriScoreTile({
    required String label,
    required String poinBadge,
    required IconData icon,
    required bool isRed,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final gradientColors = isRed
        ? const [Color(0xFFE11D48), Color(0xFFBE123C)]
        : const [Color(0xFF0284C7), Color(0xFF0369A1)];
    final borderColor = isRed
        ? const Color(0xFFFB7185)
        : const Color(0xFF38BDF8);
    final glowColor = isRed ? const Color(0xFFE11D48) : const Color(0xFF0284C7);

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: enabled ? 1.0 : 0.4,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderColor, width: 2.2),
              boxShadow: [
                BoxShadow(
                  color: glowColor.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Faint decorative watermark icon in background
                Positioned(
                  right: -10,
                  bottom: -15,
                  child: Icon(
                    icon,
                    size: 110,
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),

                // Main content
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Left: Icon + Label
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Icon(icon, color: Colors.white, size: 34),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              Text(
                                isRed ? 'SUDUT MERAH' : 'SUDUT BIRU',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      // Right: Big Point Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white, width: 2.0),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Text(
                          poinBadge,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final juriNum = _selectedJuriId.replaceAll('juri_', '');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF020617),
        border: const Border(top: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Sistem Konsensus Multi-Juri IPSI © 2026',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 8.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          Row(
            children: [
              const Icon(Icons.touch_app, color: Color(0xFF818CF8), size: 11),
              const SizedBox(width: 3),
              Text(
                'Posisi: Juri $juriNum | Konsensus 2 dari 3 Juri (< 1s)',
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 8.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
