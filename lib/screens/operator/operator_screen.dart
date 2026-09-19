import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../models/gelanggang.dart';
import '../../models/jadwal.dart';
import '../../models/nilai.dart';
import '../../models/peserta.dart';
import '../../providers/gelanggang_provider.dart';
import '../../providers/jadwal_provider.dart';
import '../../providers/nilai_provider.dart';
import '../../providers/socket_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/connection_badge.dart';

/// Operator Screen — Dewan Pertandingan Console (Tablet Optimized).
/// Features vibrant dynamic gradients for Sudut Biru and Sudut Merah, precision 3x3 Dewan button grids,
/// interactive match picker modal, central timer controls with Dewan Verifikasi buttons, and persistent score history.
class OperatorScreen extends ConsumerStatefulWidget {
  const OperatorScreen({super.key});

  @override
  ConsumerState<OperatorScreen> createState() => _OperatorScreenState();
}

class _OperatorScreenState extends ConsumerState<OperatorScreen> {
  late final SocketService _socketService;
  final _api = ApiService();

  bool _isConnected = false;
  bool _tandingStatus = false;
  Peserta? _atlitBiru; // Sudut Biru (Left)
  Peserta? _atlitMerah; // Sudut Merah (Right)
  Jadwal? _selectedJadwal;
  String _activeBabak = '1'; // Active Round: '1', '2', or '3'

  // ── Match Timer State (Count UP) ──
  int _timerSeconds = 0;
  bool _isTimerRunning = false;
  Timer? _matchTimer;

  // ── KP State Tracking ──
  int _kpBinaanMerah = 0;
  int _kpTeguranMerah = 0;
  int _kpPembinaanMerah = 0;

  int _kpBinaanBiru = 0;
  int _kpTeguranBiru = 0;
  int _kpPembinaanBiru = 0;

  // ── Dewan Verification State (Jatuhan / Pelanggaran) ──
  bool _verifikasiActive = false;
  String _verifikasiJenis = 'jatuhan';
  final Map<String, String?> _verifikasiVotes = {
    'juri_1': null,
    'juri_2': null,
    'juri_3': null,
  };
  String? _verifikasiHasil;
  StateSetter? _dialogSetState;

  StreamSubscription? _connectionSub;
  StreamSubscription? _gelanggangSub;
  StreamSubscription? _kpStatusSub;
  StreamSubscription? _pesertaDsqSub;
  StreamSubscription? _nilaiSub;
  StreamSubscription? _nilaiKpSub;
  StreamSubscription? _verifikasiVoteSub;
  StreamSubscription? _timerControlSub;
  StreamSubscription? _babakChangedSub;
  StreamSubscription? _juriReadySub;
  Timer? _fetchNilaiDebounce;

  // ── Juri Ready Status Indicators ──
  bool _juri1Ready = false;
  bool _juri2Ready = false;
  bool _juri3Ready = false;

  // ── Buzzer State ──
  final AudioPlayer _buzzerPlayer = AudioPlayer();
  int _buzzerCountdown = 0;
  bool _isBuzzerSounding = false;
  bool get _isBuzzerActive => _buzzerCountdown > 0 || _isBuzzerSounding;
  Timer? _buzzerTimer;
  Timer? _buzzerSoundTimer;

  @override
  void initState() {
    super.initState();
    // Resolve shared singleton socket service before any async work
    _socketService = ref.read(socketServiceProvider);
    // Force landscape orientation for console screens
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _initData();
  }

  void _initData() {
    final gelanggang = ref.read(activeGelanggangProvider);
    if (gelanggang != null) {
      _tandingStatus = gelanggang.isBerlangsung;
      if (gelanggang.isBerlangsung) {
        _fetchPeserta(gelanggang.atlit1Id ?? '', 1); // atlit1 = Biru
        _fetchPeserta(gelanggang.atlit2Id ?? '', 2); // atlit2 = Merah
        _fetchNilai();
        _startTimer();
      }

      // Fetch jadwal
      ref.read(jadwalListProvider.notifier).fetchJadwal(gelanggang);

      // Connect socket
      _socketService.connect(gelanggangDocumentId: gelanggang.documentId);
    }

    _connectionSub = _socketService.onConnectionChanged.listen((connected) {
      if (mounted) setState(() => _isConnected = connected);
    });

    _gelanggangSub = _socketService.onGelanggangUpdated.listen((updated) {
      if (mounted) {
        final wasBerlangsung = _tandingStatus;
        setState(() => _tandingStatus = updated.isBerlangsung);
        ref.read(activeGelanggangProvider.notifier).updateFromSocket(updated);
        if (updated.isBerlangsung) {
          _fetchPeserta(updated.atlit1Id ?? '', 1);
          _fetchPeserta(updated.atlit2Id ?? '', 2);
          _fetchNilai();
          _startTimer();
        } else {
          _pauseTimer();
          // Hanya reset lampu indikator juri jika sebelumnya pertandingan sedang berjalan lalu dihentikan/selesai
          if (wasBerlangsung) {
            _juri1Ready = false;
            _juri2Ready = false;
            _juri3Ready = false;
          }
        }
      }
    });

    // ── KP Status Socket Listener ──
    _kpStatusSub = _socketService.onKpStatus.listen((data) {
      if (!mounted) return;
      setState(() {
        final merah = data['merah'] ?? data;
        final biru = data['biru'] ?? data;
        final aksi = data['aksi']?.toString();

        if (aksi == 'reset_babak') {
          _kpBinaanMerah = 0;
          _kpTeguranMerah = 0;
          _kpBinaanBiru = 0;
          _kpTeguranBiru = 0;
        } else {
          if (data.containsKey('merah') || data['sudut'] == 'merah') {
            _kpBinaanMerah =
                (merah['binaan'] ?? merah['kp_binaan_merah'] ?? _kpBinaanMerah)
                    as int;
            _kpTeguranMerah =
                (merah['teguran'] ??
                        merah['kp_teguran_merah'] ??
                        _kpTeguranMerah)
                    as int;
            _kpPembinaanMerah =
                (merah['pembinaan'] ??
                        merah['kp_pembinaan_merah'] ??
                        _kpPembinaanMerah)
                    as int;
          }

          if (data.containsKey('biru') || data['sudut'] == 'biru') {
            _kpBinaanBiru =
                (biru['binaan'] ?? biru['kp_binaan_biru'] ?? _kpBinaanBiru)
                    as int;
            _kpTeguranBiru =
                (biru['teguran'] ?? biru['kp_teguran_biru'] ?? _kpTeguranBiru)
                    as int;
            _kpPembinaanBiru =
                (biru['pembinaan'] ??
                        biru['kp_pembinaan_biru'] ??
                        _kpPembinaanBiru)
                    as int;
          }
        }
      });

      // Debounce fetchNilai to synchronize state authoritatively
      _fetchNilaiDebounce?.cancel();
      _fetchNilaiDebounce = Timer(const Duration(milliseconds: 700), () {
        if (mounted) _fetchNilai();
      });
    });

    // ── Nilai Masuk Socket Listener ──
    _nilaiSub = _socketService.onNilaiCreated.listen((n) {
      if (mounted) {
        // Skip entries created by this Dewan screen (KP) since they are already
        // handled via the optimistic addFromSocket in _handleKpAction.
        // Strapi's afterCreate lifecycle broadcasts nilai:created after REST persist,
        // which would cause a duplicate entry in the history list.
        if (n.juriId == 'KP') return;
        ref.read(nilaiListProvider.notifier).addFromSocket(n);
      }
    });

    // ── KP Nilai Socket Listener (Batal Jatuhan / Deductions) ──
    _nilaiKpSub = _socketService.onNilaiKp.listen((data) {
      if (!mounted) return;
      // Skip events that this Dewan screen emitted itself (juri_id == 'KP').
      // Those are already handled by the optimistic addFromSocket in _handleKpAction.
      final juriId = data['juri_id']?.toString() ?? data['juriId']?.toString() ?? '';
      if (juriId == 'KP') return;
      try {
        final nilai = Nilai.fromJson(Map<String, dynamic>.from(data));
        ref.read(nilaiListProvider.notifier).addFromSocket(nilai);
      } catch (e) {
        debugPrint('[Dewan] Error parsing nilai:kp payload: $e');
      }
    });

    // ── Disqualification Socket Listener ──
    _pesertaDsqSub = _socketService.onPesertaDsq.listen((data) {
      if (!mounted) return;
      final sudut = data['sudut']?.toString().toUpperCase() ?? 'PESERTA';
      final nama = data['nama']?.toString() ?? '';

      setState(() {
        _tandingStatus = false;
        _pauseTimer();
      });
      _showDsqDialog(sudut, nama);
    });

    // ── Verification Vote Listener (From Judges) ──
    _verifikasiVoteSub = _socketService.onVerifikasiVote.listen((data) {
      if (!mounted || !_verifikasiActive) return;
      final juriId =
          data['juriId']?.toString() ?? data['juri_id']?.toString() ?? '';
      final pilihan = data['pilihan']?.toString() ?? '';

      if (['juri_1', 'juri_2', 'juri_3'].contains(juriId) &&
          pilihan.isNotEmpty) {
        setState(() {
          _verifikasiVotes[juriId] = pilihan;
        });
        _dialogSetState?.call(() {});
        _evaluasiKonsensusVerifikasi();
      }
    });

    // ── Synchronized Timer Control Listener ──
    _timerControlSub = _socketService.onTimerControl.listen((data) {
      if (!mounted) return;
      final action = data['action']?.toString();
      final seconds = data['seconds'] as int?;

      setState(() {
        if (seconds != null) _timerSeconds = seconds;
        if (action == 'start') {
          // Timekeeper mulai pertandingan → aktifkan semua tombol penilaian
          _tandingStatus = true;
          _startTimer();
        } else if (action == 'resume') {
          _startTimer();
        } else if (action == 'pause') {
          _pauseTimer();
        } else if (action == 'reset') {
          _pauseTimer();
          _timerSeconds = 0;
          _kpBinaanBiru = 0;
          _kpTeguranBiru = 0;
          _kpBinaanMerah = 0;
          _kpTeguranMerah = 0;
          _juri1Ready = false;
          _juri2Ready = false;
          _juri3Ready = false;
        } else if (action == 'stop') {
          // Timekeeper stop pertandingan → nonaktifkan tombol penilaian
          _tandingStatus = false;
          _pauseTimer();
          _juri1Ready = false;
          _juri2Ready = false;
          _juri3Ready = false;
        }
      });
    });

    // ── Babak / Round Change Sync Listener ──
    _babakChangedSub = _socketService.onBabakChanged.listen((data) {
      if (!mounted) return;
      final babak = data['babak']?.toString();
      if (babak != null && babak.isNotEmpty) {
        setState(() {
          _activeBabak = babak;
          if (_selectedJadwal != null) {
            _selectedJadwal = _selectedJadwal!.copyWith(babak: babak);
          }
        });
      }
    });

    // ── Juri Ready Status Listener ──
    _juriReadySub = _socketService.onJuriReady.listen((data) {
      if (!mounted) return;
      debugPrint('[Dewan] juri:ready received: $data');
      final juriId = data['juriId']?.toString() ??
          data['juri_id']?.toString() ??
          data['juri']?.toString() ??
          '';
      final isReady = data['isReady'] == true ||
          data['is_ready'] == true ||
          data['ready'] == true ||
          data['isReady'] == 'true';

      setState(() {
        if (juriId == 'juri_1' || juriId == '1') _juri1Ready = isReady;
        if (juriId == 'juri_2' || juriId == '2') _juri2Ready = isReady;
        if (juriId == 'juri_3' || juriId == '3') _juri3Ready = isReady;
      });
    });
  }

