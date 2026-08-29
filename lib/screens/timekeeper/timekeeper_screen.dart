import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../config/theme.dart';
import '../../models/gelanggang.dart';
import '../../providers/gelanggang_provider.dart';
import '../../services/api_service.dart';
import '../../services/socket_service.dart';

/// Time Keeper Screen — kontrol timer pertandingan secara real-time.
/// Mensinkronisasikan mulai, jeda, lanjut, dan selesai ke semua layar
/// via socket timer:control.
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

  // Timer State
  int _timerSeconds = 0;
  Timer? _matchTimer;
  // ignore: unused_field
  bool _isTimerRunning = false;
  _MatchStatus _matchStatus = _MatchStatus.standby;

  // Socket Subscriptions
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<Map<String, dynamic>>? _timerControlSub;
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

    _connectionSub = _socketService.onConnectionChanged.listen((connected) {
      if (mounted) setState(() => _isConnected = connected);
    });

    _timerControlSub = _socketService.onTimerControl.listen((data) {
      if (!mounted) return;
      final action = data['action']?.toString();
      final seconds = data['seconds'] as int?;
      setState(() {
        if (seconds != null) _timerSeconds = seconds;
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
            _timerSeconds = 0;
        }
      });
    });
  }

  void _startTimerLocal() {
    _isTimerRunning = true;
    _matchTimer?.cancel();
    _matchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _timerSeconds++);
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

  Future<void> _handleMulai() async {
    final gelanggang = ref.read(activeGelanggangProvider);
    final gelanggangId = gelanggang?.documentId ?? '';
    if (gelanggangId.isEmpty || _isUpdatingStrapi) return;

    // 1. Update status gelanggang di Strapi → memicu gelanggang:updated ke semua layar
    setState(() => _isUpdatingStrapi = true);
    try {
      final a1 = gelanggang?.atlit1Id ?? '';
      final a2 = gelanggang?.atlit2Id ?? '';
      await _api.updateProtect('gelanggangs', gelanggangId, {
        'data': {
          'status_tanding': 'berlangsung',
          if (a1.isNotEmpty) 'atlit_1_id': a1,
          if (a2.isNotEmpty) 'atlit_2_id': a2,
        },
      });

      // 2. Update provider lokal
      final updated = Gelanggang(
        id: gelanggang!.id,
        documentId: gelanggang.documentId,
        kodeGelanggang: gelanggang.kodeGelanggang,
        statusTanding: 'berlangsung',
        atlit1Id: gelanggang.atlit1Id,
        atlit2Id: gelanggang.atlit2Id,
        keterangan: gelanggang.keterangan,
        event: gelanggang.event,
      );
      ref.read(activeGelanggangProvider.notifier).updateFromSocket(updated);
    } catch (e) {
      debugPrint('[Timekeeper] Error updating gelanggang status: $e');
    } finally {
      setState(() => _isUpdatingStrapi = false);
    }

    // 3. Emit timer:control start ke semua layar
    setState(() {
      _matchStatus = _MatchStatus.berlangsung;
      _timerSeconds = 0;
      _startTimerLocal();
    });
    _socketService.emitTimerControl({
      'action': 'start',
      'seconds': 0,
      'gelanggangId': gelanggangId,
      'status': 'berlangsung',
    });
    _showSnack('Pertandingan Dimulai!', PusakaTheme.emerald500);
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
      'gelanggangId': gelanggangId,
      'status': 'jeda',
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
      'gelanggangId': gelanggangId,
      'status': 'berlangsung',
    });
    _showSnack('Pertandingan Dilanjutkan', PusakaTheme.emerald500);
  }

  Future<void> _handleSelesai() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PusakaTheme.slate900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.stop_circle_rounded, color: PusakaTheme.rose500, size: 28),
            SizedBox(width: 10),
            Text(
              'Selesai Tanding?',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: const Text(
          'Yakin ingin menghentikan timer dan mengakhiri pertandingan?',
          style: TextStyle(color: PusakaTheme.slate400, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: PusakaTheme.slate400)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: PusakaTheme.rose600,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Selesai', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final gelanggang = ref.read(activeGelanggangProvider);
    final gelanggangId = gelanggang?.documentId ?? '';

    // 1. Update status gelanggang ke 'standby' di Strapi
    if (gelanggangId.isNotEmpty && !_isUpdatingStrapi) {
      setState(() => _isUpdatingStrapi = true);
      try {
        await _api.updateProtect('gelanggangs', gelanggangId, {
          'data': {'status_tanding': 'standby'},
        });
        final updated = Gelanggang(
          id: gelanggang!.id,
          documentId: gelanggang.documentId,
          kodeGelanggang: gelanggang.kodeGelanggang,
          statusTanding: 'standby',
          atlit1Id: gelanggang.atlit1Id,
          atlit2Id: gelanggang.atlit2Id,
          keterangan: gelanggang.keterangan,
          event: gelanggang.event,
        );
        ref.read(activeGelanggangProvider.notifier).updateFromSocket(updated);
      } catch (e) {
        debugPrint('[Timekeeper] Error resetting gelanggang status: $e');
      } finally {
        setState(() => _isUpdatingStrapi = false);
      }
    }

    // 2. Update local state & stop timer
    setState(() {
      _matchStatus = _MatchStatus.selesai;
      _pauseTimerLocal();
    });

    // 3. Emit timer:control stop ke semua layar
    _socketService.emitTimerControl({
      'action': 'stop',
      'seconds': _timerSeconds,
      'gelanggangId': gelanggangId,
      'status': 'selesai',
    });
    _showSnack('Pertandingan Dihentikan', PusakaTheme.rose500);
  }

  String get _formattedTimer {
    final m = (_timerSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_timerSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
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
    _connectionSub?.cancel();
    _timerControlSub?.cancel();
    _socketService.disconnect();
    super.dispose();
  }

  Color get _statusColor {
    switch (_matchStatus) {
      case _MatchStatus.standby:
        return PusakaTheme.slate500;
      case _MatchStatus.berlangsung:
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
        decoration: const BoxDecoration(gradient: PusakaTheme.backgroundGradient),
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
                  ? _buildLandscapeLayout(gelanggang?.kodeGelanggang ?? 'Gelanggang')
                  : _buildPortraitLayout(gelanggang?.kodeGelanggang ?? 'Gelanggang'),
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildHeader(gelanggangName, compact: true),
              const SizedBox(height: 16),
              _buildTimerDisplay(large: true),
            ],
          ),
        ),
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStatusBadge(),
                const SizedBox(height: 32),
                _buildControlButtons(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPortraitLayout(String gelanggangName) {
    return Column(
      children: [
        const SizedBox(height: 8),
        _buildHeader(gelanggangName, compact: false),
        const Spacer(flex: 1),
        _buildTimerDisplay(large: false),
        const SizedBox(height: 16),
        _buildStatusBadge(),
        const Spacer(flex: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _buildControlButtons(),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildHeader(String gelanggangName, {required bool compact}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: compact ? 0 : 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pushReplacementNamed('/'),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: PusakaTheme.slate800.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: PusakaTheme.slate700.withValues(alpha: 0.5)),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: PusakaTheme.slate300, size: 14),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [PusakaTheme.emerald600, PusakaTheme.teal600]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.timer_rounded, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TIME KEEPER',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                ),
                Text(
                  gelanggangName,
                  style: const TextStyle(color: PusakaTheme.slate400, fontSize: 10, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: (_isConnected ? PusakaTheme.emerald950 : PusakaTheme.rose950).withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: (_isConnected ? PusakaTheme.emerald400 : PusakaTheme.rose400).withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isConnected ? PusakaTheme.emerald400 : PusakaTheme.rose400,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  _isConnected ? 'Online' : 'Offline',
                  style: TextStyle(
                    color: _isConnected ? PusakaTheme.emerald400 : PusakaTheme.rose400,
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

  Widget _buildTimerDisplay({required bool large}) {
    final fontSize = large ? 110.0 : 88.0;
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final glowOpacity = _matchStatus == _MatchStatus.berlangsung
            ? 0.3 + (_pulseController.value * 0.2)
            : 0.15;
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: large ? 48 : 32,
            vertical: large ? 28 : 20,
          ),
          decoration: BoxDecoration(
            color: PusakaTheme.slate900.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _statusColor.withValues(alpha: 0.3), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: _statusGlow.withValues(alpha: glowOpacity),
                blurRadius: 60,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Text(
            _formattedTimer,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              letterSpacing: -2,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
      },
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
                width: 8, height: 8,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _statusColor.withValues(alpha: 0.5 + (_pulseController.value * 0.5)),
                ),
              ),
            )
          else
            Container(
              width: 8, height: 8,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(shape: BoxShape.circle, color: _statusColor),
            ),
          Text(
            _statusLabel,
            style: TextStyle(color: _statusColor, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 2),
          ),
        ],
      ),
    ).animate(key: ValueKey(_matchStatus)).fadeIn(duration: 300.ms);
  }

  Widget _buildControlButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_matchStatus == _MatchStatus.standby || _matchStatus == _MatchStatus.selesai) ...[
          _buildControlButton(
            id: 'btn_mulai',
            label: 'MULAI',
            icon: Icons.play_arrow_rounded,
            gradient: const LinearGradient(colors: [PusakaTheme.emerald500, PusakaTheme.teal600]),
            onTap: _handleMulai,
          ),
        ] else if (_matchStatus == _MatchStatus.berlangsung) ...[
          Row(
            children: [
              Expanded(
                child: _buildControlButton(
                  id: 'btn_jeda',
                  label: 'JEDA',
                  icon: Icons.pause_rounded,
                  gradient: const LinearGradient(colors: [Color(0xFFD97706), PusakaTheme.amber500]),
                  onTap: _handleJeda,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildControlButton(
                  id: 'btn_selesai_run',
                  label: 'SELESAI',
                  icon: Icons.stop_rounded,
                  gradient: const LinearGradient(colors: [PusakaTheme.rose600, Color(0xFFDC2626)]),
                  onTap: _handleSelesai,
                ),
              ),
            ],
          ),
        ] else if (_matchStatus == _MatchStatus.jeda) ...[
          Row(
            children: [
              Expanded(
                child: _buildControlButton(
                  id: 'btn_lanjut',
                  label: 'LANJUT',
                  icon: Icons.play_arrow_rounded,
                  gradient: const LinearGradient(colors: [PusakaTheme.emerald500, PusakaTheme.teal600]),
                  onTap: _handleLanjut,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildControlButton(
                  id: 'btn_selesai_jeda',
                  label: 'SELESAI',
                  icon: Icons.stop_rounded,
                  gradient: const LinearGradient(colors: [PusakaTheme.rose600, Color(0xFFDC2626)]),
                  onTap: _handleSelesai,
                ),
              ),
            ],
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
