import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../config/theme.dart';
import '../../models/gelanggang.dart';
import '../../providers/gelanggang_provider.dart';
import '../../providers/jadwal_provider.dart';
import '../../services/api_service.dart';
import '../../services/socket_service.dart';

/// Time Keeper Screen — kontrol timer pertandingan secara real-time.
/// Mendukung Count Down timer, sinkronisasi Babak aktif dari Dewan Pertandingan,
/// dan pengaturan durasi menit per babak.
class TimekeeperScreen extends ConsumerStatefulWidget {
  const TimekeeperScreen({super.key});

  @override
  ConsumerState<TimekeeperScreen> createState() => _TimekeeperScreenState();
}

enum _MatchStatus { standby, berlangsung, jeda, selesai }

class _TimekeeperScreenState extends ConsumerState<TimekeeperScreen>
    with SingleTickerProviderStateMixin {
  final SocketService _socketService = SocketService();
  final _api = ApiService();
  bool _isUpdatingStrapi = false;

  // ── Audio Players (Beep & Gong) ──
  final AudioPlayer _beepPlayer = AudioPlayer();
  final AudioPlayer _gongPlayer = AudioPlayer();

  // ── Timer State (Count DOWN) ──
  int _totalRoundSeconds = 120; // Default 2 menit per babak
  int _timerSeconds = 120;
  Timer? _matchTimer;
  // ignore: unused_field
  bool _isTimerRunning = false;
  _MatchStatus _matchStatus = _MatchStatus.standby;

  // ── Babak State (Disinkronkan dari Dewan Pertandingan) ──
  String _activeBabak = '1';

  // Socket Subscriptions
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<Map<String, dynamic>>? _timerControlSub;
  StreamSubscription<Map<String, dynamic>>? _babakChangedSub;
  StreamSubscription<Gelanggang>? _gelanggangSub;
  bool _isConnected = false;

  // Pulse animation
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initSocket());
  }

  void _initSocket() {
    final gelanggang = ref.read(activeGelanggangProvider);
    _socketService.connect(gelanggangDocumentId: gelanggang?.documentId);

    // Initial check for active babak from active jadwal
    final jadwals = ref.read(jadwalListProvider).valueOrNull ?? [];
    if (jadwals.isNotEmpty) {
      final j = jadwals.first;
      if (j.babak != null && j.babak!.isNotEmpty) {
        _activeBabak = j.babak!;
      }
    }

    _connectionSub = _socketService.onConnectionChanged.listen((connected) {
      if (mounted) setState(() => _isConnected = connected);
    });

    _gelanggangSub = _socketService.onGelanggangUpdated.listen((updated) {
      if (mounted) {
        ref.read(activeGelanggangProvider.notifier).updateFromSocket(updated);
      }
    });

    // ── Timer Control Sync Listener ──
    _timerControlSub = _socketService.onTimerControl.listen((data) {
      if (!mounted) return;
      final action = data['action']?.toString();
      final seconds = data['seconds'] as int?;
      final totalSec = data['totalSeconds'] as int?;
      final babak = data['babak']?.toString();

      setState(() {
        if (totalSec != null && totalSec > 0) {
          _totalRoundSeconds = totalSec;
        }
        if (seconds != null) {
          _timerSeconds = seconds;
        }
        if (babak != null && babak.isNotEmpty) {
          _activeBabak = babak;
        }

        switch (action) {
          case 'start':
            _matchStatus = _MatchStatus.berlangsung;
            _startTimerLocal();
          case 'pause':
            _matchStatus = _MatchStatus.jeda;
            _pauseTimerLocal();
          case 'resume':
            _matchStatus = _MatchStatus.berlangsung;
            _startTimerLocal();
          case 'stop':
            _matchStatus = _MatchStatus.selesai;
            _pauseTimerLocal();
          case 'reset':
            _matchStatus = _MatchStatus.standby;
            _pauseTimerLocal();
            _timerSeconds = seconds ?? _totalRoundSeconds;
        }
      });
    });

    // ── Babak / Round Changed Listener (Dari Dewan Pertandingan) ──
    _babakChangedSub = _socketService.onBabakChanged.listen((data) {
      if (!mounted) return;
      final babak = data['babak']?.toString();
      if (babak != null && babak.isNotEmpty) {
        setState(() {
          _activeBabak = babak;
        });
        _showSnack(
          'Babak diubah ke BABAK $babak oleh Dewan Pertandingan',
          PusakaTheme.indigo500,
        );
      }
    });
  }

  /// Membunyikan suara beep pada 5 detik terakhir
  void _playBeep() {
    try {
      _beepPlayer.stop();
      _beepPlayer.setSource(AssetSource('audio/beep.wav'));
      _beepPlayer.setVolume(1.0);
      _beepPlayer.resume();
    } catch (e) {
      debugPrint('[Timekeeper] Error playing beep: $e');
    }
  }

  /// Membunyikan suara gong saat waktu habis
  void _playGong() {
    try {
      _gongPlayer.stop();
      _gongPlayer.setSource(AssetSource('audio/gong.wav'));
      _gongPlayer.setVolume(1.0);
      _gongPlayer.resume();
    } catch (e) {
      debugPrint('[Timekeeper] Error playing gong: $e');
    }
  }

  /// Memulai timer hitung mundur (Count DOWN)
  void _startTimerLocal() {
    _isTimerRunning = true;
    _matchTimer?.cancel();
    _matchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        if (_timerSeconds > 0) {
          setState(() => _timerSeconds--);

          // Bunyikan suara bip di detik ke-5, 4, 3, 2, 1
          if (_timerSeconds <= 5 && _timerSeconds >= 1) {
            _playBeep();
          } else if (_timerSeconds == 0) {
            // Bunyikan suara gong tepat saat waktu 00:00
            _playGong();
          }
        }

        if (_timerSeconds <= 0) {
          // Timer mencapai 00:00 -> otomatis pause & jeda
          _isTimerRunning = false;
          _matchTimer?.cancel();
          setState(() => _matchStatus = _MatchStatus.jeda);

          final gelanggangId =
              ref.read(activeGelanggangProvider)?.documentId ?? '';
          _socketService.emitTimerControl({
            'action': 'pause',
            'seconds': 0,
            'totalSeconds': _totalRoundSeconds,
            'gelanggangId': gelanggangId,
            'status': 'jeda',
            'babak': _activeBabak,
          });

          _showSnack(
            'Waktu Babak $_activeBabak Selesai! (00:00)',
            PusakaTheme.rose500,
          );
        }
      } else {
        _isTimerRunning = false;
        _matchTimer?.cancel();
      }
    });
  }

  void _pauseTimerLocal() {
    _isTimerRunning = false;
    _matchTimer?.cancel();
  }

  /// Mengatur durasi babak (dalam detik)
  void _setDuration(int seconds) {
    if (_matchStatus == _MatchStatus.berlangsung) return;
    setState(() {
      _totalRoundSeconds = seconds;
      _timerSeconds = seconds;
    });
  }

  /// Mengubah durasi relatif (+ / - detik)
  void _adjustDuration(int delta) {
    if (_matchStatus == _MatchStatus.berlangsung) return;
    final newSeconds = (_totalRoundSeconds + delta).clamp(30, 600);
    setState(() {
      _totalRoundSeconds = newSeconds;
      _timerSeconds = newSeconds;
    });
  }

  /// Reset timer kembali ke durasi awal babak
  void _handleResetTimer() {
    if (_matchStatus == _MatchStatus.berlangsung) return;
    final gelanggangId = ref.read(activeGelanggangProvider)?.documentId ?? '';
    setState(() {
      _timerSeconds = _totalRoundSeconds;
      _matchStatus = _MatchStatus.standby;
      _pauseTimerLocal();
    });
    _socketService.emitTimerControl({
      'action': 'reset',
      'seconds': _totalRoundSeconds,
      'totalSeconds': _totalRoundSeconds,
      'gelanggangId': gelanggangId,
      'status': 'standby',
      'babak': _activeBabak,
    });
    _showSnack(
      'Timer di-reset ke ${_formattedDuration(_totalRoundSeconds)}',
      PusakaTheme.indigo500,
    );
  }

  /// Dialog modal untuk input waktu manual (Menit : Detik)
  Future<void> _showCustomDurationDialog() async {
    if (_matchStatus == _MatchStatus.berlangsung) return;

    final currentMins = _totalRoundSeconds ~/ 60;
    final currentSecs = _totalRoundSeconds % 60;

    final minsCtrl = TextEditingController(text: currentMins.toString());
    final secsCtrl =
        TextEditingController(text: currentSecs.toString().padLeft(2, '0'));

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: PusakaTheme.slate900,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: const Color(0xFF38BDF8).withValues(alpha: 0.4),
            ),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.edit_calendar_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                'Atur Waktu Manual',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Masukkan jumlah menit dan detik:',
                style: TextStyle(color: PusakaTheme.slate400, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Menit
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          'MENIT',
                          style: TextStyle(
                            color: PusakaTheme.slate300,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: minsCtrl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: PusakaTheme.slate800,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color:
                                    PusakaTheme.slate700.withValues(alpha: 0.6),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFF38BDF8),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      ':',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  // Detik
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          'DETIK',
                          style: TextStyle(
                            color: PusakaTheme.slate300,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: secsCtrl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: PusakaTheme.slate800,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color:
                                    PusakaTheme.slate700.withValues(alpha: 0.6),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFF38BDF8),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Batal',
                  style: TextStyle(color: PusakaTheme.slate400)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
              onPressed: () {
                final m = int.tryParse(minsCtrl.text.trim()) ?? 0;
                final s = int.tryParse(secsCtrl.text.trim()) ?? 0;
                final total = (m * 60) + s;
                if (total > 0) {
                  Navigator.pop(ctx, total);
                } else {
                  Navigator.pop(ctx, null);
                }
              },
              child: const Text(
                'Terapkan',
                style:
                    TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ),
          ],
        );
      },
    );

    if (result != null && result > 0) {
      _setDuration(result);
      _showSnack(
        'Durasi babak diatur ke ${_formattedDuration(result)}',
        PusakaTheme.emerald500,
      );
    }
  }

  Future<void> _handleMulai() async {
    final gelanggang = ref.read(activeGelanggangProvider);
    final gelanggangId = gelanggang?.documentId ?? '';
    if (gelanggangId.isEmpty || _isUpdatingStrapi) return;

    // Jika timer sudah 0, otomatis reset ke total waktu babak sebelum mulai
    if (_timerSeconds <= 0) {
      _timerSeconds = _totalRoundSeconds;
    }

    // 1. Update status gelanggang di Strapi → memicu gelanggang:updated ke semua layar
    setState(() => _isUpdatingStrapi = true);
    try {
      await _api.updateProtect('gelanggangs', gelanggangId, {
        'data': {
          'status_tanding': 'berlangsung',
        },
      });

      // 2. Update provider lokal
      if (gelanggang != null) {
        final updated = gelanggang.copyWith(statusTanding: 'berlangsung');
        ref.read(activeGelanggangProvider.notifier).updateFromSocket(updated);
      }
    } catch (e) {
      debugPrint('[Timekeeper] Error updating gelanggang status: $e');
    } finally {
      setState(() => _isUpdatingStrapi = false);
    }

    // 3. Emit timer:control start ke semua layar
    setState(() {
      _matchStatus = _MatchStatus.berlangsung;
      _startTimerLocal();
    });
    _socketService.emitTimerControl({
      'action': 'start',
      'seconds': _timerSeconds,
      'totalSeconds': _totalRoundSeconds,
      'gelanggangId': gelanggangId,
      'status': 'berlangsung',
      'babak': _activeBabak,
    });
    _showSnack(
      'Pertandingan Dimulai! (Babak $_activeBabak)',
      PusakaTheme.emerald500,
    );
  }

  void _handleJeda() {
    final gelanggangId = ref.read(activeGelanggangProvider)?.documentId ?? '';
    setState(() {
      _matchStatus = _MatchStatus.jeda;
      _pauseTimerLocal();
    });
    _socketService.emitTimerControl({
      'action': 'pause',
      'seconds': _timerSeconds,
      'totalSeconds': _totalRoundSeconds,
      'gelanggangId': gelanggangId,
      'status': 'jeda',
      'babak': _activeBabak,
    });
    _showSnack('Pertandingan Dijeda', PusakaTheme.amber500);
  }

  void _handleLanjut() {
    final gelanggangId = ref.read(activeGelanggangProvider)?.documentId ?? '';
    setState(() {
      _matchStatus = _MatchStatus.berlangsung;
      _startTimerLocal();
    });
    _socketService.emitTimerControl({
      'action': 'resume',
      'seconds': _timerSeconds,
      'totalSeconds': _totalRoundSeconds,
      'gelanggangId': gelanggangId,
      'status': 'berlangsung',
      'babak': _activeBabak,
    });
    _showSnack('Pertandingan Dilanjutkan', PusakaTheme.emerald500);
  }

  String get _formattedTimer {
    final m = (_timerSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_timerSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _formattedDuration(int secs) {
    final m = (secs ~/ 60).toString();
    final s = (secs % 60).toString().padLeft(2, '0');
    return s == '00' ? '$m Menit' : '$m:$s Menit';
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _matchTimer?.cancel();
    _beepPlayer.dispose();
    _gongPlayer.dispose();
    _connectionSub?.cancel();
    _timerControlSub?.cancel();
    _babakChangedSub?.cancel();
    _gelanggangSub?.cancel();
    _socketService.disconnect();
    super.dispose();
  }

  Color get _statusColor {
    switch (_matchStatus) {
      case _MatchStatus.standby:
        return PusakaTheme.slate500;
      case _MatchStatus.berlangsung:
        if (_timerSeconds <= 15) return const Color(0xFFEF4444); // Urgent warning
        return PusakaTheme.emerald500;
      case _MatchStatus.jeda:
        return PusakaTheme.amber500;
      case _MatchStatus.selesai:
        return PusakaTheme.rose500;
    }
  }

  Color get _statusGlow {
    switch (_matchStatus) {
      case _MatchStatus.standby:
        return PusakaTheme.slate600;
      case _MatchStatus.berlangsung:
        if (_timerSeconds <= 15) return const Color(0xFFDC2626);
        return PusakaTheme.emerald600;
      case _MatchStatus.jeda:
        return const Color(0xFFD97706);
      case _MatchStatus.selesai:
        return PusakaTheme.rose600;
    }
  }

  String get _statusLabel {
    switch (_matchStatus) {
      case _MatchStatus.standby:
        return 'STANDBY';
      case _MatchStatus.berlangsung:
        return 'BERLANGSUNG';
      case _MatchStatus.jeda:
        return 'DIJEDA';
      case _MatchStatus.selesai:
        return 'SELESAI';
    }
  }

  @override
  Widget build(BuildContext context) {
    final gelanggang = ref.watch(activeGelanggangProvider);
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration:
            const BoxDecoration(gradient: PusakaTheme.backgroundGradient),
        child: Stack(
          children: [
            Positioned(
              top: -60,
              left: size.width * 0.2,
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) => Container(
                  width: 400,
                  height: 400,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _statusGlow.withValues(
                      alpha: 0.06 + (_pulseController.value * 0.04),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -40,
              right: -40,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: PusakaTheme.indigo600.withValues(alpha: 0.07),
                ),
              ),
            ),
            SafeArea(
              child: isLandscape
                  ? _buildLandscapeLayout(
                      gelanggang?.kodeGelanggang ?? 'Gelanggang')
                  : _buildPortraitLayout(
                      gelanggang?.kodeGelanggang ?? 'Gelanggang'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLandscapeLayout(String gelanggangName) {
    return Row(
      children: [
        Expanded(
          flex: 6,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildHeader(gelanggangName, compact: true),
                  const SizedBox(height: 12),
                  _buildBabakBanner(),
                  const SizedBox(height: 14),
                  _buildTimerDisplay(large: true),
                  const SizedBox(height: 12),
                  _buildDurationSelector(),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStatusBadge(),
                const SizedBox(height: 24),
                _buildControlButtons(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPortraitLayout(String gelanggangName) {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 8),
          _buildHeader(gelanggangName, compact: false),
          const SizedBox(height: 16),
          _buildBabakBanner(),
          const SizedBox(height: 20),
          _buildTimerDisplay(large: false),
          const SizedBox(height: 16),
          _buildDurationSelector(),
          const SizedBox(height: 16),
          _buildStatusBadge(),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _buildControlButtons(),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildHeader(String gelanggangName, {required bool compact}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 0 : 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pushReplacementNamed('/'),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: PusakaTheme.slate800.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: PusakaTheme.slate700.withValues(alpha: 0.5)),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: PusakaTheme.slate300,
                size: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [PusakaTheme.emerald600, PusakaTheme.teal600]),
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                const Icon(Icons.timer_rounded, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TIME KEEPER',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                Text(
                  gelanggangName,
                  style: const TextStyle(
                    color: PusakaTheme.slate400,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: (_isConnected ? PusakaTheme.emerald950 : PusakaTheme.rose950)
                  .withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: (_isConnected
                        ? PusakaTheme.emerald400
                        : PusakaTheme.rose400)
                    .withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isConnected
                        ? PusakaTheme.emerald400
                        : PusakaTheme.rose400,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  _isConnected ? 'Online' : 'Offline',
                  style: TextStyle(
                    color: _isConnected
                        ? PusakaTheme.emerald400
                        : PusakaTheme.rose400,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Banner informasi Babak aktif yang disinkronkan dari Dewan Pertandingan
  Widget _buildBabakBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.12),
            blurRadius: 16,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, color: Colors.white, size: 14),
                SizedBox(width: 4),
                Text(
                  'DEWAN',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 3 Babak Indicator Tabs
          Row(
            mainAxisSize: MainAxisSize.min,
            children: ['1', '2', '3'].map((b) {
              final isActive = _activeBabak == b;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  gradient: isActive
                      ? const LinearGradient(
                          colors: [Color(0xFF10B981), Color(0xFF059669)],
                        )
                      : null,
                  color: isActive
                      ? null
                      : PusakaTheme.slate800.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isActive
                        ? const Color(0xFF34D399)
                        : PusakaTheme.slate700.withValues(alpha: 0.4),
                    width: isActive ? 1.4 : 1.0,
                  ),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color:
                                const Color(0xFF10B981).withValues(alpha: 0.4),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  'BABAK $b',
                  style: TextStyle(
                    color: isActive ? Colors.white : PusakaTheme.slate400,
                    fontSize: 11,
                    fontWeight:
                        isActive ? FontWeight.w900 : FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// Tampilan hitung mundur (Count Down)
  Widget _buildTimerDisplay({required bool large}) {
    final fontSize = large ? 100.0 : 80.0;
    final isUrgent =
        _timerSeconds <= 15 && _matchStatus == _MatchStatus.berlangsung;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final glowOpacity = _matchStatus == _MatchStatus.berlangsung
            ? (isUrgent
                ? 0.5 + (_pulseController.value * 0.4)
                : 0.3 + (_pulseController.value * 0.2))
            : 0.15;

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: large ? 42 : 28,
            vertical: large ? 20 : 16,
          ),
          decoration: BoxDecoration(
            color: PusakaTheme.slate900.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isUrgent
                  ? const Color(0xFFEF4444)
                  : _statusColor.withValues(alpha: 0.4),
              width: isUrgent ? 2.0 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _statusGlow.withValues(alpha: glowOpacity),
                blurRadius: isUrgent ? 70 : 50,
                spreadRadius: isUrgent ? 6 : 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formattedTimer,
                style: TextStyle(
                  color: isUrgent ? const Color(0xFFFCA5A5) : Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'COUNT DOWN • BABAK $_activeBabak',
                style: TextStyle(
                  color: isUrgent
                      ? const Color(0xFFF87171)
                      : PusakaTheme.slate400,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Pengatur durasi menit per babak (Presets & +/- buttons)
  Widget _buildDurationSelector() {
    final isRunning = _matchStatus == _MatchStatus.berlangsung;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isRunning ? 0.35 : 1.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1329).withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: PusakaTheme.slate700.withValues(alpha: 0.5),
            width: 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: isRunning ? null : _showCustomDurationDialog,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.tune_rounded,
                    color: Color(0xFF38BDF8),
                    size: 13,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'WAKTU BABAK: ${_formattedDuration(_totalRoundSeconds)}',
                    style: const TextStyle(
                      color: PusakaTheme.slate200,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_outlined,
                            color: Color(0xFF38BDF8), size: 10),
                        SizedBox(width: 3),
                        Text(
                          'UBAH',
                          style: TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Preset 1:00 (60s)
                _buildDurationChip(
                  label: '1m',
                  seconds: 60,
                  isSelected: _totalRoundSeconds == 60,
                  enabled: !isRunning,
                ),
                // Preset 1:30 (90s)
                _buildDurationChip(
                  label: '1:30',
                  seconds: 90,
                  isSelected: _totalRoundSeconds == 90,
                  enabled: !isRunning,
                ),
                // Preset 2:00 (120s) - Default Silat
                _buildDurationChip(
                  label: '2m',
                  seconds: 120,
                  isSelected: _totalRoundSeconds == 120,
                  enabled: !isRunning,
                ),
                // Preset 3:00 (180s)
                _buildDurationChip(
                  label: '3m',
                  seconds: 180,
                  isSelected: _totalRoundSeconds == 180,
                  enabled: !isRunning,
                ),
                // If custom non-preset duration is active, show its chip
                if (![60, 90, 120, 180].contains(_totalRoundSeconds))
                  _buildDurationChip(
                    label: _formattedDuration(_totalRoundSeconds),
                    seconds: _totalRoundSeconds,
                    isSelected: true,
                    enabled: !isRunning,
                  ),
                // Tombol Manual Dialog
                GestureDetector(
                  onTap: isRunning ? null : _showCustomDurationDialog,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.6),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_note_rounded,
                            color: Color(0xFFE0F2FE), size: 13),
                        SizedBox(width: 3),
                        Text(
                          'Manual',
                          style: TextStyle(
                            color: Color(0xFFE0F2FE),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Custom -30s
                GestureDetector(
                  onTap: isRunning ? null : () => _adjustDuration(-30),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: PusakaTheme.slate800,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: PusakaTheme.slate700.withValues(alpha: 0.5)),
                    ),
                    child: const Text(
                      '-30s',
                      style: TextStyle(
                        color: PusakaTheme.slate300,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                // Custom +30s
                GestureDetector(
                  onTap: isRunning ? null : () => _adjustDuration(30),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: PusakaTheme.slate800,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: PusakaTheme.slate700.withValues(alpha: 0.5)),
                    ),
                    child: const Text(
                      '+30s',
                      style: TextStyle(
                        color: PusakaTheme.slate300,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                // Reset Button
                GestureDetector(
                  onTap: isRunning ? null : _handleResetTimer,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4338CA).withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.restart_alt_rounded,
                            color: Color(0xFFA5B4FC), size: 12),
                        SizedBox(width: 3),
                        Text(
                          'RESET',
                          style: TextStyle(
                            color: Color(0xFFA5B4FC),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationChip({
    required String label,
    required int seconds,
    required bool isSelected,
    required bool enabled,
  }) {
    return GestureDetector(
      onTap: enabled ? () => _setDuration(seconds) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                )
              : null,
          color: isSelected
              ? null
              : PusakaTheme.slate800.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF38BDF8)
                : PusakaTheme.slate700.withValues(alpha: 0.4),
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : PusakaTheme.slate400,
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: _statusColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: _statusColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_matchStatus == _MatchStatus.berlangsung)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) => Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _statusColor
                      .withValues(alpha: 0.5 + (_pulseController.value * 0.5)),
                ),
              ),
            )
          else
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 8),
              decoration:
                  BoxDecoration(shape: BoxShape.circle, color: _statusColor),
            ),
          Text(
            _statusLabel,
            style: TextStyle(
              color: _statusColor,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    ).animate(key: ValueKey(_matchStatus)).fadeIn(duration: 300.ms);
  }

  Widget _buildControlButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_matchStatus == _MatchStatus.standby ||
            _matchStatus == _MatchStatus.selesai) ...[
          _buildControlButton(
            id: 'btn_mulai',
            label: 'MULAI (BABAK $_activeBabak)',
            icon: Icons.play_arrow_rounded,
            gradient: const LinearGradient(
                colors: [PusakaTheme.emerald500, PusakaTheme.teal600]),
            onTap: _handleMulai,
          ),
        ] else if (_matchStatus == _MatchStatus.berlangsung) ...[
          _buildControlButton(
            id: 'btn_jeda',
            label: 'JEDA',
            icon: Icons.pause_rounded,
            gradient: const LinearGradient(
                colors: [Color(0xFFD97706), PusakaTheme.amber500]),
            onTap: _handleJeda,
          ),
        ] else if (_matchStatus == _MatchStatus.jeda) ...[
          _buildControlButton(
            id: 'btn_lanjut',
            label: 'LANJUT',
            icon: Icons.play_arrow_rounded,
            gradient: const LinearGradient(
                colors: [PusakaTheme.emerald500, PusakaTheme.teal600]),
            onTap: _handleLanjut,
          ),
        ],
      ],
    );
  }

  Widget _buildControlButton({
    required String id,
    required String label,
    required IconData icon,
    required LinearGradient gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: gradient.colors.first.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 26),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    )
        .animate(key: ValueKey('$id${_matchStatus.name}'))
        .fadeIn(duration: 350.ms)
        .scale(
          begin: const Offset(0.92, 0.92),
          duration: 350.ms,
          curve: Curves.easeOutBack,
        );
  }
}