  void _startTimer() {
    _isTimerRunning = true;
    _matchTimer?.cancel();
    _matchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        if (_timerSeconds > 0) {
          setState(() => _timerSeconds--);
        } else {
          _isTimerRunning = false;
          _matchTimer?.cancel();
        }
      } else {
        _isTimerRunning = false;
        _matchTimer?.cancel();
      }
    });
  }

  void _pauseTimer() {
    _isTimerRunning = false;
    _matchTimer?.cancel();
  }

  Future<void> _handleBabakSelanjutnya() async {
    final gelanggang = ref.read(activeGelanggangProvider);
    final jadwalDocId = _selectedJadwal?.documentId ?? '';
    final atlitBiruDocId =
        _atlitBiru?.documentId ?? _atlitBiru?.id?.toString() ?? '';
    final atlitMerahDocId =
        _atlitMerah?.documentId ?? _atlitMerah?.id?.toString() ?? '';
    final gelanggangId = gelanggang?.documentId ?? '';

    // 1. Tentukan babak berikutnya (1 -> 2, 2 -> 3, max 3)
    final currentBabakInt = int.tryParse(_activeBabak) ?? 1;
    if (currentBabakInt >= 3) {
      _showSnack('Sudah berada di BABAK 3 (Babak Terakhir)', Colors.orange);
      return;
    }
    final nextBabakInt = currentBabakInt + 1;
    final nextBabakStr = nextBabakInt.toString();

    // 2. Reset timer & indikator kedisiplinan (hanya binaan & teguran).
    //    Peringatan (pembinaan) & histori nilai TIDAK dihapus / di-reset.
    _matchTimer?.cancel();
    setState(() {
      _activeBabak = nextBabakStr;
      if (_selectedJadwal != null) {
        _selectedJadwal = _selectedJadwal!.copyWith(babak: nextBabakStr);
      }
      _isTimerRunning = false;
      _timerSeconds = 120;
      // Reset hanya binaan & teguran — Peringatan (pembinaan) tetap dipertahankan
      _kpBinaanBiru = 0;
      _kpTeguranBiru = 0;
      _kpBinaanMerah = 0;
      _kpTeguranMerah = 0;
    });

    // 3. Emit babak:change ke semua perangkat lain (Monitor, Juri, Timekeeper)
    _socketService.emitBabakChange({
      'gelanggangId': gelanggangId,
      'jadwalId': jadwalDocId,
      'babak': nextBabakStr,
    });

    // 4. Emit timer:control reset agar semua perangkat sync ke awal babak baru
    _socketService.emitTimerControl({
      'action': 'reset',
      'seconds': 120,
      'totalSeconds': 120,
      'gelanggangId': gelanggangId,
      'status': 'standby',
      'atlit1Id': atlitBiruDocId,
      'atlit2Id': atlitMerahDocId,
      'babak': nextBabakStr,
    });

    // 5. Update Strapi Jadwal record — persist babak baru & reset binaan/teguran
    if (jadwalDocId.isNotEmpty) {
      try {
        await _api.updateProtect('jadwals', jadwalDocId, {
          'data': {
            'babak': nextBabakStr,
            'kp_binaan_biru': 0,
            'kp_teguran_biru': 0,
            'kp_binaan_merah': 0,
            'kp_teguran_merah': 0,
          },
        });
      } catch (e) {
        debugPrint('[Dewan] Error persisting babak_selanjutnya to Strapi: $e');
      }
    }

    // 6. Reload nilai dari server setelah Strapi selesai memproses.
    //    Gunakan delay 1.5 detik agar server ada waktu commit perubahan.
    //    Ini memastikan riwayat nilai dan total poin tetap utuh dan tidak terhapus.
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) _fetchNilai();
    });

    _showSnack(
      'Beralih ke BABAK $nextBabakStr! Binaan, Teguran, & Peringatan di-reset.',
      PusakaTheme.indigo500,
    );
  }

  String get _formattedTimer {
    final mins = (_timerSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (_timerSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  Future<void> _fetchPeserta(String docId, int dst) async {
    if (docId.isEmpty) return;
    try {
      final response = await _api.findOneProtect('pesertas', docId);
      final data = response['data'];
      if (data is Map<String, dynamic> && mounted) {
        setState(() {
          if (dst == 1) {
            _atlitBiru = Peserta.fromJson(data);
          } else {
            _atlitMerah = Peserta.fromJson(data);
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching peserta operator: $e');
    }
  }

  bool _isDsqDialogOpen = false;

  void _showDsqDialog(String sudut, String nama) {
    if (_isDsqDialogOpen) return;
    _isDsqDialogOpen = true;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PusakaTheme.slate950,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: PusakaTheme.rose600, width: 2),
        ),
        title: Row(
          children: const [
            Icon(Icons.gavel, color: PusakaTheme.rose500, size: 28),
            SizedBox(width: 10),
            Text(
              'DISKUALIFIKASI (DSQ)!',
              style: TextStyle(
                color: PusakaTheme.rose400,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Text(
          'Peserta $sudut $nama telah mencapai batas sanksi dan terkena DISKUALIFIKASI oleh Dewan Pertandingan.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              _isDsqDialogOpen = false;
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: PusakaTheme.rose600,
            ),
            child: const Text(
              'Tutup',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ).then((_) => _isDsqDialogOpen = false);
  }

  void _applyJadwalSelection(Jadwal j) {
    final bId =
        j.biruPeserta?.documentId ?? j.biruPeserta?.id?.toString() ?? '';
    final mId =
        j.merahPeserta?.documentId ?? j.merahPeserta?.id?.toString() ?? '';

    // Clear previous score state
    ref.read(nilaiListProvider.notifier).clear();

    setState(() {
      _selectedJadwal = j;
      _activeBabak = (j.babak != null && j.babak!.isNotEmpty) ? j.babak! : '1';
      _atlitBiru = j.biruPeserta; // Sudut Biru (Left)
      _atlitMerah = j.merahPeserta; // Sudut Merah (Right)

      // Sync initial KP state from jadwal
      _kpBinaanMerah = j.kpBinaanMerah;
      _kpTeguranMerah = j.kpTeguranMerah;
      _kpPembinaanMerah = j.kpPembinaanMerah;

      _kpBinaanBiru = j.kpBinaanBiru;
      _kpTeguranBiru = j.kpTeguranBiru;
      _kpPembinaanBiru = j.kpPembinaanBiru;

      // Reset Juri ready indicators for new match
      _juri1Ready = false;
      _juri2Ready = false;
      _juri3Ready = false;
    });

    _fetchNilai();

    // Update gelanggang state so Monitor & Juri screens sync the new athletes immediately
    _updateGelanggang('standby', bId, mId);
  }

  /// Change active round / babak and notify all devices (Monitor, Juri, Strapi)
  Future<void> _handleBabakSelect(String babak) async {
    setState(() {
      _activeBabak = babak;
      if (_selectedJadwal != null) {
        _selectedJadwal = _selectedJadwal!.copyWith(babak: babak);
      }
    });

    final gelanggang = ref.read(activeGelanggangProvider);
    final payload = {
      'gelanggangId': gelanggang?.documentId ?? '',
      'jadwalId': _selectedJadwal?.documentId ?? '',
      'babak': babak,
    };

    _socketService.emitBabakChange(payload);

    if (_selectedJadwal?.documentId != null &&
        _selectedJadwal!.documentId!.isNotEmpty) {
      try {
        await _api.updateProtect('jadwals', _selectedJadwal!.documentId!, {
          'data': {'babak': babak},
        });
      } catch (e) {
        debugPrint('[Dewan] Error updating babak to Strapi: $e');
      }
    }

    _showSnack('Babak $babak Diaktifkan!', const Color(0xFFD97706));
  }

  Future<bool> _updateGelanggang(
    String status,
    String at1Id,
    String at2Id,
  ) async {
    final gelanggang = ref.read(activeGelanggangProvider);

    try {
      await _api.updateProtect('gelanggangs', gelanggang!.documentId!, {
        'data': {
          'status_tanding': status,
          'atlit_1_id': at1Id, // Atlit 1 = Sudut Biru
          'atlit_2_id': at2Id, // Atlit 2 = Sudut Merah
        },
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _handleMulai() async {
    final biruId = _atlitBiru?.documentId ?? _atlitBiru?.id?.toString();
    final merahId = _atlitMerah?.documentId ?? _atlitMerah?.id?.toString();

    if (biruId == null || merahId == null) {
      _showSnack(
        'Pilih partai tanding atau peserta terlebih dahulu.',
        PusakaTheme.amber500,
      );
      return;
    }

    if (biruId == merahId) {
      _showSnack(
        'Peserta Sudut Biru dan Merah tidak boleh sama.',
        PusakaTheme.amber500,
      );
      return;
    }

    final ok = await _updateGelanggang('berlangsung', biruId, merahId);
    if (ok) {
      setState(() {
        _tandingStatus = true;
        if (_timerSeconds <= 0) {
          _timerSeconds = 120;
        }
      });
      _startTimer();
      _socketService.emitTimerControl({
        'action': 'start',
        'seconds': _timerSeconds,
        'gelanggangId': ref.read(activeGelanggangProvider)?.documentId,
        'babak': _activeBabak,
      });
      _showSnack(
        'Pertandingan Dimulai! Partai #${_selectedJadwal?.nomorPartai ?? '-'}',
        PusakaTheme.emerald600,
      );
    } else {
      _showSnack('Gagal memperbarui status gelanggang.', PusakaTheme.rose600);
    }
  }

  /// Batalkan hitung mundur atau suara buzzer.
  Future<void> _cancelBuzzer() async {
    _buzzerTimer?.cancel();
    _buzzerSoundTimer?.cancel();
    try {
      await _buzzerPlayer.stop();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _buzzerCountdown = 0;
        _isBuzzerSounding = false;
      });
      _showSnack('Hitung mundur buzzer dibatalkan', PusakaTheme.amber500);
    }
  }

  /// Hitung mundur 5 detik, lalu bunyikan suara buzzer.
  /// Jika diklik lagi saat sedang hitung mundur/berbunyi, aksi akan dibatalkan.
  Future<void> _handleBuzzer() async {
    if (_isBuzzerActive) {
      await _cancelBuzzer();
      return;
    }

    _buzzerTimer?.cancel();
    _buzzerSoundTimer?.cancel();

    setState(() {
      _buzzerCountdown = 5;
      _isBuzzerSounding = false;
    });

    _buzzerTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_buzzerCountdown > 1) {
        setState(() {
          _buzzerCountdown--;
        });
      } else {
        timer.cancel();
        // Hitung mundur selesai (0s) -> Bunyikan audio buzzer
        setState(() {
          _buzzerCountdown = 0;
          _isBuzzerSounding = true;
        });

        try {
          await _buzzerPlayer.stop();
          await _buzzerPlayer.setSource(AssetSource('audio/buzzer.wav'));
          await _buzzerPlayer.setVolume(1.0);
          await _buzzerPlayer.resume();
        } catch (e) {
          debugPrint('[Dewan] Error playing buzzer: $e');
        }

        // Hentikan suara setelah 4 detik & reset state
        _buzzerSoundTimer?.cancel();
        _buzzerSoundTimer = Timer(const Duration(seconds: 4), () async {
          if (mounted) {
            try {
              await _buzzerPlayer.stop();
            } catch (_) {}
            setState(() {
              _isBuzzerSounding = false;
            });
          }
        });
      }
    });
  }

  Future<void> _handleStop() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PusakaTheme.slate900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Selesai Tanding?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Apakah Anda yakin ingin menyelesaikan pertandingan partai ini?',
          style: TextStyle(color: PusakaTheme.slate400),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Batal',
              style: TextStyle(color: PusakaTheme.slate400),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: PusakaTheme.rose600,
            ),
            child: const Text('Ya, Selesaikan'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final biruId = _atlitBiru?.documentId ?? _atlitBiru?.id?.toString() ?? '';
      final merahId =
          _atlitMerah?.documentId ?? _atlitMerah?.id?.toString() ?? '';

      // 1. Update gelanggang status to 'standby' in Strapi (valid enum: standby, berlangsung, tutup)
      await _updateGelanggang('standby', biruId, merahId);

      // 2. If a specific jadwal match is active, update jadwal status to 'selesai' in Strapi
      if (_selectedJadwal?.documentId != null &&
          _selectedJadwal!.documentId!.isNotEmpty) {
        try {
          await _api.updateProtect('jadwals', _selectedJadwal!.documentId!, {
            'data': {'status_tanding': 'selesai'},
          });
        } catch (e) {
          debugPrint('[Dewan] Error updating jadwal status: $e');
        }
      }

      // 3. Update local state & stop timer
      setState(() {
        _tandingStatus = false;
        _pauseTimer();
      });

      // 4. Emit timer:control stop event so Monitor & Juri screens trigger instantly
      final gelanggangId = ref.read(activeGelanggangProvider)?.documentId ?? '';
      _socketService.emitTimerControl({
        'action': 'stop',
        'seconds': _timerSeconds,
        'gelanggangId': gelanggangId,
        'status': 'selesai',
        'atlit1Id': biruId,
        'atlit2Id': merahId,
      });

      _showSnack(
        'Pertandingan Selesai! Pemenang Ditampilkan di Layar Monitor.',
        PusakaTheme.emerald600,
      );
    }
  }

  /// Emit KP Action via Socket.IO AND Persist Directly to Strapi Database
  DateTime? _lastKpActionTime;

  /// Emit KP Action via Socket.IO & Optimistically Update State
  Future<void> _handleKpAction(
    String aksi,
    Peserta? atlit,
    bool isRed, {
    int point = 0,
    String? label,
  }) async {
    if (!_tandingStatus) {
      _showSnack(
        'Pertandingan belum dimulai! Klik MULAI terlebih dahulu.',
        PusakaTheme.amber500,
      );
      return;
    }

    final now = DateTime.now();
    if (_lastKpActionTime != null &&
        now.difference(_lastKpActionTime!).inMilliseconds < 200) {
      debugPrint('[Dewan] Ignored duplicate rapid tap on KP action: $aksi');
      return;
    }
    _lastKpActionTime = now;

    final atlitDocId = atlit?.documentId ?? atlit?.id?.toString();
    if (atlitDocId == null || atlitDocId.isEmpty) {
      _showSnack(
        'Data atlet sudut ${isRed ? "MERAH" : "BIRU"} belum lengkap.',
        PusakaTheme.amber500,
      );
      return;
    }
    final gelanggang = ref.read(activeGelanggangProvider);
    final jadwalDocId = _selectedJadwal?.documentId ?? '';

    // 1. Optimistic local state update so tablet UI responds immediately
    // NOTE: We do NOT call emitKpAction here because scoringEngine on Strapi
    // would create a duplicate DB record. Persistence is done via REST below,
    // and emitNilaiKp is used to broadcast the confirmed record to other screens.
    final localNilai = Nilai(
      id: DateTime.now().millisecondsSinceEpoch,
      peserta: atlit,
      jumlah: point,
      jenis: aksi,
      status: 'sah',
      sudut: isRed ? 'merah' : 'biru',
      juriId: 'KP',
      juriCount: 1,
      menitKe: _formattedTimer,
      createdAt: DateTime.now(),
    );
    ref.read(nilaiListProvider.notifier).addFromSocket(localNilai);

    // Optimistically update sanction counters
    setState(() {
      if (aksi == 'binaan') {
        if (isRed) {
          _kpBinaanMerah = (_kpBinaanMerah + 1).clamp(0, 2);
        } else {
          _kpBinaanBiru = (_kpBinaanBiru + 1).clamp(0, 2);
        }
      } else if (aksi == 'batal_binaan') {
        if (isRed) {
          _kpBinaanMerah = (_kpBinaanMerah - 1).clamp(0, 2);
        } else {
          _kpBinaanBiru = (_kpBinaanBiru - 1).clamp(0, 2);
        }
      } else if (aksi == 'teguran') {
        final count = point == -2 ? 2 : 1;
        if (isRed) {
          _kpTeguranMerah = count;
        } else {
          _kpTeguranBiru = count;
        }
      } else if (aksi == 'batal_teguran') {
        final count = point == 2 ? 1 : 0;
        if (isRed) {
          _kpTeguranMerah = count;
        } else {
          _kpTeguranBiru = count;
        }
      } else if (aksi == 'pembinaan') {
        final count = point == -10 ? 2 : 1;
        if (isRed) {
          _kpPembinaanMerah = count;
        } else {
          _kpPembinaanBiru = count;
        }
      } else if (aksi == 'batal_pembinaan') {
        final count = point == 10 ? 1 : 0;
        if (isRed) {
          _kpPembinaanMerah = count;
        } else {
          _kpPembinaanBiru = count;
        }
      } else if (aksi == 'reset_babak') {
        if (isRed) {
          _kpBinaanMerah = 0;
          _kpTeguranMerah = 0;
          _kpPembinaanMerah = 0;
        } else {
          _kpBinaanBiru = 0;
          _kpTeguranBiru = 0;
          _kpPembinaanBiru = 0;
        }
      }
    });

    _showSnack(
      '${label ?? aksi.toUpperCase()} sudut ${isRed ? "MERAH" : "BIRU"} dicatat',
      PusakaTheme.indigo500,
    );

    // 3. Persist to Strapi: cancellation actions, point-bearing actions, AND binaan/batal_binaan
    // NOTE: binaan has point=0 but still needs to be saved and broadcast!
    final isBinaanAction = aksi == 'binaan' || aksi == 'batal_binaan';
    if (aksi.startsWith('batal_') || point != 0 || isBinaanAction) {
      try {
        final strapiJenis = (aksi == 'batal_jatuhan' || aksi == 'jatuhan')
            ? 'jatuhan'
            : (aksi == 'batal_teguran' || aksi == 'teguran')
            ? 'teguran'
            : (aksi == 'batal_pembinaan' || aksi == 'pembinaan')
            ? 'pembinaan'
            : (aksi == 'batal_binaan' || aksi == 'binaan')
            ? 'binaan'
            : aksi;

        final res = await _api.createProtect('nilais', {
          'data': {
            'jumlah': point,
            'peserta': atlitDocId,
            'menit_ke': _formattedTimer,
            'status': 'sah',
            'jenis': strapiJenis, // Valid enum on Strapi schema
            'sudut': isRed ? 'merah' : 'biru',
            'juri_id': 'KP',
            'juri_count': 1,
            'babak': (_selectedJadwal?.babak ?? '1').toString(),
            if (jadwalDocId.isNotEmpty) 'jadwal': jadwalDocId,
          },
        });
        if (res['data'] != null && res['data'] is Map) {
          final serverData = Map<String, dynamic>.from(res['data'] as Map);
          // NOTE: We do NOT call addFromSocket here again because the local state
          // was already updated optimistically above. We only broadcast to other
          // screens (Monitor & Juri) via emitNilaiKp.
          final gelanggangBroadcast = ref.read(activeGelanggangProvider);
          _socketService.emitNilaiKp({
            'gelanggangId': gelanggangBroadcast?.documentId ?? '',
            'documentId': serverData['documentId'],
            'id': serverData['id'],
            'jumlah': point,
            'peserta': atlitDocId,
            'menit_ke': _formattedTimer,
            'status': 'sah',
            'jenis': aksi,
            'sudut': isRed ? 'merah' : 'biru',
            'juri_id': 'KP',
            'juri_count': 1,
            'babak': (_selectedJadwal?.babak ?? '1').toString(),
            'createdAt': DateTime.now().toIso8601String(),
          });
        }
      } catch (e) {
        debugPrint('[Dewan] Error persisting $aksi to Strapi: $e');
      }
    }

    // 4. For 'diskualifikasi':
    // Disqualification immediately ends the match and declares the opponent the winner!
    if (aksi == 'diskualifikasi') {
      final biruId = _atlitBiru?.documentId ?? _atlitBiru?.id?.toString() ?? '';
      final merahId =
          _atlitMerah?.documentId ?? _atlitMerah?.id?.toString() ?? '';
      final gelanggangId = gelanggang?.documentId ?? '';

      setState(() {
        _tandingStatus = false;
        _pauseTimer();
      });

      _updateGelanggang('standby', biruId, merahId);

      _socketService.emitTimerControl({
        'action': 'stop',
        'seconds': _timerSeconds,
        'gelanggangId': gelanggangId,
        'status': 'selesai',
        'atlit1Id': biruId,
        'atlit2Id': merahId,
        'dsqSudut': isRed ? 'merah' : 'biru',
        'dsqNama': atlit?.namaLengkap ?? '',
      });

      _socketService.emitPertandinganSelesai({
        'gelanggangId': gelanggangId,
        'jadwalId': jadwalDocId,
        'pemenang': isRed ? 'biru' : 'merah',
        'kemenangan': 'diskualifikasi',
        'dsqSudut': isRed ? 'merah' : 'biru',
        'dsqNama': atlit?.namaLengkap ?? '',
      });
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ── DEWAN VERIFICATION WORKFLOW (JATUHAN & PELANGGARAN) ──
  // ══════════════════════════════════════════════════════════════════════════
  void _startVerifikasi(String jenis) {
    if (!_tandingStatus) {
      _showSnack(
        'Pertandingan belum dimulai! Klik MULAI terlebih dahulu.',
        PusakaTheme.amber500,
      );
      return;
    }
    final isPelanggaran = jenis.toLowerCase() == 'pelanggaran';
    debugPrint('[Dewan] _startVerifikasi ($jenis) triggered');
    final gelanggang = ref.read(activeGelanggangProvider);
    final jadwalDocId = _selectedJadwal?.documentId ?? '';

    final bId =
        _atlitBiru?.documentId ??
        _atlitBiru?.id?.toString() ??
        _selectedJadwal?.biruPeserta?.documentId ??
        gelanggang?.atlit1Id ??
        '';
    final mId =
        _atlitMerah?.documentId ??
        _atlitMerah?.id?.toString() ??
        _selectedJadwal?.merahPeserta?.documentId ??
        gelanggang?.atlit2Id ??
        '';

    setState(() {
      _verifikasiActive = true;
      _verifikasiJenis = jenis;
      _verifikasiVotes['juri_1'] = null;
      _verifikasiVotes['juri_2'] = null;
      _verifikasiVotes['juri_3'] = null;
      _verifikasiHasil = null;
    });

    final payload = {
      'gelanggangId': gelanggang?.documentId ?? '',
      'jadwalId': jadwalDocId,
      'jenis': jenis,
      'judul': isPelanggaran ? 'VERIFIKASI PELANGGARAN' : 'VERIFIKASI JATUHAN',
      'atlitBiru': {
        'documentId': bId,
        'nama':
            _atlitBiru?.namaLengkap ??
            _selectedJadwal?.biruPeserta?.namaLengkap ??
            'Sudut Biru',
        'kontingen':
            _atlitBiru?.kontingen ??
            _selectedJadwal?.biruPeserta?.kontingen ??
            '-',
      },
      'atlitMerah': {
        'documentId': mId,
        'nama':
            _atlitMerah?.namaLengkap ??
            _selectedJadwal?.merahPeserta?.namaLengkap ??
            'Sudut Merah',
        'kontingen':
            _atlitMerah?.kontingen ??
            _selectedJadwal?.merahPeserta?.kontingen ??
            '-',
      },
      'babak': _selectedJadwal?.babak ?? '1',
      'menit_ke': _formattedTimer,
    };

    _socketService.emitVerifikasiMulai(payload);
    _showDewanVerifikasiDialog();
  }

  void _startVerifikasiJatuhan() => _startVerifikasi('jatuhan');
  void _startVerifikasiPelanggaran() => _startVerifikasi('pelanggaran');

  void _evaluasiKonsensusVerifikasi() {
    if (!_verifikasiActive || _verifikasiHasil != null) return;

    final votes = _verifikasiVotes.values.where((v) => v != null).toList();
    final countBiru = votes.where((v) => v == 'biru').length;
    final countMerah = votes.where((v) => v == 'merah').length;
    final countInvalid = votes.where((v) => v == 'invalid').length;

    String? keputusan;
    if (countBiru >= 2) {
      keputusan = 'biru';
    } else if (countMerah >= 2) {
      keputusan = 'merah';
    } else if (countInvalid >= 2) {
      keputusan = 'invalid';
    } else if (votes.length == 3) {
      keputusan = 'invalid';
    }

    if (keputusan != null) {
      setState(() => _verifikasiHasil = keputusan);
      _dialogSetState?.call(() {});

      final gelanggang = ref.read(activeGelanggangProvider);

      // Emit completed verification event to Monitoring & Juri screens so they display verdict immediately (tanpa menutup popup)
      _socketService.emitVerifikasiSelesai({
        'gelanggangId': gelanggang?.documentId ?? '',
        'action': 'hasil',
        'jenis': _verifikasiJenis,
        'hasil': keputusan,
        'keterangan': keputusan == 'invalid'
            ? 'Jatuhan Tidak Sah'
            : 'Jatuhan Sah Sudut ${keputusan.toUpperCase()}',
        'votes': Map<String, dynamic>.from(_verifikasiVotes),
      });

      // Dewan popup stays open so Dewan can review and click Selesai/Tutup
    }
  }

  void _showDewanVerifikasiDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            _dialogSetState = setModalState;

            final v1 = _verifikasiVotes['juri_1'];
            final v2 = _verifikasiVotes['juri_2'];
            final v3 = _verifikasiVotes['juri_3'];
            final votesCount = [v1, v2, v3].where((v) => v != null).length;

            return Dialog(
              backgroundColor: const Color(0xFF090D16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFF0284C7), width: 2.0),
              ),
              child: Container(
                width: 680,
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
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: (_verifikasiJenis == 'pelanggaran'
                                        ? const Color(0xFFD97706)
                                        : const Color(0xFF0369A1))
                                    .withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                _verifikasiJenis == 'pelanggaran'
                                    ? Icons.gavel_rounded
                                    : Icons.verified_user_rounded,
                                color: _verifikasiJenis == 'pelanggaran'
                                    ? const Color(0xFFFBBF24)
                                    : const Color(0xFF38BDF8),
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _verifikasiJenis == 'pelanggaran'
                                      ? 'VERIFIKASI PELANGGARAN'
                                      : 'VERIFIKASI JATUHAN',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  _verifikasiJenis == 'pelanggaran'
                                      ? 'Menunggu input verifikasi pelanggaran dari 3 Juri Pertandingan'
                                      : 'Menunggu input verifikasi jatuhan dari 3 Juri Pertandingan',
                                  style: const TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: (_verifikasiJenis == 'pelanggaran'
                                    ? const Color(0xFFD97706)
                                    : const Color(0xFF0369A1))
                                .withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _verifikasiJenis == 'pelanggaran'
                                  ? const Color(0xFFFBBF24).withValues(alpha: 0.5)
                                  : const Color(0xFF38BDF8).withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            '$votesCount / 3 JURI MERESPON',
                            style: TextStyle(
                              color: _verifikasiJenis == 'pelanggaran'
                                  ? const Color(0xFFFBBF24)
                                  : const Color(0xFF38BDF8),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),
                    const Divider(color: Color(0xFF1E293B), height: 1),
                    const SizedBox(height: 18),

                    // 3 Juri Live Vote Cards
                    Row(
                      children: [
                        Expanded(child: _buildJuriVoteCard('JURI 1', v1)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildJuriVoteCard('JURI 2', v2)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildJuriVoteCard('JURI 3', v3)),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Verdict Banner or Waiting Banner
                    if (_verifikasiHasil != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 18,
                        ),
                        decoration: BoxDecoration(
                          color: _verifikasiHasil == 'biru'
                              ? const Color(0xFF0284C7).withValues(alpha: 0.45)
                              : _verifikasiHasil == 'merah'
                              ? const Color(0xFFE11D48).withValues(alpha: 0.45)
                              : const Color(0xFF1E293B).withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _verifikasiHasil == 'biru'
                                ? const Color(0xFF38BDF8)
                                : _verifikasiHasil == 'merah'
                                ? const Color(0xFFFB7185)
                                : const Color(0xFF94A3B8),
                            width: 2.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _verifikasiHasil == 'biru'
                                  ? const Color(
                                      0xFF0284C7,
                                    ).withValues(alpha: 0.4)
                                  : _verifikasiHasil == 'merah'
                                  ? const Color(
                                      0xFFE11D48,
                                    ).withValues(alpha: 0.4)
                                  : Colors.black.withValues(alpha: 0.3),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _verifikasiHasil == 'invalid'
                                  ? Icons.cancel_outlined
                                  : Icons.check_circle_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _verifikasiHasil == 'invalid'
                                  ? (_verifikasiJenis == 'pelanggaran'
                                      ? 'TIDAK ADA PELANGGARAN'
                                      : 'JATUHAN TIDAK SAH')
                                  : (_verifikasiJenis == 'pelanggaran'
                                      ? 'PELANGGARAN SUDUT ${_verifikasiHasil!.toUpperCase()}'
                                      : 'JATUHAN SAH SUDUT ${_verifikasiHasil!.toUpperCase()}'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Selesai / Tutup Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final gelanggang = ref.read(
                              activeGelanggangProvider,
                            );
                            final labelVer = _verifikasiHasil == 'invalid'
                                ? (_verifikasiJenis == 'pelanggaran'
                                    ? 'Tidak Ada Pelanggaran'
                                    : 'Jatuhan Tidak Sah')
                                : (_verifikasiJenis == 'pelanggaran'
                                    ? 'Pelanggaran Sudut ${_verifikasiHasil!.toUpperCase()}'
                                    : 'Jatuhan Sah Sudut ${_verifikasiHasil!.toUpperCase()}');

                            _socketService.emitVerifikasiSelesai({
                              'gelanggangId': gelanggang?.documentId ?? '',
                              'action': 'tutup',
                              'jenis': _verifikasiJenis,
                              'hasil': _verifikasiHasil,
                              'keterangan': labelVer,
                              'votes': Map<String, dynamic>.from(
                                _verifikasiVotes,
                              ),
                            });

                            setState(() => _verifikasiActive = false);
                            Navigator.pop(ctx);
                          },
                          icon: const Icon(
                            Icons.check_circle_outline,
                            color: Colors.white,
                            size: 20,
                          ),
                          label: const Text(
                            'SELESAI / TUTUP HASIL VERIFIKASI',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _verifikasiHasil == 'biru'
                                ? const Color(0xFF0284C7)
                                : _verifikasiHasil == 'merah'
                                ? const Color(0xFFE11D48)
                                : const Color(0xFF334155),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: _verifikasiHasil == 'biru'
                                    ? const Color(0xFF38BDF8)
                                    : _verifikasiHasil == 'merah'
                                    ? const Color(0xFFFB7185)
                                    : const Color(0xFF94A3B8),
                                width: 1.5,
                              ),
                            ),
                            elevation: 4,
                          ),
                        ),
                      ),
                    ] else ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF1E293B)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF38BDF8),
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Menunggu keputusan 2 dari 3 Juri...',
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Manual Fallback / Cancel
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              setState(() => _verifikasiActive = false);
                              _socketService.emitVerifikasiSelesai({
                                'gelanggangId':
                                    ref
                                        .read(activeGelanggangProvider)
                                        ?.documentId ??
                                    '',
                                'action': 'tutup',
                                'hasil': 'dibatalkan',
                                'keterangan':
                                    'Verifikasi dibatalkan oleh Dewan',
                              });
                              Navigator.pop(ctx);
                            },
                            icon: const Icon(
                              Icons.close,
                              color: Color(0xFF94A3B8),
                              size: 16,
                            ),
                            label: const Text(
                              'Batalkan Verifikasi',
                              style: TextStyle(color: Color(0xFF94A3B8)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildJuriVoteCard(String juriLabel, String? vote) {
    Color cardBg;
    Color borderCol;
    Color textCol;
    String statusLabel;
    IconData statusIcon;
    final isPelanggaran = _verifikasiJenis.toLowerCase() == 'pelanggaran';

    if (vote == 'biru') {
      cardBg = const Color(0xFF0369A1).withValues(alpha: 0.35);
      borderCol = const Color(0xFF38BDF8);
      textCol = const Color(0xFF38BDF8);
      statusLabel = isPelanggaran ? 'PELANGGARAN BIRU' : 'JATUHAN BIRU';
      statusIcon = isPelanggaran ? Icons.gavel_rounded : Icons.sports_martial_arts;
    } else if (vote == 'merah') {
      cardBg = const Color(0xFF9F1239).withValues(alpha: 0.35);
      borderCol = const Color(0xFFFB7185);
      textCol = const Color(0xFFFB7185);
      statusLabel = isPelanggaran ? 'PELANGGARAN MERAH' : 'JATUHAN MERAH';
      statusIcon = isPelanggaran ? Icons.gavel_rounded : Icons.sports_martial_arts;
    } else if (vote == 'invalid') {
      cardBg = const Color(0xFFD97706).withValues(alpha: 0.25);
      borderCol = const Color(0xFFF59E0B);
      textCol = const Color(0xFFFBBF24);
      statusLabel = isPelanggaran ? 'TIDAK ADA PELANGGARAN' : 'INVALID (TIDAK SAH)';
      statusIcon = Icons.cancel_outlined;
    } else {
      cardBg = const Color(0xFF0F172A);
      borderCol = const Color(0xFF1E293B);
      textCol = const Color(0xFF64748B);
      statusLabel = 'MENUNGGU...';
      statusIcon = Icons.hourglass_top_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderCol, width: 1.5),
      ),
      child: Column(
        children: [
          Text(
            juriLabel,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Icon(statusIcon, color: textCol, size: 26),
          const SizedBox(height: 6),
          Text(
            statusLabel,
            style: TextStyle(
              color: textCol,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Open comprehensive match selector dialog (Live connected to Riverpod)
  void _showPartaiPickerDialog() {
    int activeFilterIndex = 0; // 0 = Semua, 1 = Belum Bertanding, 2 = Sudah Bertanding

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: const Color(0xFF090D16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF4338CA), width: 1.8),
            ),
            child: Container(
              width: 820,
              height: 560,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Dialog Header with Title, Refresh & Close
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4338CA).withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.format_list_numbered_rounded,
                              color: Color(0xFF818CF8),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'DAFTAR PARTAI PERTANDINGAN',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                'Pilih partai tanding untuk memuat data atlet sudut biru dan merah',
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Consumer(
                            builder: (context, ref, _) {
                              return IconButton(
                                tooltip: 'Muat Ulang Jadwal',
                                icon: const Icon(
                                  Icons.refresh,
                                  color: Color(0xFF818CF8),
                                ),
                                onPressed: () {
                                  final g = ref.read(activeGelanggangProvider);
                                  if (g != null) {
                                    ref
                                        .read(jadwalListProvider.notifier)
                                        .fetchJadwal(g);
                                  }
                                },
                              );
                            },
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close, color: Colors.white70),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),
                  const Divider(color: Color(0xFF1E293B), height: 1),
                  const SizedBox(height: 10),

                  // 2. Interactive Filter Bar (Semua, Belum Bertanding, Sudah Bertanding)
                  Consumer(
                    builder: (context, ref, _) {
                      final jadwalState = ref.watch(jadwalListProvider);
                      final allList = jadwalState.value ?? [];

                      int totalCount = allList.length;
                      int selesaiCount = allList.where((j) =>
                          j.status == 'selesai' ||
                          j.statusTanding == 'selesai' ||
                          j.pemenang != null).length;
                      int belumCount = totalCount - selesaiCount;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            _buildFilterTabChip(
                              label: 'Semua Partai ($totalCount)',
                              icon: Icons.format_list_bulleted_rounded,
                              isSelected: activeFilterIndex == 0,
                              badgeColor: const Color(0xFF6366F1),
                              onTap: () => setDialogState(() => activeFilterIndex = 0),
                            ),
                            const SizedBox(width: 8),
                            _buildFilterTabChip(
                              label: 'Belum Bertanding ($belumCount)',
                              icon: Icons.hourglass_top_rounded,
                              isSelected: activeFilterIndex == 1,
                              badgeColor: const Color(0xFF64748B),
                              onTap: () => setDialogState(() => activeFilterIndex = 1),
                            ),
                            const SizedBox(width: 8),
                            _buildFilterTabChip(
                              label: 'Sudah Bertanding ($selesaiCount)',
                              icon: Icons.check_circle_rounded,
                              isSelected: activeFilterIndex == 2,
                              badgeColor: const Color(0xFF10B981),
                              onTap: () => setDialogState(() => activeFilterIndex = 2),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  // 3. Match List View connected to Riverpod
                  Expanded(
                    child: Consumer(
                      builder: (context, ref, _) {
                        final jadwalState = ref.watch(jadwalListProvider);

                        return jadwalState.when(
                          data: (allList) {
                            if (allList.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.event_busy,
                                      color: Color(0xFF64748B),
                                      size: 48,
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Belum ada jadwal partai di arena ini',
                                      style: TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        final g = ref.read(
                                          activeGelanggangProvider,
                                        );
                                        if (g != null) {
                                          ref
                                              .read(jadwalListProvider.notifier)
                                              .fetchJadwal(g);
                                        }
                                      },
                                      icon: const Icon(Icons.refresh, size: 16),
                                      label: const Text('Muat Ulang Jadwal'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF4F46E5),
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            final displayList = allList.where((j) {
                              final isSelesai = j.status == 'selesai' ||
                                  j.statusTanding == 'selesai' ||
                                  j.pemenang != null;
                              if (activeFilterIndex == 1) return !isSelesai;
                              if (activeFilterIndex == 2) return isSelesai;
                              return true;
                            }).toList();

                            if (displayList.isEmpty) {
                              return Center(
                                child: Text(
                                  activeFilterIndex == 1
                                      ? 'Tidak ada partai yang belum bertanding'
                                      : 'Belum ada partai yang selesai bertanding',
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            }

                            return ListView.separated(
                              itemCount: displayList.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, idx) {
                                final j = displayList[idx];
                                final isSelected =
                                    _selectedJadwal?.documentId == j.documentId ||
                                    (_selectedJadwal?.id != null &&
                                        _selectedJadwal?.id == j.id);
                                final isSelesai = j.status == 'selesai' ||
                                    j.statusTanding == 'selesai' ||
                                    j.pemenang != null;

                                return InkWell(
                                  onTap: () {
                                    _applyJadwalSelection(j);
                                    Navigator.pop(ctx);
                                    _showSnack(
                                      'Memilih Partai #${j.nomorPartai ?? '-'}',
                                      PusakaTheme.indigo500,
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFF1E1B4B).withValues(alpha: 0.9)
                                          : (isSelesai
                                              ? const Color(0xFF064E3B).withValues(alpha: 0.22)
                                              : const Color(0xFF0F172A)),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFF6366F1)
                                            : (isSelesai
                                                ? const Color(0xFF10B981)
                                                : const Color(0xFF1E293B)),
                                        width: isSelected
                                            ? 2.0
                                            : (isSelesai ? 1.6 : 1.0),
                                      ),
                                      boxShadow: isSelesai
                                          ? [
                                              BoxShadow(
                                                color: const Color(0xFF10B981).withValues(alpha: 0.25),
                                                blurRadius: 8,
                                                spreadRadius: 0.5,
                                              ),
                                            ]
                                          : (isSelected
                                              ? [
                                                  BoxShadow(
                                                    color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                                                    blurRadius: 8,
                                                  ),
                                                ]
                                              : null),
                                    ),
                                    child: Row(
                                      children: [
                                        // Partai Number Badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? const Color(0xFF4F46E5)
                                                : (isSelesai
                                                    ? const Color(0xFF065F46)
                                                    : const Color(0xFF1E293B)),
                                            borderRadius: BorderRadius.circular(8),
                                            border: isSelesai
                                                ? Border.all(
                                                    color: const Color(0xFF34D399),
                                                    width: 1.2,
                                                  )
                                                : null,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    isSelesai
                                                        ? Icons.check_circle_rounded
                                                        : Icons.schedule_rounded,
                                                    color: isSelesai
                                                        ? const Color(0xFF34D399)
                                                        : const Color(0xFF94A3B8),
                                                    size: 11,
                                                  ),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    'PARTAI',
                                                    style: TextStyle(
                                                      color: isSelesai
                                                          ? const Color(0xFFA7F3D0)
                                                          : const Color(0xFFCBD5E1),
                                                      fontSize: 8.5,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              Text(
                                                '#${j.nomorPartai ?? '-'}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        const SizedBox(width: 14),

                                        // Sudut Biru (Left)
                                        Expanded(
                                          flex: 4,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF0369A1).withValues(alpha: 0.18),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: const Color(0xFF0284C7).withValues(alpha: 0.45),
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'SUDUT BIRU',
                                                  style: TextStyle(
                                                    color: Color(0xFF38BDF8),
                                                    fontSize: 8.5,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  j.biruPeserta?.namaLengkap ?? 'Belum Ditentukan',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  j.biruPeserta?.kontingen ?? 'Kontingen -',
                                                  style: const TextStyle(
                                                    color: Color(0xFF7DD3FC),
                                                    fontSize: 10.5,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),

                                        // VS Badge
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 10),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF334155),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              'VS',
                                              style: TextStyle(
                                                color: Colors.amber,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        ),

                                        // Sudut Merah (Right)
                                        Expanded(
                                          flex: 4,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF9F1239).withValues(alpha: 0.18),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: const Color(0xFFE11D48).withValues(alpha: 0.45),
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'SUDUT MERAH',
                                                  style: TextStyle(
                                                    color: Color(0xFFFB7185),
                                                    fontSize: 8.5,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  j.merahPeserta?.namaLengkap ?? 'Belum Ditentukan',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  j.merahPeserta?.kontingen ?? 'Kontingen -',
                                                  style: const TextStyle(
                                                    color: Color(0xFFFDA4AF),
                                                    fontSize: 10.5,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),

                                        const SizedBox(width: 14),

                                        // Status Indicator Badge (Sudah Bertanding / Belum Bertanding)
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 3.5,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isSelesai
                                                    ? const Color(0xFF064E3B)
                                                    : const Color(0xFF1E1B4B),
                                                borderRadius: BorderRadius.circular(6),
                                                border: isSelesai
                                                    ? Border.all(color: const Color(0xFF059669), width: 1)
                                                    : null,
                                              ),
                                              child: Text(
                                                j.kelas?.namaKelas ?? 'Kelas',
                                                style: TextStyle(
                                                  color: isSelesai
                                                      ? const Color(0xFFA7F3D0)
                                                      : const Color(0xFFA5B4FC),
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            if (isSelesai)
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 7,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF065F46),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: const Color(0xFF34D399),
                                                    width: 1,
                                                  ),
                                                ),
                                                child: const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.check_circle_rounded,
                                                      color: Color(0xFF34D399),
                                                      size: 13,
                                                    ),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      'SUDAH BERTANDING',
                                                      style: TextStyle(
                                                        color: Color(0xFF34D399),
                                                        fontSize: 9.0,
                                                        fontWeight: FontWeight.w900,
                                                        letterSpacing: 0.4,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            else
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 7,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF1E293B),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: const Color(0xFF475569),
                                                    width: 1,
                                                  ),
                                                ),
                                                child: const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.hourglass_empty_rounded,
                                                      color: Color(0xFF94A3B8),
                                                      size: 13,
                                                    ),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      'BELUM BERTANDING',
                                                      style: TextStyle(
                                                        color: Color(0xFFCBD5E1),
                                                        fontSize: 9.0,
                                                        fontWeight: FontWeight.w800,
                                                        letterSpacing: 0.4,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                          loading: () => const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: Color(0xFF818CF8)),
                                SizedBox(height: 12),
                                Text(
                                  'Memuat jadwal partai...',
                                  style: TextStyle(color: Color(0xFF94A3B8)),
                                ),
                              ],
                            ),
                          ),
                          error: (err, st) => Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: Color(0xFFEF4444),
                                  size: 40,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Gagal memuat jadwal: $err',
                                  style: const TextStyle(
                                    color: Color(0xFFFCA5A5),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                ElevatedButton(
                                  onPressed: () {
                                    final g = ref.read(activeGelanggangProvider);
                                    if (g != null) {
                                      ref
                                          .read(jadwalListProvider.notifier)
                                          .fetchJadwal(g);
                                    }
                                  },
                                  child: const Text('Coba Lagi'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterTabChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required Color badgeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? badgeColor.withValues(alpha: 0.25)
              : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? badgeColor : const Color(0xFF334155),
            width: isSelected ? 1.6 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? badgeColor : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _fetchNilaiDebounce?.cancel();
    _matchTimer?.cancel();
    _buzzerTimer?.cancel();
    _buzzerSoundTimer?.cancel();
    _buzzerPlayer.dispose();
    _connectionSub?.cancel();
    _gelanggangSub?.cancel();
    _kpStatusSub?.cancel();
    _pesertaDsqSub?.cancel();
    _nilaiSub?.cancel();
    _nilaiKpSub?.cancel();
    _verifikasiVoteSub?.cancel();
    _timerControlSub?.cancel();
    _babakChangedSub?.cancel();
    _juriReadySub?.cancel();
    // Do NOT call _socketService.disconnect() — socket is a shared singleton via Riverpod provider
    // Restore orientation
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _fetchNilai() {
    final bDocId =
        _atlitBiru?.documentId ??
        _selectedJadwal?.biruPeserta?.documentId ??
        '';
    final bAltId =
        _atlitBiru?.id?.toString() ??
        _selectedJadwal?.biruPeserta?.id?.toString() ??
        '';
    final mDocId =
        _atlitMerah?.documentId ??
        _selectedJadwal?.merahPeserta?.documentId ??
        '';
    final mAltId =
        _atlitMerah?.id?.toString() ??
        _selectedJadwal?.merahPeserta?.id?.toString() ??
        '';
    final jDocId = _selectedJadwal?.documentId ?? '';
    final jId = _selectedJadwal?.id?.toString() ?? '';

    if (bDocId.isNotEmpty ||
        mDocId.isNotEmpty ||
        bAltId.isNotEmpty ||
        mAltId.isNotEmpty ||
        jDocId.isNotEmpty ||
        jId.isNotEmpty) {
      ref.read(nilaiListProvider.notifier).fetchNilai(
            bDocId,
            mDocId,
            atlit1AltId: bAltId,
            atlit2AltId: mAltId,
            jadwalDocId: jDocId,
            jadwalId: jId,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final gelanggang = ref.watch(activeGelanggangProvider);
    final jadwalState = ref.watch(jadwalListProvider);
    final allNilai = ref.watch(nilaiListProvider);

    ref.listen<Gelanggang?>(activeGelanggangProvider, (previous, next) {
      if (next != null) {
        ref.read(jadwalListProvider.notifier).fetchJadwal(next);
      }
    });

    final atlitBiruDocId =
        _atlitBiru?.documentId ?? _atlitBiru?.id?.toString() ?? '';
    final atlitMerahDocId =
        _atlitMerah?.documentId ?? _atlitMerah?.id?.toString() ?? '';
    final totalSkorBiru = countNilaiForPeserta(
      allNilai,
      atlitBiruDocId,
      sudut: 'biru',
    );
    final totalSkorMerah = countNilaiForPeserta(
      allNilai,
      atlitMerahDocId,
      sudut: 'merah',
    );

    // Get 5 latest score logs for each athlete
    final historyBiru = recentNilaiForPeserta(
      allNilai,
      atlitBiruDocId,
      limit: 5,
      sudut: 'biru',
    );
    final historyMerah = recentNilaiForPeserta(
      allNilai,
      atlitMerahDocId,
      limit: 5,
      sudut: 'merah',
    );

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF030712), // Obsidian background
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F172A), Color(0xFF020617), Color(0xFF000000)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── 1. Top Header Bar (Info & Arena) ──
              _buildTopHeader(gelanggang),

              // ── 2. Dedicated Top Partai Selector Bar (Interactive when standby, locked when active) ──
              _buildPartaiSelectorBar(jadwalState, gelanggang),

              // ── 3. Main 3-Column Arena Console ──
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. SUDUT BIRU (LEFT)
                      Expanded(
                        flex: 5,
                        child: _buildSudutBiruCard(
                          totalSkorBiru,
                          historyBiru,
                          binaan: _kpBinaanBiru,
                          teguran: _kpTeguranBiru,
                          pembinaan: _kpPembinaanBiru,
                        ),
                      ),

                      const SizedBox(width: 10),

                      // 2. CENTER CONTROLLER (TIMER, MULAI/STOP & DEWAN VERIFIKASI)
                      SizedBox(width: 240, child: _buildCenterControl()),

                      const SizedBox(width: 10),

                      // 3. SUDUT MERAH (RIGHT)
                      Expanded(
                        flex: 5,
                        child: _buildSudutMerahCard(
                          totalSkorMerah,
                          historyMerah,
                          binaan: _kpBinaanMerah,
                          teguran: _kpTeguranMerah,
                          pembinaan: _kpPembinaanMerah,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ── 1. TOP HEADER BAR ──
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildTopHeader(Gelanggang? gelanggang) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF090D16).withValues(alpha: 0.95),
        border: const Border(
          bottom: BorderSide(color: Color(0xFF1E293B), width: 1.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Back button + Event Title & Arena
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pushReplacementNamed('/home'),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: Colors.white70,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'EVENT KEJUARAAN',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    gelanggang?.event?.namaEvent ??
                        'KEJUARAAN NASIONAL PENCAK SILAT 2026',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Center-Right: Arena Badge, Match Status Badge & Connection
          Row(
            children: [
              // Arena Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1B4B).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF4338CA).withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.stadium,
                      color: Color(0xFF818CF8),
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'ARENA ${gelanggang?.keterangan ?? gelanggang?.kodeGelanggang ?? '-'}',
                      style: const TextStyle(
                        color: Color(0xFFC7D2FE),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // Status Tanding Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _tandingStatus
                      ? const Color(0xFF064E3B).withValues(alpha: 0.8)
                      : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _tandingStatus
                        ? const Color(0xFF10B981)
                        : const Color(0xFF475569),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _tandingStatus
                            ? const Color(0xFF34D399)
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _tandingStatus ? 'BERLANGSUNG' : 'STANDBY',
                      style: TextStyle(
                        color: _tandingStatus
                            ? const Color(0xFF34D399)
                            : const Color(0xFFCBD5E1),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // Connection badge
              ConnectionBadge(isConnected: _isConnected),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ── 2. DEDICATED TOP BAR: BABAK SELECTOR & PARTAI SELECTOR ──
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildPartaiSelectorBar(
    AsyncValue<List<Jadwal>> jadwalState,
    Gelanggang? gelanggang,
  ) {
    final isLocked = _tandingStatus; // Locked when match is actively running
    final list = jadwalState.valueOrNull ?? [];

    // Auto-select active match or first match on initial load
    if (_selectedJadwal == null && list.isNotEmpty) {
      final a1 = gelanggang?.atlit1Id;
      final a2 = gelanggang?.atlit2Id;
      final activeMatch = list.where((j) {
        final bId = j.biruPeserta?.documentId ?? j.biruPeserta?.id?.toString();
        final mId =
            j.merahPeserta?.documentId ?? j.merahPeserta?.id?.toString();
        return (bId == a1 && mId == a2) ||
            (bId == a2 && mId == a1) ||
            j.statusTanding == 'berlangsung';
      }).firstOrNull;

      final target = activeMatch ?? list.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedJadwal == null) {
          _applyJadwalSelection(target);
        }
      });
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 4),
      child: Row(
        children: [
          // ── 1. KOTAK PILIH BABAK (BABAK 1, BABAK 2, BABAK 3) ──
          _buildBabakSelectorBox(),

          const SizedBox(width: 8),

          // ── 2. KOTAK STATUS JURI (3 LAMPUS INDIKATOR READY) ──
          _buildJuriIndicatorBox(),

          const SizedBox(width: 8),

          // ── 3. KOTAK PILIH PARTAI TANDING (EXPANDED) ──
          Expanded(child: _buildPartaiSelectorBox(isLocked)),
        ],
      ),
    );
  }

  Widget _buildJuriIndicatorBox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6.5),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.6),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Label
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.how_to_reg_rounded,
                  size: 16,
                  color: Color(0xFF34D399),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'JURI:',
                style: TextStyle(
                  color: Color(0xFF34D399),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),

          // 3 LED Dots for Juri 1, Juri 2, Juri 3
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildJuriDotIndicator('1', _juri1Ready),
              const SizedBox(width: 5),
              _buildJuriDotIndicator('2', _juri2Ready),
              const SizedBox(width: 5),
              _buildJuriDotIndicator('3', _juri3Ready),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildJuriDotIndicator(String label, bool isReady) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: isReady
            ? const Color(0xFF065F46).withValues(alpha: 0.85)
            : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isReady ? const Color(0xFF34D399) : const Color(0xFF334155),
          width: isReady ? 1.5 : 1.0,
        ),
        boxShadow: isReady
            ? [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.5),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Lampu LED titik
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isReady ? const Color(0xFF34D399) : const Color(0xFF64748B),
              boxShadow: isReady
                  ? [
                      const BoxShadow(
                        color: Color(0xFF34D399),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'J$label',
            style: TextStyle(
              color: isReady ? Colors.white : const Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBabakSelectorBox() {
    final currentBabak = _activeBabak;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6.5),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.6),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Label with Martial Arts Icon
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFFD97706).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.sports_martial_arts_rounded,
                  size: 16,
                  color: Color(0xFFFBBF24),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'BABAK:',
                style: TextStyle(
                  color: Color(0xFFFBBF24),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),

          // Segmented 3 Round Buttons: Babak 1, Babak 2, Babak 3
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildBabakButton('1', 'BABAK 1', currentBabak == '1'),
              const SizedBox(width: 5),
              _buildBabakButton('2', 'BABAK 2', currentBabak == '2'),
              const SizedBox(width: 5),
              _buildBabakButton('3', 'BABAK 3', currentBabak == '3'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBabakButton(String babakNum, String label, bool isActive) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _handleBabakSelect(babakNum),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6.5),
          decoration: BoxDecoration(
            gradient: isActive
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                  )
                : null,
            color: isActive ? null : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive
                  ? const Color(0xFFFDE68A)
                  : const Color(0xFF475569),
              width: isActive ? 1.5 : 1.0,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isActive) ...[
                const Icon(
                  Icons.check_circle_rounded,
                  size: 13,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.white : const Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPartaiSelectorBox(bool isLocked) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (isLocked) {
            _showSnack(
              'Pertandingan sedang berlangsung. Selesaikan pertandingan terlebih dahulu untuk mengganti partai.',
              PusakaTheme.amber500,
            );
          } else {
            _showPartaiPickerDialog();
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isLocked
                  ? const Color(0xFF334155)
                  : const Color(0xFF4F46E5).withValues(alpha: 0.7),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: isLocked
                    ? Colors.transparent
                    : const Color(0xFF4F46E5).withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Left Icon & Match Info
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isLocked
                          ? const Color(0xFF1E293B)
                          : const Color(0xFF4338CA).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isLocked
                          ? Icons.lock_rounded
                          : Icons.format_list_numbered_rounded,
                      size: 18,
                      color: isLocked
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF818CF8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            'PILIH PARTAI TANDING',
                            style: TextStyle(
                              color: isLocked
                                  ? const Color(0xFF64748B)
                                  : const Color(0xFF818CF8),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isLocked)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF7F1D1D,
                                ).withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: const Color(
                                    0xFFEF4444,
                                  ).withValues(alpha: 0.5),
                                ),
                              ),
                              child: const Text(
                                'TERKUNCI SAAT TANDING',
                                style: TextStyle(
                                  color: Color(0xFFFCA5A5),
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF065F46,
                                ).withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: const Color(
                                    0xFF10B981,
                                  ).withValues(alpha: 0.5),
                                ),
                              ),
                              child: const Text(
                                'KLIK UNTUK MEMILIH',
                                style: TextStyle(
                                  color: Color(0xFF6EE7B7),
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _selectedJadwal != null
                            ? 'PARTAI #${_selectedJadwal!.nomorPartai ?? '-'} | ${_selectedJadwal!.kelas?.namaKelas ?? 'Kelas'} : B [${_selectedJadwal!.biruPeserta?.namaLengkap ?? 'TBD'}] vs M [${_selectedJadwal!.merahPeserta?.namaLengkap ?? 'TBD'}]'
                            : 'Pilih partai pertandingan untuk arena ini',
                        style: TextStyle(
                          color: isLocked
                              ? const Color(0xFF94A3B8)
                              : Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const Spacer(),

              // Right: Action Indicator Button (Enlarged)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: isLocked
                      ? const Color(0xFF1E293B)
                      : const Color(0xFF4F46E5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      isLocked ? Icons.lock_outline : Icons.touch_app_rounded,
                      color: isLocked ? const Color(0xFF64748B) : Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isLocked ? 'Terkunci' : 'Ganti Partai',
                      style: TextStyle(
                        color: isLocked
                            ? const Color(0xFF64748B)
                            : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ── 3. SUDUT BIRU (LEFT COLUMN - BRIGHT BLUE GRADIENT TO DARK RIGHT) ──
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildSudutBiruCard(
    int totalScore,
    List<Nilai> history, {
    required int binaan,
    required int teguran,
    required int pembinaan,
  }) {
    return Container(
      decoration: BoxDecoration(
        // Bright Blue on left, fading darker towards center/right
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFF0284C7), // Vibrant bright blue (Left)
            Color(0xFF0369A1), // Deep royal blue
            Color(0xFF07274E), // Dark navy
            Color(0xFF051329), // Deep shadow edge (Right)
          ],
          stops: [0.0, 0.35, 0.75, 1.0],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF38BDF8), width: 2.0),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.35),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Large Faint Watermark "BIRU"
          Positioned(
            left: 14,
            top: 4,
            child: Text(
              'BIRU',
              style: TextStyle(
                fontSize: 84,
                fontWeight: FontWeight.w900,
                color: Colors.white.withValues(alpha: 0.12),
                letterSpacing: 6,
              ),
            ),
          ),

          // Content Column
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header: Athlete Info & Large Glowing Score ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Athlete Names
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(
                                  0xFF38BDF8,
                                ).withValues(alpha: 0.7),
                              ),
                            ),
                            child: const Text(
                              'SUDUT BIRU',
                              style: TextStyle(
                                color: Color(0xFF38BDF8),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _atlitBiru?.namaLengkap?.toUpperCase() ??
                                'BELUM ADA ATLET',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _atlitBiru?.kontingen?.toUpperCase() ??
                                'KONTINGEN -',
                            style: const TextStyle(
                              color: Color(0xFFBAE6FD),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    // Big Glowing Blue Score
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF38BDF8),
                          width: 1.8,
                        ),
                      ),
                      child: Text(
                        '$totalScore',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF38BDF8),
                          fontFamily: 'monospace',
                          shadows: [
                            Shadow(color: Color(0xFF38BDF8), blurRadius: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // ── Exact 3x3 Button Grid (Taller aspect ratio for big icons & labels) ──
                Expanded(
                  flex: 3,
                  child: GridView.count(
                    crossAxisCount: 3,
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    childAspectRatio: 1.85,
                    children: [
                      // Row 1
                      _buildActionTile(
                        'Binaan 1',
                        Icons.touch_app_outlined,
                        const Color(0xFF1E293B),
                        binaan >= 1
                            ? null
                            : () => _handleKpAction(
                                'binaan',
                                _atlitBiru,
                                false,
                                point: 0,
                                label: 'Binaan 1',
                              ),
                        isActive: binaan >= 1,
                        activeColor: const Color(0xFF6366F1),
                      ),
                      _buildActionTile(
                        'Binaan 2',
                        Icons.front_hand_outlined,
                        const Color(0xFF1E293B),
                        binaan >= 2
                            ? null
                            : () => _handleKpAction(
                                'binaan',
                                _atlitBiru,
                                false,
                                point: 0,
                                label: 'Binaan 2',
                              ),
                        isActive: binaan >= 2,
                        activeColor: const Color(0xFF6366F1),
                      ),
                      _buildActionTile(
                        'Jatuhan +3',
                        Icons.sports_martial_arts,
                        const Color(0xFF059669),
                        () => _handleKpAction(
                          'jatuhan',
                          _atlitBiru,
                          false,
                          point: 3,
                          label: 'Jatuhan (+3)',
                        ),
                        isFilled: true,
                        textColor: Colors.white,
                      ),

                      // Row 2
                      _buildActionTile(
                        'Teguran 1 (-1)',
                        Icons.looks_one_outlined,
                        const Color(0xFF1E293B),
                        teguran == 0
                            ? () => _handleKpAction(
                                'teguran',
                                _atlitBiru,
                                false,
                                point: -1,
                                label: 'Teguran 1 (-1)',
                              )
                            : teguran >= 1
                            ? () => _handleKpAction(
                                'batal_teguran',
                                _atlitBiru,
                                false,
                                point: 1,
                                label: 'Pelanggaran Dibatalkan (+1)',
                              )
                            : null,
                        isActive: teguran >= 1,
                        activeColor: const Color(0xFFEA580C),
                        badge: '-1',
                        badgeColor: const Color(0xFFFB923C),
                      ),
                      _buildActionTile(
                        'Teguran 2 (-2)',
                        Icons.looks_two_outlined,
                        const Color(0xFF1E293B),
                        teguran == 1
                            ? () => _handleKpAction(
                                'teguran',
                                _atlitBiru,
                                false,
                                point: -2,
                                label: 'Teguran 2 (-2)',
                              )
                            : teguran == 2
                            ? () => _handleKpAction(
                                'batal_teguran',
                                _atlitBiru,
                                false,
                                point: 2,
                                label: 'Pelanggaran Dibatalkan (+2)',
                              )
                            : null,
                        isActive: teguran >= 2,
                        activeColor: const Color(0xFFEA580C),
                        badge: '-2',
                        badgeColor: const Color(0xFFFB923C),
                      ),
                      _buildActionTile(
                        'Jatuhan Batal',
                        Icons.rotate_left,
                        const Color(0xFF78350F),
                        () => _handleKpAction(
                          'batal_jatuhan',
                          _atlitBiru,
                          false,
                          point: -3,
                          label: 'Jatuhan Batal (-3)',
                        ),
                        isFilled: true,
                        textColor: const Color(0xFFFDE68A),
                      ),

                      // Row 3
                      _buildActionTile(
                        'Peringatan 1 (-5)',
                        Icons.gavel,
                        const Color(0xFF1E293B),
                        pembinaan == 0
                            ? () => _handleKpAction(
                                'pembinaan',
                                _atlitBiru,
                                false,
                                point: -5,
                                label: 'Peringatan 1 (-5)',
                              )
                            : pembinaan == 1
                            ? () => _handleKpAction(
                                'batal_pembinaan',
                                _atlitBiru,
                                false,
                                point: 5,
                                label: 'Pelanggaran Dibatalkan (+5)',
                              )
                            : null,
                        isActive: pembinaan >= 1,
                        activeColor: const Color(0xFFE11D48),
                        badge: '-5',
                        badgeColor: const Color(0xFFF43F5E),
                      ),
                      _buildActionTile(
                        'Peringatan 2 (-10)',
                        Icons.warning_amber_rounded,
                        const Color(0xFF1E293B),
                        pembinaan < 2
                            ? () => _handleKpAction(
                                'pembinaan',
                                _atlitBiru,
                                false,
                                point: -10,
                                label: 'Peringatan 2 (-10)',
                              )
                            : pembinaan == 2
                            ? () => _handleKpAction(
                                'batal_pembinaan',
                                _atlitBiru,
                                false,
                                point: 10,
                                label: 'Pelanggaran Dibatalkan (+10)',
                              )
                            : null,
                        isActive: pembinaan >= 2,
                        activeColor: const Color(0xFFE11D48),
                        badge: '-10',
                        badgeColor: const Color(0xFFF43F5E),
                      ),
                      _buildActionTile(
                        'Diskualifikasi',
                        Icons.do_not_disturb_on_total_silence,
                        const Color(0xFF991B1B),
                        () => _handleKpAction(
                          'diskualifikasi',
                          _atlitBiru,
                          false,
                          point: 0,
                          label: 'Diskualifikasi',
                        ),
                        isFilled: true,
                        textColor: Colors.white,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 6),

                // ── Vertical Log Nilai Masuk (Biru - 5 Latest) ──
                Expanded(
                  flex: 2,
                  child: _buildVerticalLogNilaiSection(
                    'LOG NILAI MASUK (BIRU):',
                    history,
                    const Color(0xFF38BDF8),
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
  // ── 4. SUDUT MERAH (RIGHT COLUMN - BRIGHT RED GRADIENT TO DARK LEFT) ──
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildSudutMerahCard(
    int totalScore,
    List<Nilai> history, {
    required int binaan,
    required int teguran,
    required int pembinaan,
  }) {
    return Container(
      decoration: BoxDecoration(
        // Bright Red on right, fading darker towards center/left
        gradient: const LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [
            Color(0xFFE11D48), // Vibrant bright red (Right)
            Color(0xFFBE123C), // Deep crimson
            Color(0xFF4C0519), // Dark burgundy
            Color(0xFF1C0208), // Deep shadow edge (Left)
          ],
          stops: [0.0, 0.35, 0.75, 1.0],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFB7185), width: 2.0),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE11D48).withValues(alpha: 0.35),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Large Faint Watermark "MERAH"
          Positioned(
            right: 14,
            top: 4,
            child: Text(
              'MERAH',
              style: TextStyle(
                fontSize: 84,
                fontWeight: FontWeight.w900,
                color: Colors.white.withValues(alpha: 0.12),
                letterSpacing: 6,
              ),
            ),
          ),

          // Content Column
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header: Large Glowing Score & Athlete Info (Right-aligned) ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Big Glowing Red Score
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFFB7185),
                          width: 1.8,
                        ),
                      ),
                      child: Text(
                        '$totalScore',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFFB7185),
                          fontFamily: 'monospace',
                          shadows: [
                            Shadow(color: Color(0xFFFB7185), blurRadius: 20),
                          ],
                        ),
                      ),
                    ),

                    // Athlete Names (Right-aligned)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(
                                  0xFFFB7185,
                                ).withValues(alpha: 0.7),
                              ),
                            ),
                            child: const Text(
                              'SUDUT MERAH',
                              style: TextStyle(
                                color: Color(0xFFFB7185),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _atlitMerah?.namaLengkap?.toUpperCase() ??
                                'BELUM ADA ATLET',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                          ),
                          Text(
                            _atlitMerah?.kontingen?.toUpperCase() ??
                                'KONTINGEN -',
                            style: const TextStyle(
                              color: Color(0xFFFECDD3),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // ── Exact 3x3 Button Grid (Taller aspect ratio for big icons & labels) ──
                Expanded(
                  flex: 3,
                  child: GridView.count(
                    crossAxisCount: 3,
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    childAspectRatio: 1.85,
                    children: [
                      // Row 1
                      _buildActionTile(
                        'Jatuhan +3',
                        Icons.sports_martial_arts,
                        const Color(0xFF059669),
                        () => _handleKpAction(
                          'jatuhan',
                          _atlitMerah,
                          true,
                          point: 3,
                          label: 'Jatuhan (+3)',
                        ),
                        isFilled: true,
                        textColor: Colors.white,
                      ),
                      _buildActionTile(
                        'Binaan 2',
                        Icons.front_hand_outlined,
                        const Color(0xFF1E293B),
                        binaan >= 2
                            ? null
                            : () => _handleKpAction(
                                'binaan',
                                _atlitMerah,
                                true,
                                point: 0,
                                label: 'Binaan 2',
                              ),
                        isActive: binaan >= 2,
                        activeColor: const Color(0xFF6366F1),
                      ),
                      _buildActionTile(
                        'Binaan 1',
                        Icons.touch_app_outlined,
                        const Color(0xFF1E293B),
                        binaan >= 1
                            ? null
                            : () => _handleKpAction(
                                'binaan',
                                _atlitMerah,
                                true,
                                point: 0,
                                label: 'Binaan 1',
                              ),
                        isActive: binaan >= 1,
                        activeColor: const Color(0xFF6366F1),
                      ),

                      // Row 2
                      _buildActionTile(
                        'Jatuhan Batal',
                        Icons.rotate_left,
                        const Color(0xFF78350F),
                        () => _handleKpAction(
                          'batal_jatuhan',
                          _atlitMerah,
                          true,
                          point: -3,
                          label: 'Jatuhan Batal (-3)',
                        ),
                        isFilled: true,
                        textColor: const Color(0xFFFDE68A),
                      ),
                      _buildActionTile(
                        'Teguran 2 (-2)',
                        Icons.looks_two_outlined,
                        const Color(0xFF1E293B),
                        teguran == 1
                            ? () => _handleKpAction(
                                'teguran',
                                _atlitMerah,
                                true,
                                point: -2,
                                label: 'Teguran 2 (-2)',
                              )
                            : teguran == 2
                            ? () => _handleKpAction(
                                'batal_teguran',
                                _atlitMerah,
                                true,
                                point: 2,
                                label: 'Pelanggaran Dibatalkan (+2)',
                              )
                            : null,
                        isActive: teguran >= 2,
                        activeColor: const Color(0xFFEA580C),
                        badge: '-2',
                        badgeColor: const Color(0xFFFB923C),
                      ),
                      _buildActionTile(
                        'Teguran 1 (-1)',
                        Icons.looks_one_outlined,
                        const Color(0xFF1E293B),
                        teguran == 0
                            ? () => _handleKpAction(
                                'teguran',
                                _atlitMerah,
                                true,
                                point: -1,
                                label: 'Teguran 1 (-1)',
                              )
                            : teguran >= 1
                            ? () => _handleKpAction(
                                'batal_teguran',
                                _atlitMerah,
                                true,
                                point: 1,
                                label: 'Pelanggaran Dibatalkan (+1)',
                              )
                            : null,
                        isActive: teguran >= 1,
                        activeColor: const Color(0xFFEA580C),
                        badge: '-1',
                        badgeColor: const Color(0xFFFB923C),
                      ),

                      // Row 3
                      _buildActionTile(
                        'Diskualifikasi',
                        Icons.do_not_disturb_on_total_silence,
                        const Color(0xFF991B1B),
                        () => _handleKpAction(
                          'diskualifikasi',
                          _atlitMerah,
                          true,
                          point: 0,
                          label: 'Diskualifikasi',
                        ),
                        isFilled: true,
                        textColor: Colors.white,
                      ),
                      _buildActionTile(
                        'Peringatan 2 (-10)',
                        Icons.warning_amber_rounded,
                        const Color(0xFF1E293B),
                        pembinaan < 2
                            ? () => _handleKpAction(
                                'pembinaan',
                                _atlitMerah,
                                true,
                                point: -10,
                                label: 'Peringatan 2 (-10)',
                              )
                            : pembinaan == 2
                            ? () => _handleKpAction(
                                'batal_pembinaan',
                                _atlitMerah,
                                true,
                                point: 10,
                                label: 'Pelanggaran Dibatalkan (+10)',
                              )
                            : null,
                        isActive: pembinaan >= 2,
                        activeColor: const Color(0xFFE11D48),
                        badge: '-10',
                        badgeColor: const Color(0xFFF43F5E),
                      ),
                      _buildActionTile(
                        'Peringatan 1 (-5)',
                        Icons.gavel,
                        const Color(0xFF1E293B),
                        pembinaan == 0
                            ? () => _handleKpAction(
                                'pembinaan',
                                _atlitMerah,
                                true,
                                point: -5,
                                label: 'Peringatan 1 (-5)',
                              )
                            : pembinaan == 1
                            ? () => _handleKpAction(
                                'batal_pembinaan',
                                _atlitMerah,
                                true,
                                point: 5,
                                label: 'Pelanggaran Dibatalkan (+5)',
                              )
                            : null,
                        isActive: pembinaan >= 1,
                        activeColor: const Color(0xFFE11D48),
                        badge: '-5',
                        badgeColor: const Color(0xFFF43F5E),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 6),

                // ── Vertical Log Nilai Masuk (Merah - 5 Latest) ──
                Expanded(
                  flex: 2,
                  child: _buildVerticalLogNilaiSection(
                    'LOG NILAI MASUK (MERAH):',
                    history,
                    const Color(0xFFFB7185),
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
  // ── 5. CENTER CONTROL PANEL (TIMER, MULAI/STOP & DEWAN VERIFIKASI) ──
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildCenterControl() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B0F19),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E293B), width: 1.5),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── App/Event Logo Above Timer Box (70% Width) ──
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6.0),
              child: FractionallySizedBox(
                widthFactor: 0.50,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/img/logo-small.webp',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),

          // ── Digital Timer Box ──
          Container(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155), width: 1.2),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: !_tandingStatus
                        ? const Color(0xFF1E293B)
                        : _isTimerRunning
                        ? const Color(0xFF065F46)
                        : const Color(0xFF78350F),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    'BABAK ${_selectedJadwal?.babak ?? '1'} • ${!_tandingStatus
                        ? 'STANDBY'
                        : _isTimerRunning
                        ? 'BERJALAN'
                        : 'DIJEDA'}',
                    style: TextStyle(
                      color: !_tandingStatus
                          ? const Color(0xFF94A3B8)
                          : _isTimerRunning
                          ? const Color(0xFF34D399)
                          : const Color(0xFFFBBF24),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formattedTimer,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // ── Match Control Action Buttons (Mulai / Buzzer / Selesaikan) ──
          if (!_tandingStatus) ...[
            // 1. Mulai Pertandingan Button (Full Width)
            Expanded(
              child: GestureDetector(
                onTap: _handleMulai,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF059669), Color(0xFF047857)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF059669).withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'MULAI',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ] else ...[
            // 2. BUZZER Button (full-width, active during match)
            Expanded(
              child: GestureDetector(
                onTap: _handleBuzzer,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    gradient: _isBuzzerSounding
                        ? const LinearGradient(
                            colors: [Color(0xFFDC2626), Color(0xFF991B1B)],
                          )
                        : _buzzerCountdown > 0
                            ? const LinearGradient(
                                colors: [Color(0xFFD97706), Color(0xFFB45309)],
                              )
                            : const LinearGradient(
                                colors: [Color(0xFFEA580C), Color(0xFFC2410C)],
                              ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isBuzzerSounding
                          ? const Color(0xFFFCA5A5)
                          : _buzzerCountdown > 0
                              ? const Color(0xFFFDE047)
                              : const Color(0xFFFB923C),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (_isBuzzerSounding
                                ? const Color(0xFFDC2626)
                                : _buzzerCountdown > 0
                                    ? const Color(0xFFD97706)
                                    : const Color(0xFFEA580C))
                            .withValues(alpha: _isBuzzerActive ? 0.6 : 0.4),
                        blurRadius: _isBuzzerActive ? 18 : 10,
                        spreadRadius: _isBuzzerActive ? 2 : 0,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isBuzzerSounding
                            ? Icons.volume_up_rounded
                            : _buzzerCountdown > 0
                                ? Icons.cancel_outlined
                                : Icons.notifications_active_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isBuzzerSounding
                            ? 'BUZZER BERBUNYI!'
                            : _buzzerCountdown > 0
                                ? 'BUZZER (${_buzzerCountdown}s) • TAP BATAL'
                                : 'BUZZER (5s)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 6),

          // ── Selesaikan Pertandingan Button ──
          Expanded(
            child: GestureDetector(
              onTap: !_tandingStatus ? null : _handleStop,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: !_tandingStatus ? 0.35 : 1.0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE11D48), Color(0xFFBE123C)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE11D48).withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.stop_rounded, color: Colors.white, size: 26),
                      SizedBox(width: 8),
                      Text(
                        'SELESAIKAN',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 6),

          // ── Kendali Dewan Pertandingan Box (Verifikasi Jatuhan, Pelanggaran & Reset) ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1B4B).withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF4C1D95).withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              children: [
                const Text(
                  'KENDALI DEWAN',
                  style: TextStyle(
                    color: Color(0xFFA78BFA),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),

                // 1. Verifikasi Jatuhan Button
                Opacity(
                  opacity: _tandingStatus ? 1.0 : 0.38,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _tandingStatus ? _startVerifikasiJatuhan : null,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 11,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: _tandingStatus
                            ? const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                              )
                            : null,
                        color: _tandingStatus ? null : const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _tandingStatus
                              ? const Color(0xFF38BDF8)
                              : const Color(0xFF334155),
                          width: 1.2,
                        ),
                        boxShadow: _tandingStatus
                            ? [
                                BoxShadow(
                                  color: const Color(
                                    0xFF0284C7,
                                  ).withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified_user_rounded,
                            color: _tandingStatus
                                ? Colors.white
                                : const Color(0xFF64748B),
                            size: 26,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'VERIFIKASI JATUHAN',
                            style: TextStyle(
                              color: _tandingStatus
                                  ? Colors.white
                                  : const Color(0xFF64748B),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 6),

                // 2. Verifikasi Pelanggaran Button
                Opacity(
                  opacity: _tandingStatus ? 1.0 : 0.38,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _tandingStatus ? _startVerifikasiPelanggaran : null,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 11,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: _tandingStatus
                            ? const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xFFD97706), Color(0xFFB45309)],
                              )
                            : null,
                        color: _tandingStatus ? null : const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _tandingStatus
                              ? const Color(0xFFFBBF24)
                              : const Color(0xFF334155),
                          width: 1.2,
                        ),
                        boxShadow: _tandingStatus
                            ? [
                                BoxShadow(
                                  color: const Color(
                                    0xFFD97706,
                                  ).withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.gavel_rounded,
                            color: _tandingStatus
                                ? Colors.white
                                : const Color(0xFF64748B),
                            size: 26,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'VERIFIKASI PELANGGARAN',
                            style: TextStyle(
                              color: _tandingStatus
                                  ? Colors.white
                                  : const Color(0xFF64748B),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 6),

                // 3. Babak Selanjutnya Button
                Opacity(
                  opacity: (_tandingStatus || _selectedJadwal != null)
                      ? 1.0
                      : 0.38,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: (_tandingStatus || _selectedJadwal != null)
                        ? () => _handleBabakSelanjutnya()
                        : null,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 9,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        color: (_tandingStatus || _selectedJadwal != null)
                            ? const Color(0xFF4338CA)
                            : const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: (_tandingStatus || _selectedJadwal != null)
                              ? const Color(0xFF6366F1).withValues(alpha: 0.7)
                              : const Color(0xFF334155),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.skip_next_rounded,
                            color: (_tandingStatus || _selectedJadwal != null)
                                ? Colors.white
                                : const Color(0xFF64748B),
                            size: 22,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'BABAK SELANJUTNYA',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: (_tandingStatus || _selectedJadwal != null)
                                  ? Colors.white
                                  : const Color(0xFF64748B),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
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

  // ══════════════════════════════════════════════════════════════════════════
  // ── 6. REUSABLE ACTION TILES & VERTICAL LOG LIST SECTION (ENLARGED) ──
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildActionTile(
    String label,
    IconData icon,
    Color bgColor,
    VoidCallback? onTap, {
    bool isFilled = false,
    bool isActive = false,
    Color activeColor = const Color(0xFF6366F1),
    Color textColor = Colors.white70,
    String? badge,
    Color? badgeColor,
  }) {
    final isEnabled = _tandingStatus;
    final canTap = isEnabled && onTap != null;

    final effectiveBgColor = isActive
        ? activeColor
        : isFilled
        ? (isEnabled ? bgColor : const Color(0xFF1E293B))
        : const Color(0xFF090E1A).withValues(alpha: 0.78);

    final effectiveBorderColor = isActive
        ? Colors.white.withValues(alpha: 0.9)
        : isFilled
        ? Colors.transparent
        : (isEnabled
              ? const Color(0xFF334155).withValues(alpha: 0.8)
              : const Color(0xFF1E293B));

    final effectiveIconColor = isActive
        ? Colors.white
        : isEnabled
        ? (isFilled ? textColor : const Color(0xFFCBD5E1))
        : const Color(0xFF64748B);

    final effectiveTextColor = isActive
        ? Colors.white
        : isEnabled
        ? (isFilled ? textColor : Colors.white)
        : const Color(0xFF64748B);

    return Opacity(
      opacity: isEnabled ? 1.0 : 0.35,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: canTap ? onTap : null,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: effectiveBgColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: effectiveBorderColor,
                width: isActive ? 1.8 : 1.2,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: activeColor.withValues(alpha: 0.65),
                        blurRadius: 14,
                        spreadRadius: 1,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : (isFilled && isEnabled)
                  ? [
                      BoxShadow(
                        color: bgColor.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icon on top with optional penalty badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isActive ? Icons.check_circle_rounded : icon,
                      color: effectiveIconColor,
                      size: 26, // Enlarged icon
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? Colors.black.withValues(alpha: 0.35)
                              : isEnabled
                              ? (badgeColor ?? Colors.amber).withValues(
                                  alpha: 0.25,
                                )
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isActive
                                ? Colors.white.withValues(alpha: 0.8)
                                : isEnabled
                                ? (badgeColor ?? Colors.amber).withValues(
                                    alpha: 0.6,
                                  )
                                : const Color(0xFF334155),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            color: isActive
                                ? Colors.white
                                : isEnabled
                                ? (badgeColor ?? Colors.amber)
                                : const Color(0xFF64748B),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                // Text label on bottom
                Text(
                  label,
                  style: TextStyle(
                    color: effectiveTextColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Vertical List displaying the 5 latest score logs
  Widget _buildVerticalLogNilaiSection(
    String title,
    List<Nilai> history,
    Color accentColor,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF030712).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B), width: 1.2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
              Text(
                '${history.length}/5 TERBARU',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: history.isEmpty
                ? const Center(
                    child: Text(
                      'Belum ada riwayat nilai',
                      style: TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: history.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 3),
                    itemBuilder: (ctx, idx) {
                      final n = history[idx];
                      return _buildLogRowItem(n);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Individual Vertical Log Row Item with Distinct Colors for each score type
  Widget _buildLogRowItem(Nilai n) {
    final jenis = (n.jenis ?? '').toLowerCase();
    final jumlah = n.jumlah ?? 0;

    Color bgColor;
    Color borderColor;
    Color textColor;
    IconData icon;

    if (jenis == 'pukulan' || jumlah == 1) {
      // 1. PUKULAN (+1): Blue / Cyan theme
      bgColor = const Color(0xFF0C4A6E).withValues(alpha: 0.45);
      borderColor = const Color(0xFF0284C7);
      textColor = const Color(0xFF7DD3FC);
      icon = Icons.sports_mma_rounded;
    } else if (jenis == 'tendangan' || jumlah == 2) {
      // 2. TENDANGAN (+2): Emerald / Mint theme
      bgColor = const Color(0xFF064E3B).withValues(alpha: 0.45);
      borderColor = const Color(0xFF10B981);
      textColor = const Color(0xFF6EE7B7);
      icon = Icons.sports_martial_arts_rounded;
    } else if (jenis == 'batal_jatuhan' ||
        jumlah == -3 ||
        (jenis == 'jatuhan' && jumlah < 0)) {
      // 3. BATAL JATUHAN (-3): Zinc / Dark Gray theme
      bgColor = const Color(0xFF27272A).withValues(alpha: 0.6);
      borderColor = const Color(0xFF71717A);
      textColor = const Color(0xFFD4D4D8);
      icon = Icons.replay_rounded;
    } else if (jenis == 'jatuhan' || jumlah == 3) {
      // 4. JATUHAN (+3): Gold / Amber theme
      bgColor = const Color(0xFF78350F).withValues(alpha: 0.5);
      borderColor = const Color(0xFFF59E0B);
      textColor = const Color(0xFFFDE68A);
      icon = Icons.verified_user_rounded;
    } else if (jenis == 'binaan' || (jumlah == 0 && jenis.isNotEmpty)) {
      // 5. BINAAN (0): Indigo / Slate theme
      bgColor = const Color(0xFF1E1B4B).withValues(alpha: 0.5);
      borderColor = const Color(0xFF6366F1);
      textColor = const Color(0xFFA5B4FC);
      icon = Icons.info_outline;
    } else if (jenis == 'teguran' || jumlah == -1 || jumlah == -2) {
      // 6. TEGURAN (-1 / -2): Orange theme
      bgColor = const Color(0xFF7C2D12).withValues(alpha: 0.45);
      borderColor = const Color(0xFFEA580C);
      textColor = const Color(0xFFFDBA74);
      icon = Icons.warning_amber_rounded;
    } else if (jenis == 'pembinaan' ||
        jenis == 'peringatan' ||
        jumlah == -5 ||
        jumlah == -10) {
      // 7. PEMBINAAN / PERINGATAN (-5 / -10): Crimson / Rose theme
      bgColor = const Color(0xFF881337).withValues(alpha: 0.5);
      borderColor = const Color(0xFFE11D48);
      textColor = const Color(0xFFFECDD3);
      icon = Icons.report_problem_rounded;
    } else if (jenis == 'diskualifikasi') {
      // 8. DISKUALIFIKASI: Deep Purple theme
      bgColor = const Color(0xFF581C87).withValues(alpha: 0.55);
      borderColor = const Color(0xFFA855F7);
      textColor = const Color(0xFFE9D5FF);
      icon = Icons.gavel_rounded;
    } else {
      bgColor = const Color(0xFF1E293B).withValues(alpha: 0.5);
      borderColor = const Color(0xFF475569);
      textColor = const Color(0xFFE2E8F0);
      icon = Icons.info_outline;
    }

    final juriSource = (n.juriId != null && n.juriId!.isNotEmpty)
        ? (n.juriId!.toLowerCase() == 'kp'
              ? 'Dewan (KP)'
              : n.juriId!.toUpperCase())
        : (n.juriCount != null && n.juriCount! > 1
              ? '${n.juriCount} Juri'
              : 'Juri');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: 0.9),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: textColor),
              const SizedBox(width: 6),
              Text(
                n.poinLabel,
                style: TextStyle(
                  color: textColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  juriSource,
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (n.menitKe != null && n.menitKe!.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  n.menitKe!,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 9,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
