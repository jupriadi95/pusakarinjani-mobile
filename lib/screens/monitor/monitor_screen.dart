import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/gelanggang.dart';
import '../../models/jadwal.dart';
import '../../models/media.dart';
import '../../models/nilai.dart';
import '../../models/peserta.dart';
import '../../models/sponsor.dart';
import '../../providers/gelanggang_provider.dart';
import '../../providers/jadwal_provider.dart';
import '../../providers/nilai_provider.dart';
import '../../providers/socket_provider.dart';
import '../../config/env.dart';
import '../../services/api_service.dart';
import '../../widgets/standby_screen.dart';

/// Monitor Screen — Arena Scoreboard Display for Large Screens / TV Displays.
/// Features:
/// - Athlete Photos (with fallback initials avatar), Contingent, and Perguruan.
/// - Giant Total Scores with vibrant ambient glow.
/// - Synchronized Countdown Timer & Vertical Round (Babak 1, 2, 3) Indicator.
/// - Color-coded Vertical Score History Log (Pukulan, Tendangan, Jatuhan, Teguran, etc.).
/// - KP Sanksi Status (Binaan, Teguran, Pembinaan).
/// - Real-time Anonymous Dewan Verification Overlay (Vote counts for Blue, Red, Invalid).
/// - Winner Announcement Modal at the end of the match.
class MonitorScreen extends ConsumerStatefulWidget {
  const MonitorScreen({super.key});

  @override
  ConsumerState<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends ConsumerState<MonitorScreen> {
  late final SocketService _socketService;
  final _api = ApiService();

  bool _isConnected = false;
  Gelanggang? _gelanggang;
  Peserta? _atlit1; // Blue corner athlete
  Peserta? _atlit2; // Red corner athlete
  Jadwal? _activeJadwal;

  // ── Match Timer State (Count UP) ──
  int _timerSeconds = 0;
  bool _isTimerRunning = false;
  Timer? _countdownTimer;

  // ── KP Sanctions State ──
  int _kpBinaanBiru = 0;
  int _kpTeguranBiru = 0;
  int _kpPembinaanBiru = 0;
  int _kpBinaanMerah = 0;
  int _kpTeguranMerah = 0;
  int _kpPembinaanMerah = 0;

  // ── Dewan Verification Overlay State (Anonymous Summary) ──
  bool _verifikasiActive = false;
  String _verifikasiJenis = 'jatuhan';
  String? _verifikasiHasil;
  final Map<String, String?> _verifikasiVotes = {
    'juri_1': null,
    'juri_2': null,
    'juri_3': null,
  };
  Timer? _verifikasiDismissTimer;

  // ── Winner Announcement State ──
  static const int _winnerDisplayDurationSeconds = 20;
  bool _showWinnerModal = false;
  Timer? _winnerDismissTimer;
  int _winnerDismissRemainingSeconds = _winnerDisplayDurationSeconds;
  String? _liveBabakOverride;

  // ── Keputusan Dewan saat skor SERI ('biru' | 'merah') ──
  String? _dewanPemenang;

  // ── Disqualification State ──
  String? _dsqSudut; // 'biru' | 'merah'
  String? _dsqNama;
  String? _dsqMessage;

  // ── Sponsors (for standby showcase) ──
  List<Sponsor> _sponsors = [];

  StreamSubscription? _connectionSub;
  StreamSubscription? _gelanggangSub;
  StreamSubscription? _nilaiSub;
  StreamSubscription? _nilaiKpSub; // Receives KP deductions persisted via REST
  StreamSubscription? _kpStatusSub;
  StreamSubscription? _pesertaDsqSub;
  StreamSubscription? _verifikasiMulaiSub;
  StreamSubscription? _verifikasiVoteSub;
  StreamSubscription? _verifikasiSelesaiSub;
  StreamSubscription? _timerControlSub;
  StreamSubscription? _babakChangedSub;
  StreamSubscription? _pertandinganSelesaiSub;
  Timer?
  _fetchNilaiDebounce; // Debounce timer to prevent race condition on rapid kp:status events

  @override
  void initState() {
    super.initState();
    // Resolve shared singleton socket service
    _socketService = ref.read(socketServiceProvider);
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
      // Defer provider modifications so they run AFTER initState completes.
      // This prevents the Riverpod "modify provider while building" error.
      Future.microtask(() {
        if (!mounted) return;
        ref.read(jadwalListProvider.notifier).fetchJadwal(_gelanggang!);
      });

      if (_gelanggang!.atlit1Id != null && _gelanggang!.atlit1Id!.isNotEmpty) {
        _fetchPeserta(_gelanggang!.atlit1Id!, 1);
      }
      if (_gelanggang!.atlit2Id != null && _gelanggang!.atlit2Id!.isNotEmpty) {
        _fetchPeserta(_gelanggang!.atlit2Id!, 2);
      }
      _fetchNilai();

      // Fetch sponsors for standby showcase
      final eventDocId = _gelanggang!.event?.documentId;
      if (eventDocId != null && eventDocId.isNotEmpty) {
        _fetchSponsors(eventDocId);
      }

      if (_gelanggang!.isBerlangsung) {
        _startTimer();
      }

      _socketService.connect(gelanggangDocumentId: _gelanggang!.documentId);
    }

    _connectionSub = _socketService.onConnectionChanged.listen((connected) {
      if (mounted) setState(() => _isConnected = connected);
    });

    _gelanggangSub = _socketService.onGelanggangUpdated.listen((updated) {
      if (mounted) {
        final wasBerlangsung = _gelanggang?.isBerlangsung ?? false;
        final isNowFinished =
            updated.statusTanding == 'selesai' ||
            (!updated.isBerlangsung && wasBerlangsung);
        final isStartingNewMatch = updated.isBerlangsung && !wasBerlangsung;

        // Deteksi pergantian partai: atlit berubah → berarti Dewan memilih partai lain
        final isPartaiBaru =
            (updated.atlit1Id != _gelanggang?.atlit1Id ||
                updated.atlit2Id != _gelanggang?.atlit2Id) &&
            !updated.isBerlangsung;

        // Clear score when a new match is started OR when dewan switches to a new partai!
        if (isStartingNewMatch || isPartaiBaru) {
          ref.read(nilaiListProvider.notifier).clear();
          _hideWinnerModal();
          setState(() {
            _dewanPemenang = null;
            _dsqSudut = null;
            _dsqNama = null;
            _dsqMessage = null;
            _kpBinaanMerah = 0;
            _kpTeguranMerah = 0;
            _kpPembinaanMerah = 0;
            _kpBinaanBiru = 0;
            _kpTeguranBiru = 0;
            _kpPembinaanBiru = 0;
            _liveBabakOverride = null;
            _activeJadwal = null;
          });
        }

        setState(() {
          _gelanggang = updated;
          if (updated.isBerlangsung) {
            _startTimer();
          } else {
            _pauseTimer();
          }
        });

        ref.read(activeGelanggangProvider.notifier).updateFromSocket(updated);
        ref.read(jadwalListProvider.notifier).fetchJadwal(updated);
        if (updated.atlit1Id != null && updated.atlit1Id!.isNotEmpty) {
          _fetchPeserta(updated.atlit1Id!, 1);
        }
        if (updated.atlit2Id != null && updated.atlit2Id!.isNotEmpty) {
          _fetchPeserta(updated.atlit2Id!, 2);
        }
        _fetchNilai();

        // Show winner celebration modal if match finished
        if (isNowFinished && mounted) {
          _triggerWinnerModal();
        }
      }
    });

    _nilaiSub = _socketService.onNilaiCreated.listen((newNilai) {
      if (mounted) ref.read(nilaiListProvider.notifier).addFromSocket(newNilai);
    });

    // ── KP nilai persisted via REST — direct realtime sync & sanction counter update ──
    _nilaiKpSub = _socketService.onNilaiKp.listen((data) {
      if (!mounted) return;
      try {
        final nilai = Nilai.fromJson(Map<String, dynamic>.from(data));
        ref.read(nilaiListProvider.notifier).addFromSocket(nilai);

        final sudut =
            (data['sudut'] ?? nilai.sudut ?? '').toString().toLowerCase();
        final jenis =
            (data['jenis'] ?? nilai.jenis ?? '').toString().toLowerCase();
        final jumlah = (data['jumlah'] ?? nilai.jumlah ?? 0) is num
            ? ((data['jumlah'] ?? nilai.jumlah ?? 0) as num).toInt()
            : (int.tryParse(
                    (data['jumlah'] ?? nilai.jumlah ?? '0').toString()) ??
                0);
        final isRed = sudut == 'merah';

        setState(() {
          if (jenis == 'binaan') {
            if (isRed) {
              _kpBinaanMerah = (_kpBinaanMerah + 1).clamp(0, 2);
            } else {
              _kpBinaanBiru = (_kpBinaanBiru + 1).clamp(0, 2);
            }
          } else if (jenis == 'batal_binaan') {
            if (isRed) {
              _kpBinaanMerah = (_kpBinaanMerah - 1).clamp(0, 2);
            } else {
              _kpBinaanBiru = (_kpBinaanBiru - 1).clamp(0, 2);
            }
          } else if (jenis == 'teguran') {
            final count = jumlah == -2 ? 2 : 1;
            if (isRed) {
              _kpTeguranMerah = count;
            } else {
              _kpTeguranBiru = count;
            }
          } else if (jenis == 'batal_teguran') {
            final count = jumlah == 2 ? 1 : 0;
            if (isRed) {
              _kpTeguranMerah = count;
            } else {
              _kpTeguranBiru = count;
            }
          } else if (jenis == 'pembinaan' || jenis == 'peringatan') {
            final count = jumlah == -10 ? 2 : 1;
            if (isRed) {
              _kpPembinaanMerah = count;
            } else {
              _kpPembinaanBiru = count;
            }
          } else if (jenis == 'batal_pembinaan' || jenis == 'batal_peringatan') {
            final count = jumlah == 10 ? 1 : 0;
            if (isRed) {
              _kpPembinaanMerah = count;
            } else {
              _kpPembinaanBiru = count;
            }
          }
        });
      } catch (e) {
        debugPrint('[Monitor] Error parsing nilai:kp payload: $e');
      }
    });

    // ── KP Sanctions Status Listener ──
    _kpStatusSub = _socketService.onKpStatus.listen((data) {
      if (!mounted) return;

      int safeInt(dynamic v, int fallback) {
        if (v == null) return fallback;
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse(v.toString()) ?? fallback;
      }

      final merah = (data['merah'] as Map?) ?? data;
      final biru = (data['biru'] as Map?) ?? data;

      final statusDisiplin =
          (merah['statusDisiplin'] ??
                  biru['statusDisiplin'] ??
                  data['statusDisiplin'])
              ?.toString();
      final aksi = data['aksi']?.toString();
      final isDsq =
          statusDisiplin == 'diskualifikasi' || aksi == 'diskualifikasi';

      setState(() {
        if (aksi == 'reset_babak') {
          _kpBinaanMerah = 0;
          _kpTeguranMerah = 0;
          _kpPembinaanMerah = 0;
          _kpBinaanBiru = 0;
          _kpTeguranBiru = 0;
          _kpPembinaanBiru = 0;
        } else {
          if (data.containsKey('merah') && data['merah'] is Map) {
            final m = data['merah'] as Map;
            _kpBinaanMerah =
                safeInt(m['binaan'] ?? m['kp_binaan_merah'], _kpBinaanMerah);
            _kpTeguranMerah =
                safeInt(m['teguran'] ?? m['kp_teguran_merah'], _kpTeguranMerah);
            _kpPembinaanMerah = safeInt(
                m['pembinaan'] ?? m['kp_pembinaan_merah'], _kpPembinaanMerah);
          } else if (data['sudut'] == 'merah' || data.containsKey('merah')) {
            _kpBinaanMerah = safeInt(
                merah['binaan'] ?? merah['kp_binaan_merah'], _kpBinaanMerah);
            _kpTeguranMerah = safeInt(
                merah['teguran'] ?? merah['kp_teguran_merah'],
                _kpTeguranMerah);
            _kpPembinaanMerah = safeInt(
                merah['pembinaan'] ?? merah['kp_pembinaan_merah'],
                _kpPembinaanMerah);
          }

          if (data.containsKey('biru') && data['biru'] is Map) {
            final b = data['biru'] as Map;
            _kpBinaanBiru =
                safeInt(b['binaan'] ?? b['kp_binaan_biru'], _kpBinaanBiru);
            _kpTeguranBiru =
                safeInt(b['teguran'] ?? b['kp_teguran_biru'], _kpTeguranBiru);
            _kpPembinaanBiru = safeInt(
                b['pembinaan'] ?? b['kp_pembinaan_biru'], _kpPembinaanBiru);
          } else if (data['sudut'] == 'biru' || data.containsKey('biru')) {
            _kpBinaanBiru = safeInt(
                biru['binaan'] ?? biru['kp_binaan_biru'], _kpBinaanBiru);
            _kpTeguranBiru = safeInt(
                biru['teguran'] ?? biru['kp_teguran_biru'], _kpTeguranBiru);
            _kpPembinaanBiru = safeInt(
                biru['pembinaan'] ?? biru['kp_pembinaan_biru'],
                _kpPembinaanBiru);
          }
        }

        if (isDsq) {
          final sudut = (data['sudut'] ?? 'merah').toString().toLowerCase();
          _dsqSudut = sudut;
          _dsqNama =
              (sudut == 'biru' ? _atlit1?.namaLengkap : _atlit2?.namaLengkap) ??
              '';
          _dsqMessage =
              data['keterangan']?.toString() ??
              'Peserta Sudut ${sudut.toUpperCase()} Diskualifikasi!';
          _pauseTimer();
          _triggerWinnerModal();
        }
      });

      // Debounce _fetchNilai by 700ms so DB write completes before we poll.
      // This eliminates the race condition where optimistic items get overwritten by stale DB data.
      _fetchNilaiDebounce?.cancel();
      _fetchNilaiDebounce = Timer(const Duration(milliseconds: 700), () {
        if (mounted) _fetchNilai();
      });
    });

    // ── Disqualification Listener ──
    _pesertaDsqSub = _socketService.onPesertaDsq.listen((data) {
      if (!mounted) return;
      final sudut = (data['sudut'] ?? 'merah').toString().toLowerCase();
      final nama =
          data['nama']?.toString() ??
          (sudut == 'biru' ? _atlit1?.namaLengkap : _atlit2?.namaLengkap) ??
          '';
      final message =
          data['message']?.toString() ??
          'Peserta Sudut ${sudut.toUpperCase()} Diskualifikasi!';

      setState(() {
        _dsqSudut = sudut;
        _dsqNama = nama;
        _dsqMessage = message;
        _pauseTimer();
      });
      _triggerWinnerModal();
    });

    // ── Dewan Verification Socket Listeners ──
    _verifikasiMulaiSub = _socketService.onVerifikasiMulai.listen((data) {
      if (!mounted) return;
      _verifikasiDismissTimer?.cancel();
      setState(() {
        _verifikasiActive = true;
        _verifikasiJenis = data['jenis']?.toString() ?? 'jatuhan';
        _verifikasiHasil = null;
        _verifikasiVotes['juri_1'] = null;
        _verifikasiVotes['juri_2'] = null;
        _verifikasiVotes['juri_3'] = null;
      });
    });

    _verifikasiVoteSub = _socketService.onVerifikasiVote.listen((data) {
      if (!mounted || !_verifikasiActive) return;
      final juriId =
          data['juriId']?.toString() ?? data['juri_id']?.toString() ?? '';
      final pilihan = data['pilihan']?.toString() ?? '';

      if (['juri_1', 'juri_2', 'juri_3'].contains(juriId)) {
        setState(() {
          _verifikasiVotes[juriId] = pilihan;

          // Hanya tentukan hasil akhir jika KETIGA juri (3 dari 3) sudah selesai memberikan voting
          final votes = _verifikasiVotes.values
              .where((v) => v != null)
              .toList();

          if (votes.length == 3) {
            final countBiru = votes.where((v) => v == 'biru').length;
            final countMerah = votes.where((v) => v == 'merah').length;

            if (countBiru >= 2) {
              _verifikasiHasil = 'biru';
            } else if (countMerah >= 2) {
              _verifikasiHasil = 'merah';
            } else {
              _verifikasiHasil = 'invalid';
            }
          }
        });
      }
    });

    _verifikasiSelesaiSub = _socketService.onVerifikasiSelesai.listen((data) {
      if (!mounted) return;
      final action = data['action']?.toString();
      final hasil = data['hasil']?.toString() ?? '';

      if (action == 'tutup' || action == 'close' || hasil == 'dibatalkan') {
        // Popup hanya ditutup ketika popup yang ada di dewan pertandingan diselesaikan
        _verifikasiDismissTimer?.cancel();
        setState(() {
          _verifikasiActive = false;
          _verifikasiHasil = null;
        });
        _fetchNilai();
      } else {
        // Update hasil akhir agar muncul di monitor
        if (hasil.isNotEmpty) {
          setState(() {
            _verifikasiHasil = hasil;
          });
        }
        _fetchNilai();
      }
    });

    // ── Synchronized Timer Control Listener (Mulai, Jeda/Pause, Lanjut/Resume, Stop) ──
    _timerControlSub = _socketService.onTimerControl.listen((data) {
      if (!mounted) return;
      final action = data['action']?.toString();
      final seconds = data['seconds'] as int?;
      final dsqSudut = data['dsqSudut']?.toString().toLowerCase();
      final dsqNama = data['dsqNama']?.toString();
      final pemenang = data['pemenang']?.toString().toLowerCase();

      setState(() {
        if (seconds != null) {
          _timerSeconds = seconds;
        }
        if (dsqSudut != null && dsqSudut.isNotEmpty) {
          _dsqSudut = dsqSudut;
          _dsqNama = dsqNama;
        }
        if (pemenang == 'biru' || pemenang == 'merah') {
          _dewanPemenang = pemenang;
        }
        if (action == 'pause') {
          _pauseTimer();
        } else if (action == 'resume' || action == 'start') {
          _startTimer();
          _hideWinnerModal();
          _dewanPemenang = null;
          _dsqSudut = null;
          _dsqNama = null;
        } else if (action == 'reset') {
          _pauseTimer();
          _timerSeconds = 0;
          _hideWinnerModal();
          _dewanPemenang = null;
          _dsqSudut = null;
          _dsqNama = null;
          _kpBinaanBiru = 0;
          _kpTeguranBiru = 0;
          _kpBinaanMerah = 0;
          _kpTeguranMerah = 0;
        } else if (action == 'stop') {
          _pauseTimer();
          _triggerWinnerModal();
        }
      });

      if (pemenang == 'biru' || pemenang == 'merah') {
        _triggerWinnerModal();
      }

      if (action == 'stop') {
        _fetchNilai();
      }
    });

    // ── Babak / Round Change Listener ──
    _babakChangedSub = _socketService.onBabakChanged.listen((data) {
      if (!mounted) return;
      final babak = data['babak']?.toString();
      if (babak != null && babak.isNotEmpty) {
        setState(() {
          _liveBabakOverride = babak;
          // Reset hanya Binaan & Teguran — Peringatan (pembinaan) & histori nilai TIDAK di-reset
          _kpBinaanBiru = 0;
          _kpTeguranBiru = 0;
          _kpBinaanMerah = 0;
          _kpTeguranMerah = 0;
        });
      }
    });

    // ── Match Completion / Finished Listener ──
    _pertandinganSelesaiSub = _socketService.onPertandinganSelesai.listen((
      data,
    ) {
      if (!mounted) return;
      final dsqSudut = data['dsqSudut']?.toString().toLowerCase();
      final dsqNama = data['dsqNama']?.toString();
      final pemenang = data['pemenang']?.toString().toLowerCase();
      setState(() {
        if (dsqSudut != null && dsqSudut.isNotEmpty) {
          _dsqSudut = dsqSudut;
          _dsqNama = dsqNama;
        }
        if (pemenang == 'biru' || pemenang == 'merah') {
          _dewanPemenang = pemenang;
        }
        _pauseTimer();
      });
      _triggerWinnerModal();
      _fetchNilai();
    });
  }

  /// Cek apakah skor saat ini seri dan Dewan belum memberikan keputusan
  bool _isSeriWaitingDewan() {
    if (_dsqSudut != null && _dsqSudut!.isNotEmpty) return false;
    if (_dewanPemenang != null) return false;
    final nilaiList = ref.read(nilaiListProvider);
    final a1Id = _atlit1?.documentId ??
        _atlit1?.id?.toString() ??
        _gelanggang?.atlit1Id ??
        '';
    final a2Id = _atlit2?.documentId ??
        _atlit2?.id?.toString() ??
        _gelanggang?.atlit2Id ??
        '';
    final active = _resolveActiveJadwal();
    final jDocId = active?.documentId ?? '';
    final jId = active?.id?.toString() ?? '';
    final biruScore = countNilaiForPeserta(
      nilaiList,
      a1Id,
      sudut: 'biru',
      jadwalDocId: jDocId,
      jadwalId: jId,
    );
    final merahScore = countNilaiForPeserta(
      nilaiList,
      a2Id,
      sudut: 'merah',
      jadwalDocId: jDocId,
      jadwalId: jId,
    );
    return biruScore == merahScore;
  }

  /// Tampilkan popup pemenang dan mulai countdown 20 detik untuk otomatis ditutup
  void _triggerWinnerModal() {
    _winnerDismissTimer?.cancel();
    _winnerDismissRemainingSeconds = _winnerDisplayDurationSeconds;
    if (mounted) {
      setState(() {
        _showWinnerModal = true;
      });
    }

    // Jika skor seri dan Dewan belum memutuskan pemenang, jangan jalankan timer auto-dismiss 20 detik
    // agar layar statistik capaian nilai tetap terlihat oleh Dewan sampai ada keputusan.
    if (_isSeriWaitingDewan()) {
      return;
    }

    _winnerDismissTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_winnerDismissRemainingSeconds > 1) {
        setState(() {
          _winnerDismissRemainingSeconds--;
        });
      } else {
        timer.cancel();
        _winnerDismissTimer = null;
        setState(() {
          _winnerDismissRemainingSeconds = 0;
          _showWinnerModal = false;
        });
      }
    });
  }

  /// Sembunyikan popup pemenang dan batalkan timer countdown
  void _hideWinnerModal() {
    _winnerDismissTimer?.cancel();
    _winnerDismissTimer = null;
    if (mounted && _showWinnerModal) {
      setState(() {
        _showWinnerModal = false;
      });
    }
  }

  void _startTimer() {
    _isTimerRunning = true;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        if (_timerSeconds > 0) {
          setState(() => _timerSeconds--);
        } else {
          _isTimerRunning = false;
          _countdownTimer?.cancel();
        }
      } else {
        _isTimerRunning = false;
        _countdownTimer?.cancel();
      }
    });
  }

  void _pauseTimer() {
    _isTimerRunning = false;
    _countdownTimer?.cancel();
  }

  String get _formattedTimer {
    final mins = (_timerSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (_timerSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  Future<void> _fetchPeserta(String docId, int dst) async {
    if (docId.isEmpty) return;
    try {
      final response = await _api.findOneProtect(
        'pesertas',
        docId,
        params: {'populate[0]': 'action_foto', 'populate[1]': 'pas_foto'},
      );
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

  Future<void> _fetchSponsors(String eventDocumentId) async {
    try {
      final list = await _api.fetchSponsorsByEvent(eventDocumentId);
      final parsed = list
          .whereType<Map<String, dynamic>>()
          .map(Sponsor.fromJson)
          .toList();
      if (mounted) setState(() => _sponsors = parsed);
    } catch (e) {
      debugPrint('Monitor fetchSponsors error: $e');
    }
  }

  /// Mendapatkan data Jadwal/Partai yang aktif ditampilkan di monitor
  Jadwal? _resolveActiveJadwal([List<Jadwal>? list]) {
    final jadwals = list ?? ref.read(jadwalListProvider).valueOrNull ?? [];
    if (jadwals.isEmpty) return _activeJadwal;

    final a1 = _gelanggang?.atlit1Id ?? _atlit1?.documentId ?? _atlit1?.id?.toString();
    final a2 = _gelanggang?.atlit2Id ?? _atlit2?.documentId ?? _atlit2?.id?.toString();

    // 1. Prioritas utama: Partai dengan status 'berlangsung' saat gelanggang aktif
    final ongoing =
        jadwals.where((j) => j.statusTanding == 'berlangsung').firstOrNull;
    if (ongoing != null && (_gelanggang?.isBerlangsung ?? false)) {
      return ongoing;
    }

    // 2. Prioritas kedua: Partai yang mencocokkan KEDUA atlet sudut biru & merah
    if (a1 != null && a1.isNotEmpty && a2 != null && a2.isNotEmpty) {
      final both = jadwals.where((j) {
        final bDoc =
            j.biruPeserta?.documentId ?? j.biruPeserta?.id?.toString();
        final mDoc =
            j.merahPeserta?.documentId ?? j.merahPeserta?.id?.toString();
        return (bDoc == a1 && mDoc == a2) || (bDoc == a2 && mDoc == a1);
      }).firstOrNull;
      if (both != null) return both;
    }

    // 3. Match dengan status 'berlangsung' jika ada
    if (ongoing != null) return ongoing;

    // 4. Match dengan salah satu atlet jika salah satu atlet cocok
    if ((a1 != null && a1.isNotEmpty) || (a2 != null && a2.isNotEmpty)) {
      final single = jadwals.where((j) {
        final bDoc =
            j.biruPeserta?.documentId ?? j.biruPeserta?.id?.toString();
        final mDoc =
            j.merahPeserta?.documentId ?? j.merahPeserta?.id?.toString();
        final matchA1 =
            a1 != null && a1.isNotEmpty && (bDoc == a1 || mDoc == a1);
        final matchA2 =
            a2 != null && a2.isNotEmpty && (bDoc == a2 || mDoc == a2);
        return matchA1 || matchA2;
      }).firstOrNull;
      if (single != null) return single;
    }

    return _activeJadwal ?? jadwals.firstOrNull;
  }

  Future<void> _fetchNilai() async {
    if (_gelanggang == null) return;
    final a1 = _gelanggang!.atlit1Id ?? _atlit1?.documentId ?? _atlit1?.id?.toString() ?? '';
    final a2 = _gelanggang!.atlit2Id ?? _atlit2?.documentId ?? _atlit2?.id?.toString() ?? '';

    final activeJadwal = _resolveActiveJadwal();
    if (activeJadwal != null && mounted) {
      _activeJadwal = activeJadwal;
    }

    final jDocId = activeJadwal?.documentId ?? '';
    final jId = activeJadwal?.id?.toString() ?? '';

    if (a1.isNotEmpty || a2.isNotEmpty || jDocId.isNotEmpty || jId.isNotEmpty) {
      await ref.read(nilaiListProvider.notifier).fetchNilai(
            a1,
            a2,
            jadwalDocId: jDocId,
            jadwalId: jId,
          );
    }
  }

  String? _resolveImageUrl(Media? media) {
    if (media == null || media.url == null || media.url!.isEmpty) return null;
    final url = media.url!;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      // In offline mode, if the image URL points to the cloud domain, rewrite to the local backend base URL
      if (Env.isOffline && url.contains('pusakarinjani.my.id')) {
        return url.replaceFirst(RegExp(r'https?://[^/]+'), Env.apiBaseUrl);
      }
      return url;
    }
    return '${Env.apiBaseUrl}$url';
  }

  String _resolveCurrentBabak() {
    if (_liveBabakOverride != null && _liveBabakOverride!.isNotEmpty) {
      return _liveBabakOverride!;
    }
    final active = _resolveActiveJadwal();
    return active?.babak ?? '1';
  }

  @override
  void dispose() {
    _winnerDismissTimer?.cancel();
    _verifikasiDismissTimer?.cancel();
    _fetchNilaiDebounce?.cancel();
    _countdownTimer?.cancel();
    _connectionSub?.cancel();
    _gelanggangSub?.cancel();
    _nilaiSub?.cancel();
    _nilaiKpSub?.cancel();
    _kpStatusSub?.cancel();
    _pesertaDsqSub?.cancel();
    _verifikasiMulaiSub?.cancel();
    _verifikasiVoteSub?.cancel();
    _verifikasiSelesaiSub?.cancel();
    _timerControlSub?.cancel();
    _babakChangedSub?.cancel();
    _pertandinganSelesaiSub?.cancel();
    // Do NOT call _socketService.disconnect() — socket is a shared singleton via Riverpod provider
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listen to jadwalList updates so active match is identified promptly
    ref.listen<AsyncValue<List<Jadwal>>>(jadwalListProvider, (previous, next) {
      final list = next.valueOrNull;
      if (list != null && list.isNotEmpty) {
        final resolved = _resolveActiveJadwal(list);
        if (resolved != null && resolved.documentId != _activeJadwal?.documentId) {
          setState(() {
            _activeJadwal = resolved;
          });
          _fetchNilai();
        }
      }
    });

    ref.listen<Gelanggang?>(activeGelanggangProvider, (previous, next) {
      if (next != null) {
        final atlitChanged = next.atlit1Id != previous?.atlit1Id || next.atlit2Id != previous?.atlit2Id;
        if (atlitChanged) {
          ref.read(nilaiListProvider.notifier).clear();
          setState(() {
            _gelanggang = next;
            _activeJadwal = _resolveActiveJadwal();
          });
          _fetchNilai();
        }
      }
    });

    // Re-evaluate whenever jadwal list state updates
    ref.watch(jadwalListProvider);

    // STATE 2: STANDBY
    if (_gelanggang?.statusTanding != 'berlangsung' && !_showWinnerModal) {
      return Scaffold(
        body: StandbyScreen(
          eventInfo: _gelanggang?.event,
          gelanggangInfo: _gelanggang,
          isLargeDisplay: true,
          sponsors: _sponsors,
          leadingAction: GestureDetector(
            onTap: () {
              Navigator.of(context).pushReplacementNamed('/home');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_back,
                    color: Color(0xFF94A3B8),
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Kembali ke Portal',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          trailingAction: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: (_isConnected
                      ? const Color(0xFF065F46)
                      : const Color(0xFF881337))
                  .withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isConnected
                    ? const Color(0xFF10B981)
                    : const Color(0xFFE11D48),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isConnected
                        ? const Color(0xFF34D399)
                        : const Color(0xFFFB7185),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _isConnected ? 'TERHUBUNG KE ARENA' : 'OFFLINE',
                  style: TextStyle(
                    color: _isConnected
                        ? const Color(0xFF34D399)
                        : const Color(0xFFFB7185),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // STATE 1: ACTIVE SCOREBOARD (Large Arena Screen)
    return _buildActiveScoreboard();
  }

  Widget _buildActiveScoreboard() {
    final nilaiList = ref.watch(nilaiListProvider);
    final a1Id =
        _atlit1?.documentId ??
        _atlit1?.id?.toString() ??
        _gelanggang?.atlit1Id ??
        '';
    final a2Id =
        _atlit2?.documentId ??
        _atlit2?.id?.toString() ??
        _gelanggang?.atlit2Id ??
        '';

    final activeJadwal = _resolveActiveJadwal();
    final jDocId = activeJadwal?.documentId ?? '';
    final jId = activeJadwal?.id?.toString() ?? '';

    // Filter score records strictly to the active match/jadwal
    final matchNilaiList = (jDocId.isNotEmpty || jId.isNotEmpty)
        ? nilaiList.where((n) {
            final nDoc = n.jadwalDocId;
            final nId = n.jadwalId;
            final hasJadwalRef = (nDoc != null && nDoc.isNotEmpty) ||
                (nId != null && nId.isNotEmpty);
            if (hasJadwalRef) {
              final matchDoc = jDocId.isNotEmpty && (nDoc == jDocId || nId == jDocId);
              final matchId = jId.isNotEmpty && (nId == jId || nDoc == jId);
              return matchDoc || matchId;
            }
            final doc = n.peserta?.documentId;
            final id = n.peserta?.id?.toString();
            final hasAthlete = (doc != null && doc.isNotEmpty) || (id != null && id.isNotEmpty);
            if (hasAthlete) {
              final matchA1 = a1Id.isNotEmpty && (doc == a1Id || id == a1Id);
              final matchA2 = a2Id.isNotEmpty && (doc == a2Id || id == a2Id);
              return matchA1 || matchA2;
            }
            return true;
          }).toList()
        : nilaiList;

    final atlit1Score = countNilaiForPeserta(
      matchNilaiList,
      a1Id,
      sudut: 'biru',
      jadwalDocId: jDocId,
      jadwalId: jId,
    );
    final atlit2Score = countNilaiForPeserta(
      matchNilaiList,
      a2Id,
      sudut: 'merah',
      jadwalDocId: jDocId,
      jadwalId: jId,
    );
    final atlit1Logs = recentNilaiForPeserta(
      matchNilaiList,
      a1Id,
      limit: 5,
      sudut: 'biru',
      jadwalDocId: jDocId,
      jadwalId: jId,
    );
    final atlit2Logs = recentNilaiForPeserta(
      matchNilaiList,
      a2Id,
      limit: 5,
      sudut: 'merah',
      jadwalDocId: jDocId,
      jadwalId: jId,
    );
    final currentBabak = _resolveCurrentBabak();

    // Dynamically derive sanction indicator lights from score history and live state
    int computeSanctions(String corner, String jenis, int liveState) {
      final relevant = matchNilaiList.where((n) {
        if (!n.isSah) return false;
        final matchesCorner = (n.sudut?.toLowerCase() == corner.toLowerCase());
        final isCurrentRound = (n.babak == null ||
            n.babak!.isEmpty ||
            n.babak == currentBabak);
        return matchesCorner && isCurrentRound;
      }).toList();

      final sorted = List<Nilai>.from(relevant);
      sorted.sort((a, b) {
        final aTime = a.createdAt ?? DateTime(2000);
        final bTime = b.createdAt ?? DateTime(2000);
        return aTime.compareTo(bTime);
      });

      if (jenis == 'binaan') {
        bool hasBinaan = false;
        int count = 0;
        for (final n in sorted) {
          final j = (n.jenis ?? '').toLowerCase();
          if (j == 'binaan' || j == 'batal_binaan') {
            hasBinaan = true;
            if (j == 'binaan') count++;
            if (j == 'batal_binaan') count--;
          }
        }
        return hasBinaan ? count.clamp(0, 2) : liveState;
      } else if (jenis == 'teguran') {
        bool hasTeguran = false;
        int count = 0;
        for (final n in sorted) {
          final j = (n.jenis ?? '').toLowerCase();
          final p = n.jumlah ?? 0;
          if (j == 'teguran' || j == 'batal_teguran') {
            hasTeguran = true;
            if (j == 'teguran') {
              count = p == -2 ? 2 : 1;
            } else if (j == 'batal_teguran') {
              count = p == 2 ? 1 : 0;
            }
          }
        }
        return hasTeguran ? count.clamp(0, 2) : liveState;
      } else if (jenis == 'pembinaan') {
        bool hasPembinaan = false;
        int count = 0;
        for (final n in sorted) {
          final j = (n.jenis ?? '').toLowerCase();
          final p = n.jumlah ?? 0;
          if (j == 'pembinaan' ||
              j == 'peringatan' ||
              j == 'batal_pembinaan' ||
              j == 'batal_peringatan') {
            hasPembinaan = true;
            if (j == 'pembinaan' || j == 'peringatan') {
              count = p == -10 ? 2 : 1;
            } else if (j == 'batal_pembinaan' || j == 'batal_peringatan') {
              count = p == 10 ? 1 : 0;
            }
          }
        }
        return hasPembinaan ? count.clamp(0, 2) : liveState;
      }
      return liveState;
    }

    final finalBinaanBiru = computeSanctions('biru', 'binaan', _kpBinaanBiru);
    final finalTeguranBiru = computeSanctions('biru', 'teguran', _kpTeguranBiru);
    final finalPembinaanBiru =
        computeSanctions('biru', 'pembinaan', _kpPembinaanBiru);

    final finalBinaanMerah = computeSanctions('merah', 'binaan', _kpBinaanMerah);
    final finalTeguranMerah =
        computeSanctions('merah', 'teguran', _kpTeguranMerah);
    final finalPembinaanMerah =
        computeSanctions('merah', 'pembinaan', _kpPembinaanMerah);

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
        child: Stack(
          children: [
            // Background ambient glows
            Positioned(
              top: MediaQuery.of(context).size.height * 0.25,
              left: MediaQuery.of(context).size.width * 0.08,
              child: Container(
                width: 420,
                height: 420,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF0284C7).withValues(alpha: 0.18),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).size.height * 0.25,
              right: MediaQuery.of(context).size.width * 0.08,
              child: Container(
                width: 420,
                height: 420,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE11D48).withValues(alpha: 0.18),
                ),
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  // 1. Top Header Bar
                  _buildHeader(),

                  // 2. Main Arena View: Dual Athlete Cards + Center Control Tower
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // SUDUT BIRU (LEFT)
                          Expanded(
                            flex: 5,
                            child: _buildAthleteCard(
                              atlit: _atlit1,
                              isRed: false,
                              score: atlit1Score,
                              logs: atlit1Logs,
                              binaan: finalBinaanBiru,
                              teguran: finalTeguranBiru,
                              pembinaan: finalPembinaanBiru,
                            ),
                          ),

                          const SizedBox(width: 12),

                          // CENTER MATCH CONTROLLER & BABAK INDICATOR
                          SizedBox(
                            width: 190,
                            child: _buildCenterMatchInfo(currentBabak),
                          ),

                          const SizedBox(width: 12),

                          // SUDUT MERAH (RIGHT)
                          Expanded(
                            flex: 5,
                            child: _buildAthleteCard(
                              atlit: _atlit2,
                              isRed: true,
                              score: atlit2Score,
                              logs: atlit2Logs,
                              binaan: finalBinaanMerah,
                              teguran: finalTeguranMerah,
                              pembinaan: finalPembinaanMerah,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 3. Footer Bar
                  _buildFooter(),
                ],
              ),
            ),

            // ── 4. Dewan Verification Anonymous Overlay ──
            if (_verifikasiActive) _buildVerifikasiOverlay(),

            // ── 5. Winner Celebration Modal (Akhir Pertandingan) ──
            if (_showWinnerModal)
              Positioned.fill(
                child: _buildWinnerModal(atlit1Score, atlit2Score),
              ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ── 1. HEADER BAR ──
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF090D16).withValues(alpha: 0.95),
        border: const Border(
          bottom: BorderSide(color: Color(0xFF1E293B), width: 1.2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Event Title & Arena
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: const Icon(
                  Icons.shield,
                  color: Color(0xFF818CF8),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _gelanggang?.event?.namaEvent?.toUpperCase() ??
                        'KEJUARAAN PENCAK SILAT 2026',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    'Arena ${_gelanggang?.keterangan ?? _gelanggang?.kodeGelanggang ?? '-'}',
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Center: Match Category Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF6366F1).withValues(alpha: 0.8),
                width: 1.2,
              ),
            ),
            child: Text(
              _activeJadwal?.nomorPartai != null
                  ? 'PARTAI #${_activeJadwal!.nomorPartai}${_activeJadwal!.kelas?.namaKelas != null ? " • ${_activeJadwal!.kelas!.namaKelas}" : (_gelanggang?.keterangan != null ? " • ${_gelanggang!.keterangan}" : "")}'
                      .toUpperCase()
                  : (_gelanggang?.keterangan?.toUpperCase() ??
                      'TANDING KELAS DEWASA'),
              style: const TextStyle(
                color: Color(0xFFA5B4FC),
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),

          // Right: Connection Status & Live Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color:
                      (_isConnected
                              ? const Color(0xFF065F46)
                              : const Color(0xFF881337))
                          .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _isConnected
                        ? const Color(0xFF10B981)
                        : const Color(0xFFE11D48),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isConnected
                            ? const Color(0xFF34D399)
                            : const Color(0xFFFB7185),
                        boxShadow: [
                          BoxShadow(
                            color:
                                (_isConnected
                                        ? const Color(0xFF34D399)
                                        : const Color(0xFFFB7185))
                                    .withValues(alpha: 0.6),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isConnected ? 'LIVE SCOREBOARD' : 'OFFLINE',
                      style: TextStyle(
                        color: _isConnected
                            ? const Color(0xFF34D399)
                            : const Color(0xFFFB7185),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // Back / Exit Button
              GestureDetector(
                onTap: () {
                  Navigator.of(context).pushReplacementNamed('/home');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    children: const [
                      Icon(
                        Icons.arrow_back,
                        color: Color(0xFF94A3B8),
                        size: 13,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Keluar',
                        style: TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
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
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ── 2. CENTER MATCH INFO (TIMER + VERTICAL ROUND/BABAK INDICATOR) ──
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildCenterMatchInfo(String currentBabak) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF090D16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1E293B), width: 1.8),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── App/Event Logo Above Timer Box (Full Width) ──
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/img/logo-small.webp',
                width: double.infinity,
                fit: BoxFit.fitWidth,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            ),
          ),

          // ── Big Digital Timer Box ──
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF334155), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _isTimerRunning
                        ? const Color(0xFF065F46)
                        : (_gelanggang?.statusTanding == 'berlangsung'
                              ? const Color(0xFF78350F)
                              : const Color(0xFF1E293B)),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    _isTimerRunning
                        ? 'TIMER BERJALAN'
                        : (_gelanggang?.statusTanding == 'berlangsung'
                              ? 'WAKTU DIJEDA'
                              : 'STANDBY'),
                    style: TextStyle(
                      color: _isTimerRunning
                          ? const Color(0xFF34D399)
                          : (_gelanggang?.statusTanding == 'berlangsung'
                                ? const Color(0xFFFBBF24)
                                : const Color(0xFF94A3B8)),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formattedTimer,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ── Round / Babak Section Header ──
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1B4B).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'RONDE PERTANDINGAN',
              style: TextStyle(
                color: Color(0xFFA78BFA),
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 8),

          // ── Babak 1, Babak 2, Babak 3 Stack ──
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
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            roundNumber,
            style: TextStyle(
              color: isActive ? Colors.white : const Color(0xFF94A3B8),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (isActive) ...[
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
  // ── 3. ATHLETE CORNER CARDS (SUDUT BIRU & SUDUT MERAH) ──
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildAthleteCard({
    required Peserta? atlit,
    required bool isRed,
    required int score,
    required List<Nilai> logs,
    required int binaan,
    required int teguran,
    required int pembinaan,
  }) {
    final gradientColors = isRed
        ? const [
            Color(0xFFE11D48), // Bright red
            Color(0xFFBE123C), // Deep crimson
            Color(0xFF4C0519), // Dark burgundy
            Color(0xFF1C0208), // Edge shadow
          ]
        : const [
            Color(0xFF0284C7), // Bright blue
            Color(0xFF0369A1), // Royal blue
            Color(0xFF07274E), // Dark navy
            Color(0xFF051329), // Edge shadow
          ];
    final gradientBegin = isRed ? Alignment.centerRight : Alignment.centerLeft;
    final gradientEnd = isRed ? Alignment.centerLeft : Alignment.centerRight;
    final borderColor = isRed
        ? const Color(0xFFFB7185)
        : const Color(0xFF38BDF8);
    final glowColor = isRed ? const Color(0xFFE11D48) : const Color(0xFF0284C7);
    final cornerTitle = isRed ? 'SUDUT MERAH' : 'SUDUT BIRU';
    final photoUrl =
        _resolveImageUrl(atlit?.actionFoto) ?? _resolveImageUrl(atlit?.pasFoto);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: gradientBegin,
          end: gradientEnd,
          colors: gradientColors,
          stops: const [0.0, 0.35, 0.75, 1.0],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 2.2),
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
          // Faint Background Watermark
          Positioned(
            left: isRed ? null : 16,
            right: isRed ? 16 : null,
            top: 4,
            child: Text(
              isRed ? 'MERAH' : 'BIRU',
              style: TextStyle(
                fontSize: 92,
                fontWeight: FontWeight.w900,
                color: Colors.white.withValues(alpha: 0.12),
                letterSpacing: 6,
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header: Corner Name + Athlete Tag ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: borderColor.withValues(alpha: 0.8),
                            ),
                          ),
                          child: Text(
                            cornerTitle,
                            style: TextStyle(
                              color: isRed
                                  ? const Color(0xFFFB7185)
                                  : const Color(0xFF38BDF8),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        if (_dsqSudut == (isRed ? 'merah' : 'biru')) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE11D48),
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFFE11D48,
                                  ).withValues(alpha: 0.7),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.gavel,
                                  color: Colors.white,
                                  size: 12,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'DISKUALIFIKASI',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        atlit?.perguruan?.toUpperCase() ?? 'IPSI TANDING',
                        style: TextStyle(
                          color: isRed
                              ? const Color(0xFFFECDD3)
                              : const Color(0xFFBAE6FD),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // ── Athlete Header Box (Name & Contingent Full Width) ──
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.38),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isRed
                              ? const Color(0xFFE11D48).withValues(alpha: 0.3)
                              : const Color(0xFF0284C7).withValues(alpha: 0.3),
                          border: Border.all(
                            color: borderColor.withValues(alpha: 0.6),
                          ),
                        ),
                        child: Icon(
                          Icons.sports_martial_arts,
                          color: isRed
                              ? const Color(0xFFFB7185)
                              : const Color(0xFF38BDF8),
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              atlit?.namaLengkap?.toUpperCase() ??
                                  'BELUM ADA ATLET',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              atlit?.kontingen?.toUpperCase() ?? 'KONTINGEN -',
                              style: TextStyle(
                                color: isRed
                                    ? const Color(0xFFFECDD3)
                                    : const Color(0xFFBAE6FD),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // ── KP Sanctions Status Row (Binaan, Teguran, Pembinaan) ──
                _buildKpSanctionsBar(binaan, teguran, pembinaan, isRed),

                const SizedBox(height: 8),

                // ── Bagian Atas: Side-by-Side Total Score & Athlete Photo (Proporsi Lebih Tinggi) ──
                // Sudut Biru: Score on Left, Photo on Right
                // Sudut Merah: Photo on Left, Score on Right
                Expanded(
                  flex: 6,
                  child: _buildScoreAndPhotoSection(
                    atlit: atlit,
                    isRed: isRed,
                    score: score,
                    photoUrl: photoUrl,
                    borderColor: borderColor,
                    glowColor: glowColor,
                  ),
                ),

                const SizedBox(height: 8),

                // ── Bagian Bawah: Score History Box (Tinggi Sedikit Lebih Ringkas) ──
                Expanded(flex: 4, child: _buildScoreHistoryList(logs, isRed)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Side-by-Side Score & Large Photo Box
  Widget _buildScoreAndPhotoSection({
    required Peserta? atlit,
    required bool isRed,
    required int score,
    required String? photoUrl,
    required Color borderColor,
    required Color glowColor,
  }) {
    final scoreWidget = Expanded(
      flex: 5,
      child: Container(
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: glowColor.withValues(alpha: 0.45),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Text(
                '$score',
                style: TextStyle(
                  fontSize: 110,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                  color: Colors.white,
                  shadows: [
                    Shadow(color: glowColor, blurRadius: 36),
                    const Shadow(color: Colors.black54, blurRadius: 10),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final photoWidget = Expanded(
      flex: 4,
      child: Container(
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: borderColor.withValues(alpha: 0.9),
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(color: glowColor.withValues(alpha: 0.3), blurRadius: 16),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: photoUrl != null
            ? Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, stack) =>
                    _buildLargePhotoPlaceholder(atlit, isRed),
              )
            : _buildLargePhotoPlaceholder(atlit, isRed),
      ),
    );

    return Row(
      children: isRed
          ? [
              // Sudut Merah: Photo on Left, Score on Right
              photoWidget,
              const SizedBox(width: 8),
              scoreWidget,
            ]
          : [
              // Sudut Biru: Score on Left, Photo on Right
              scoreWidget,
              const SizedBox(width: 8),
              photoWidget,
            ],
    );
  }

  Widget _buildLargePhotoPlaceholder(Peserta? atlit, bool isRed) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isRed
              ? const [Color(0xFF3B0714), Color(0xFF1C0208)]
              : const [Color(0xFF072448), Color(0xFF031024)],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.person,
            size: 78,
            color: Colors.white.withValues(alpha: 0.12),
          ),
          Center(
            child: Text(
              atlit?.initials ?? '?',
              style: TextStyle(
                color: isRed
                    ? const Color(0xFFFB7185)
                    : const Color(0xFF38BDF8),
                fontSize: 36,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── KP Sanctions Pill Bar ──
  Widget _buildKpSanctionsBar(
    int binaan,
    int teguran,
    int pembinaan,
    bool isRed,
  ) {
    return Row(
      children: [
        Expanded(
          child: _buildSanctionPill(
            'BINAAN',
            binaan,
            2,
            const Color(0xFF6366F1),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildSanctionPill(
            'TEGURAN',
            teguran,
            2,
            const Color(0xFFEA580C),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildSanctionPill(
            'PERINGATAN',
            pembinaan,
            2,
            const Color(0xFFE11D48),
          ),
        ),
      ],
    );
  }

  Widget _buildSanctionPill(
    String label,
    int current,
    int max,
    Color themeColor,
  ) {
    final isActive = current > 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: isActive
            ? themeColor.withValues(alpha: 0.25)
            : const Color(0xFF0B111E).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? themeColor : const Color(0xFF1E293B),
          width: isActive ? 2.0 : 1.2,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: themeColor.withValues(alpha: 0.45),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── TULISAN KETERANGAN ──
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : const Color(0xFF94A3B8),
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 6),

          // ── LAMPU INDIKATOR JAUH LEBIH BESAR (32px) DI BAWAH TULISAN ──
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(max, (index) {
                final isLit = index < current;
                return Container(
                  margin: EdgeInsets.only(left: index > 0 ? 10.0 : 0),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isLit ? themeColor : const Color(0xFF0F172A),
                    border: Border.all(
                      color: isLit ? Colors.white : const Color(0xFF334155),
                      width: isLit ? 2.4 : 1.5,
                    ),
                    boxShadow: isLit
                        ? [
                            BoxShadow(
                              color: themeColor.withValues(alpha: 0.95),
                              blurRadius: 14,
                              spreadRadius: 2.5,
                            ),
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.8),
                              blurRadius: 6,
                              spreadRadius: 1.0,
                            ),
                          ]
                        : null,
                  ),
                  child: isLit
                      ? Center(
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : null,
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ── Color-Coded Vertical Score History List (Identical to Dewan) ──
  Widget _buildScoreHistoryList(List<Nilai> logs, bool isRed) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'RIWAYAT POIN TERAKHIR',
                style: TextStyle(
                  color: isRed
                      ? const Color(0xFFFDA4AF)
                      : const Color(0xFF7DD3FC),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
              Text(
                '${logs.length}/5 TERBARU',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: logs.isEmpty
                ? const Center(
                    child: Text(
                      'Belum ada riwayat poin',
                      style: TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: logs.length,
                    separatorBuilder: (ctx, idx) => const SizedBox(height: 3),
                    itemBuilder: (ctx, idx) {
                      final n = logs[idx];
                      return _buildLogRowItem(n);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogRowItem(Nilai n) {
    final jenis = (n.jenis ?? '').toLowerCase();
    final jumlah = n.jumlah ?? 0;

    Color bgColor;
    Color borderColor;
    Color textColor;
    IconData icon;

    if (jenis == 'pukulan' || jumlah == 1) {
      bgColor = const Color(0xFF0C4A6E).withValues(alpha: 0.45);
      borderColor = const Color(0xFF0284C7);
      textColor = const Color(0xFF7DD3FC);
      icon = Icons.sports_mma_rounded;
    } else if (jenis == 'tendangan' || jumlah == 2) {
      bgColor = const Color(0xFF064E3B).withValues(alpha: 0.45);
      borderColor = const Color(0xFF10B981);
      textColor = const Color(0xFF6EE7B7);
      icon = Icons.sports_martial_arts_rounded;
    } else if (jenis == 'batal_jatuhan' ||
        jumlah == -3 ||
        (jenis == 'jatuhan' && jumlah < 0)) {
      bgColor = const Color(0xFF27272A).withValues(alpha: 0.6);
      borderColor = const Color(0xFF71717A);
      textColor = const Color(0xFFD4D4D8);
      icon = Icons.replay_rounded;
    } else if (jenis == 'jatuhan' || jumlah == 3) {
      bgColor = const Color(0xFF78350F).withValues(alpha: 0.5);
      borderColor = const Color(0xFFF59E0B);
      textColor = const Color(0xFFFDE68A);
      icon = Icons.verified_user_rounded;
    } else if (jenis == 'binaan' || (jumlah == 0 && jenis.isNotEmpty)) {
      bgColor = const Color(0xFF1E1B4B).withValues(alpha: 0.5);
      borderColor = const Color(0xFF6366F1);
      textColor = const Color(0xFFA5B4FC);
      icon = Icons.info_outline;
    } else if (jenis == 'teguran' || jumlah == -1 || jumlah == -2) {
      bgColor = const Color(0xFF7C2D12).withValues(alpha: 0.45);
      borderColor = const Color(0xFFEA580C);
      textColor = const Color(0xFFFDBA74);
      icon = Icons.warning_amber_rounded;
    } else if (jenis == 'pembinaan' ||
        jenis == 'peringatan' ||
        jumlah == -5 ||
        jumlah == -10) {
      bgColor = const Color(0xFF881337).withValues(alpha: 0.5);
      borderColor = const Color(0xFFE11D48);
      textColor = const Color(0xFFFECDD3);
      icon = Icons.report_problem_rounded;
    } else if (jenis == 'diskualifikasi') {
      bgColor = const Color(0xFF581C87).withValues(alpha: 0.55);
      borderColor = const Color(0xFFA855F7);
      textColor = const Color(0xFFE9D5FF);
      icon = Icons.gavel_rounded;
    } else {
      bgColor = const Color(0xFF1E293B).withValues(alpha: 0.5);
      borderColor = const Color(0xFF475569);
      textColor = const Color(0xFFE2E8F0);
      icon = Icons.circle;
    }

    final String babakStr = (n.babak != null &&
            n.babak!.isNotEmpty &&
            n.babak != 'null')
        ? n.babak!
        : _resolveCurrentBabak();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 1.1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: textColor),
              const SizedBox(width: 8),
              Text(
                n.poinLabel,
                style: TextStyle(
                  color: textColor,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: borderColor.withValues(alpha: 0.45),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  'Babak $babakStr',
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.95),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (n.menitKe != null && n.menitKe!.isNotEmpty) ...[
                const SizedBox(width: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: borderColor.withValues(alpha: 0.4),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    n.menitKe!,
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.9),
                      fontSize: 11.5,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ── 4. DEWAN VERIFICATION ANONYMOUS REAL-TIME BROADCAST OVERLAY ──
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildVerifikasiOverlay() {
    final isPelanggaran = _verifikasiJenis.toLowerCase() == 'pelanggaran';
    final jenisTitle = _verifikasiJenis.toUpperCase();
    final isFinalResult = _verifikasiHasil != null;

    final votes = _verifikasiVotes.values.where((v) => v != null).toList();
    final countBiru = votes.where((v) => v == 'biru').length;
    final countMerah = votes.where((v) => v == 'merah').length;
    final countInvalid = votes
        .where((v) => v == 'invalid' || v == 'tidak_sah' || v == 'batal')
        .length;
    final totalMasuk = votes.length;

    return Container(
      color: Colors.black.withValues(alpha: 0.92),
      child: Center(
        child: Container(
          width: 820,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF090D16),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isFinalResult
                  ? (_verifikasiHasil == 'biru'
                      ? const Color(0xFF0284C7)
                      : _verifikasiHasil == 'merah'
                          ? const Color(0xFFE11D48)
                          : const Color(0xFFD97706))
                  : (isPelanggaran
                      ? const Color(0xFFD97706)
                      : const Color(0xFF0284C7)),
              width: 3.0,
            ),
            boxShadow: [
              BoxShadow(
                color: isFinalResult
                    ? (_verifikasiHasil == 'biru'
                        ? const Color(0xFF0284C7)
                        : _verifikasiHasil == 'merah'
                            ? const Color(0xFFE11D48)
                            : const Color(0xFFD97706))
                        .withValues(alpha: 0.55)
                    : (isPelanggaran
                            ? const Color(0xFFD97706)
                            : const Color(0xFF0284C7))
                        .withValues(alpha: 0.4),
                blurRadius: 40,
                spreadRadius: 6,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 1. LOADING STATE (Sebelum 3 Juri Selesai Voting) ──
              if (!isFinalResult) ...[
                const SizedBox(height: 12),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: CircularProgressIndicator(
                        strokeWidth: 4.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isPelanggaran
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF38BDF8),
                        ),
                      ),
                    ),
                    Icon(
                      isPelanggaran
                          ? Icons.gavel_rounded
                          : Icons.sports_martial_arts_rounded,
                      color: isPelanggaran
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFF38BDF8),
                      size: 38,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'VERIFIKASI $jenisTitle SEDANG BERLANGSUNG',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Sedang Menunggu Keputusan Juri ($totalMasuk / 3 Juri Masuk)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),

                // ── TAMPILAN JUMLAH VOTE JURI (RINGKASAN HASIL VOTE) ──
                _buildVoteTallyCards(
                  countBiru: countBiru,
                  countMerah: countMerah,
                  countInvalid: countInvalid,
                  isPelanggaran: isPelanggaran,
                ),
                const SizedBox(height: 12),
              ]
              // ── 2. FINAL RESULT STATE (Hanya Menampilkan 1 Hasil Akhir Saja) ──
              else ...[
                // Overlay Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (_verifikasiHasil == 'biru'
                                ? const Color(0xFF0284C7)
                                : _verifikasiHasil == 'merah'
                                    ? const Color(0xFFE11D48)
                                    : const Color(0xFFD97706))
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _verifikasiHasil == 'invalid'
                            ? Icons.cancel_outlined
                            : (_verifikasiHasil == 'biru'
                                ? (isPelanggaran
                                    ? Icons.gavel_rounded
                                    : Icons.sports_martial_arts)
                                : (isPelanggaran
                                    ? Icons.gavel_rounded
                                    : Icons.sports_martial_arts)),
                        color: _verifikasiHasil == 'biru'
                            ? const Color(0xFF38BDF8)
                            : _verifikasiHasil == 'merah'
                                ? const Color(0xFFFB7185)
                                : const Color(0xFFFBBF24),
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'HASIL VERIFIKASI $jenisTitle',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const Text(
                          'Keputusan Akhir Konsensus Juri Pertandingan',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                const Divider(color: Color(0xFF1E293B), height: 1),
                const SizedBox(height: 20),

                // Satu Hasil Akhir Saja (Single Final Result Card) dengan Summary Vote
                _buildSingleFinalResultCard(
                  hasil: _verifikasiHasil!,
                  isPelanggaran: isPelanggaran,
                  countBiru: countBiru,
                  countMerah: countMerah,
                  countInvalid: countInvalid,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVoteTallyCards({
    required int countBiru,
    required int countMerah,
    required int countInvalid,
    required bool isPelanggaran,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 1. Sudut Biru Card (Kiri)
        Expanded(
          child: _buildVoteCountCard(
            label: 'SUDUT BIRU',
            count: countBiru,
            accentColor: const Color(0xFF0284C7),
            lightColor: const Color(0xFF38BDF8),
            icon: Icons.shield_rounded,
          ),
        ),
        const SizedBox(width: 14),

        // 2. Invalid / Tidak Sah Card (Tengah)
        Expanded(
          child: _buildVoteCountCard(
            label: isPelanggaran ? 'TIDAK ADA PELANGGARAN' : 'TIDAK SAH / INVALID',
            count: countInvalid,
            accentColor: const Color(0xFFD97706),
            lightColor: const Color(0xFFFBBF24),
            icon: isPelanggaran ? Icons.verified_user_rounded : Icons.cancel_outlined,
          ),
        ),
        const SizedBox(width: 14),

        // 3. Sudut Merah Card (Kanan)
        Expanded(
          child: _buildVoteCountCard(
            label: 'SUDUT MERAH',
            count: countMerah,
            accentColor: const Color(0xFFE11D48),
            lightColor: const Color(0xFFFB7185),
            icon: Icons.shield_rounded,
          ),
        ),
      ],
    );
  }

  Widget _buildVoteCountCard({
    required String label,
    required int count,
    required Color accentColor,
    required Color lightColor,
    required IconData icon,
  }) {
    final hasVotes = count > 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: hasVotes
            ? accentColor.withValues(alpha: 0.28)
            : const Color(0xFF1E293B).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasVotes ? lightColor : const Color(0xFF334155),
          width: hasVotes ? 2.5 : 1.4,
        ),
        boxShadow: hasVotes
            ? [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.45),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: lightColor, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: hasVotes ? Colors.white : const Color(0xFF94A3B8),
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  color: hasVotes ? lightColor : const Color(0xFF64748B),
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'JURI',
                style: TextStyle(
                  color: hasVotes ? Colors.white70 : const Color(0xFF64748B),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSingleFinalResultCard({
    required String hasil,
    required bool isPelanggaran,
    required int countBiru,
    required int countMerah,
    required int countInvalid,
  }) {
    final isBiru = hasil == 'biru';
    final isMerah = hasil == 'merah';
    final isInvalid = !isBiru && !isMerah;

    final primaryColor = isBiru
        ? const Color(0xFF0284C7)
        : isMerah
            ? const Color(0xFFE11D48)
            : const Color(0xFFD97706);

    final borderColor = isBiru
        ? const Color(0xFF38BDF8)
        : isMerah
            ? const Color(0xFFFB7185)
            : const Color(0xFFF59E0B);

    final glowColor = isBiru
        ? const Color(0xFF0284C7)
        : isMerah
            ? const Color(0xFFE11D48)
            : const Color(0xFFD97706);

    final title = isInvalid
        ? (isPelanggaran ? 'TIDAK ADA PELANGGARAN' : 'JATUHAN TIDAK SAH')
        : (isPelanggaran
            ? (isBiru ? 'PELANGGARAN SUDUT BIRU' : 'PELANGGARAN SUDUT MERAH')
            : (isBiru ? 'JATUHAN SAH SUDUT BIRU' : 'JATUHAN SAH SUDUT MERAH'));

    final athleteName = isBiru
        ? _atlit1?.namaLengkap
        : isMerah
            ? _atlit2?.namaLengkap
            : null;

    final kontingen = isBiru
        ? _atlit1?.kontingen
        : isMerah
            ? _atlit2?.kontingen
            : null;

    final icon = isInvalid
        ? Icons.cancel_outlined
        : (isPelanggaran ? Icons.gavel_rounded : Icons.sports_martial_arts);

    final statusTag = isInvalid
        ? (isPelanggaran
            ? 'KEPUTUSAN: TIDAK ADA PELANGGARAN'
            : 'KEPUTUSAN: TIDAK SAH (0 POIN)')
        : (isPelanggaran
            ? 'KEPUTUSAN: PELANGGARAN'
            : 'KEPUTUSAN: SAH (+3 POIN)');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor,
          width: 3.0,
        ),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.5),
            blurRadius: 36,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon lingkaran
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primaryColor.withValues(alpha: 0.4),
              border: Border.all(color: borderColor, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: glowColor.withValues(alpha: 0.45),
                  blurRadius: 18,
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 44,
            ),
          ),
          const SizedBox(height: 14),

          // Judul Keputusan
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),

          // Nama Atlit & Kontingen
          if (athleteName != null && athleteName.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              athleteName.toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: borderColor,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            if (kontingen != null && kontingen.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                kontingen.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ] else if (isInvalid) ...[
            const SizedBox(height: 6),
            Text(
              isPelanggaran
                  ? 'Tidak ditemukan unsur pelanggaran oleh juri'
                  : 'Teknik jatuhan dinyatakan tidak sah atau tidak memenuhi kriteria',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFCBD5E1),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Tag Status Poin / Keputusan
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: borderColor.withValues(alpha: 0.6),
                width: 1.5,
              ),
            ),
            child: Text(
              statusTag,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
            ),
          ),

          const SizedBox(height: 16),
          const Divider(color: Color(0xFF1E293B), height: 1),
          const SizedBox(height: 12),

          // Tampilan Perolehan Vote Juri
          _buildVoteTallyCards(
            countBiru: countBiru,
            countMerah: countMerah,
            countInvalid: countInvalid,
            isPelanggaran: isPelanggaran,
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ── 5a. SKOR SERI — PERBANDINGAN STATISTIK (MENUNGGU KEPUTUSAN DEWAN) ──
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildSeriStatsModal() {
    final nilaiList = ref.watch(nilaiListProvider);
    final a1Id =
        _atlit1?.documentId ?? _atlit1?.id?.toString() ?? _gelanggang?.atlit1Id ?? '';
    final a2Id =
        _atlit2?.documentId ?? _atlit2?.id?.toString() ?? _gelanggang?.atlit2Id ?? '';
    final active = _resolveActiveJadwal();
    final jDocId = active?.documentId ?? '';
    final jId = active?.id?.toString() ?? '';
    final biru = computeMatchStats(
      nilaiList,
      a1Id,
      sudut: 'biru',
      jadwalDocId: jDocId,
      jadwalId: jId,
    );
    final merah = computeMatchStats(
      nilaiList,
      a2Id,
      sudut: 'merah',
      jadwalDocId: jDocId,
      jadwalId: jId,
    );

    const biruColor = Color(0xFF38BDF8);
    const merahColor = Color(0xFFFB7185);
    const gold = Color(0xFFFBBF24);

    Widget athleteHeader(Peserta? atlit, bool isRed) {
      final color = isRed ? merahColor : biruColor;
      return Column(
        children: [
          Text(
            isRed ? 'SUDUT MERAH' : 'SUDUT BIRU',
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            (atlit?.namaLengkap ?? '-').toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            (atlit?.kontingen ?? '-').toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color.withValues(alpha: 0.85),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    Widget statRow(String label, IconData icon, int b, int m,
        {bool lowerIsBetter = false}) {
      final biruBetter = lowerIsBetter ? b < m : b > m;
      final merahBetter = lowerIsBetter ? m < b : m > b;

      Widget value(int v, bool better, Color color) => Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: better
                    ? color.withValues(alpha: 0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: better
                      ? color.withValues(alpha: 0.7)
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Text(
                '$v',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: better ? color : Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
            ),
          );

      return Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF1E293B))),
        ),
        child: Row(
          children: [
            value(b, biruBetter, biruColor),
            SizedBox(
              width: 220,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: const Color(0xFF94A3B8), size: 22),
                  const SizedBox(width: 8),
                  Text(
                    label.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            value(m, merahBetter, merahColor),
          ],
        ),
      );
    }

    return Container(
      color: Colors.black.withValues(alpha: 0.92),
      child: Center(
        child: Container(
          width: 900,
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
          decoration: BoxDecoration(
            color: const Color(0xFF090D16),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: gold, width: 3),
            boxShadow: [
              BoxShadow(
                color: gold.withValues(alpha: 0.35),
                blurRadius: 40,
                spreadRadius: 4,
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.balance_rounded, color: gold, size: 44),
                const SizedBox(height: 4),
                const Text(
                  'SKOR SERI',
                  style: TextStyle(
                    color: gold,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF78350F).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'MENUNGGU KEPUTUSAN DEWAN PERTANDINGAN',
                    style: TextStyle(
                      color: Color(0xFFFDE68A),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: athleteHeader(_atlit1, false)),
                    const SizedBox(
                      width: 220,
                      child: Center(
                        child: Text(
                          'VS',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    Expanded(child: athleteHeader(_atlit2, true)),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B1220),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: Column(
                    children: [
                      statRow('Nilai', Icons.scoreboard_rounded, biru.nilai,
                          merah.nilai),
                      statRow('Pukulan', Icons.sports_mma_rounded,
                          biru.pukulan, merah.pukulan),
                      statRow('Tendangan', Icons.sports_martial_arts_rounded,
                          biru.tendangan, merah.tendangan),
                      statRow('Jatuhan', Icons.verified_user_rounded,
                          biru.jatuhan, merah.jatuhan),
                      statRow('Binaan', Icons.info_outline_rounded,
                          biru.binaan, merah.binaan,
                          lowerIsBetter: true),
                      statRow('Teguran', Icons.warning_amber_rounded,
                          biru.teguran, merah.teguran,
                          lowerIsBetter: true),
                      statRow('Peringatan', Icons.gpp_maybe_rounded,
                          biru.peringatan, merah.peringatan,
                          lowerIsBetter: true),
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

  // ══════════════════════════════════════════════════════════════════════════
  // ── 5. WINNER CELEBRATION MODAL (AKHIR PERTANDINGAN) ──
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildWinnerModal(int biruScore, int merahScore) {
    final isDsq = _dsqSudut != null && _dsqSudut!.isNotEmpty;
    final isDewanDecision =
        !isDsq && biruScore == merahScore && _dewanPemenang != null;

    // Skor seri & Dewan belum memutuskan → tampilkan perbandingan statistik
    if (!isDsq && biruScore == merahScore && _dewanPemenang == null) {
      return _buildSeriStatsModal();
    }

    final isBiruWin = isDsq
        ? (_dsqSudut == 'merah')
        : isDewanDecision
        ? _dewanPemenang == 'biru'
        : (biruScore > merahScore);
    final isMerahWin = isDsq
        ? (_dsqSudut == 'biru')
        : isDewanDecision
        ? _dewanPemenang == 'merah'
        : (merahScore > biruScore);

    final winnerColor = isBiruWin
        ? const Color(0xFF0284C7)
        : isMerahWin
        ? const Color(0xFFE11D48)
        : const Color(0xFFD97706);
    final winnerBorder = isBiruWin
        ? const Color(0xFF38BDF8)
        : isMerahWin
        ? const Color(0xFFFB7185)
        : const Color(0xFFFBBF24);
    final winnerTitle = isBiruWin
        ? 'SUDUT BIRU'
        : isMerahWin
        ? 'SUDUT MERAH'
        : 'SERI / DRAW';
    final jadwals = ref.watch(jadwalListProvider).valueOrNull ?? [];
    final activeJadwal = _resolveActiveJadwal(jadwals);

    final winnerAtlit = isBiruWin
        ? (_atlit1 ?? _activeJadwal?.biruPeserta ?? activeJadwal?.biruPeserta)
        : isMerahWin
        ? (_atlit2 ?? _activeJadwal?.merahPeserta ?? activeJadwal?.merahPeserta)
        : null;

    final photoUrl =
        _resolveImageUrl(winnerAtlit?.actionFoto) ??
        _resolveImageUrl(winnerAtlit?.pasFoto);

    final biruName =
        _atlit1?.namaLengkap ??
        _activeJadwal?.biruPeserta?.namaLengkap ??
        activeJadwal?.biruPeserta?.namaLengkap ??
        'Peserta Sudut Biru';
    final biruKontingen =
        _atlit1?.kontingen ??
        _activeJadwal?.biruPeserta?.kontingen ??
        activeJadwal?.biruPeserta?.kontingen ??
        '-';

    final merahName =
        _atlit2?.namaLengkap ??
        _activeJadwal?.merahPeserta?.namaLengkap ??
        activeJadwal?.merahPeserta?.namaLengkap ??
        'Peserta Sudut Merah';
    final merahKontingen =
        _atlit2?.kontingen ??
        _activeJadwal?.merahPeserta?.kontingen ??
        activeJadwal?.merahPeserta?.kontingen ??
        '-';

    final winnerName = isBiruWin
        ? biruName
        : isMerahWin
        ? merahName
        : 'Kedua Atlet Mendapat Skor Sama';
    final winnerKontingen = isBiruWin
        ? biruKontingen
        : isMerahWin
        ? merahKontingen
        : '-';

    return Container(
      color: Colors.black.withValues(alpha: 0.94),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: photoUrl != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // ── 1. HERO ATHLETE PHOTO (DILUAR KOTAK INFORMASI & NILAI) ──
                    _buildWinnerHeroPhoto(
                      photoUrl: photoUrl,
                      winnerName: winnerName,
                      winnerKontingen: winnerKontingen,
                      winnerTitle: winnerTitle,
                      winnerColor: winnerColor,
                      winnerBorder: winnerBorder,
                    ),

                    const SizedBox(width: 28),

                    // ── 2. KOTAK INFORMASI ATLIT & NILAI ──
                    _buildWinnerInfoCard(
                      winnerTitle: winnerTitle,
                      winnerColor: winnerColor,
                      winnerBorder: winnerBorder,
                      isDewanDecision: isDewanDecision,
                      isDsq: isDsq,
                      winnerName: winnerName,
                      winnerKontingen: winnerKontingen,
                      biruScore: biruScore,
                      merahScore: merahScore,
                      isBiruWin: isBiruWin,
                      isMerahWin: isMerahWin,
                      width: 580,
                    ),
                  ],
                )
              : _buildWinnerInfoCard(
                  winnerTitle: winnerTitle,
                  winnerColor: winnerColor,
                  winnerBorder: winnerBorder,
                  isDewanDecision: isDewanDecision,
                  isDsq: isDsq,
                  winnerName: winnerName,
                  winnerKontingen: winnerKontingen,
                  biruScore: biruScore,
                  merahScore: merahScore,
                  isBiruWin: isBiruWin,
                  isMerahWin: isMerahWin,
                  width: 800,
                ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ── HERO WINNER ATHLETE PHOTO (FOKUS UTAMA DI MONITORING) ──
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildWinnerHeroPhoto({
    required String photoUrl,
    required String winnerName,
    required String winnerKontingen,
    required String winnerTitle,
    required Color winnerColor,
    required Color winnerBorder,
  }) {
    return Container(
      width: 350,
      height: 510,
      decoration: BoxDecoration(
        color: const Color(0xFF090D16),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: winnerBorder, width: 3.5),
        boxShadow: [
          BoxShadow(
            color: winnerColor.withValues(alpha: 0.65),
            blurRadius: 42,
            spreadRadius: 5,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.8),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Athlete Image ──
          Image.network(
            photoUrl,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (ctx, err, stack) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_rounded,
                    size: 110,
                    color: winnerBorder.withValues(alpha: 0.7),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      winnerName.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            loadingBuilder: (ctx, child, progress) {
              if (progress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  color: winnerBorder,
                  strokeWidth: 3,
                ),
              );
            },
          ),

          // ── Top Gradient Overlay ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 80,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom Gradient Overlay for Athlete Name & Kontingen ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.8),
                    Colors.black.withValues(alpha: 0.95),
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    winnerName.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      shadows: [
                        Shadow(
                          color: Colors.black,
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    winnerKontingen.toUpperCase(),
                    style: TextStyle(
                      color: winnerBorder,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      shadows: const [
                        Shadow(
                          color: Colors.black,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),

          // ── Floating Winner Trophy Badge (Top Left) ──
          Positioned(
            top: 14,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.emoji_events_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'PEMENANG',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Floating Sudut Tag (Top Right) ──
          Positioned(
            top: 14,
            right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: winnerColor.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: winnerBorder, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                winnerTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ── KOTAK INFORMASI ATLIT DAN NILAI ──
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildWinnerInfoCard({
    required String winnerTitle,
    required Color winnerColor,
    required Color winnerBorder,
    required bool isDewanDecision,
    required bool isDsq,
    required String winnerName,
    required String winnerKontingen,
    required int biruScore,
    required int merahScore,
    required bool isBiruWin,
    required bool isMerahWin,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: const Color(0xFF090D16),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: winnerBorder, width: 3.5),
        boxShadow: [
          BoxShadow(
            color: winnerColor.withValues(alpha: 0.6),
            blurRadius: 42,
            spreadRadius: 6,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Trophy Icon
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: winnerColor.withValues(alpha: 0.25),
              shape: BoxShape.circle,
              border: Border.all(color: winnerBorder, width: 2.0),
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              color: Color(0xFFFBBF24),
              size: 46,
            ),
          ),

          const SizedBox(height: 10),

          // Title
          const Text(
            'PERTANDINGAN SELESAI',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'PEMENANG $winnerTitle',
            style: TextStyle(
              color: winnerBorder,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),

          if (isDewanDecision) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF78350F).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFBBF24)),
              ),
              child: const Text(
                'SKOR SERI • KEPUTUSAN DEWAN PERTANDINGAN',
                style: TextStyle(
                  color: Color(0xFFFDE68A),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],

          if (isDsq) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFE11D48).withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFFB7185),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.gavel,
                    color: Color(0xFFFB7185),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _dsqMessage ??
                        'MENANG DISKUALIFIKASI — Sudut ${_dsqSudut!.toUpperCase()} ${_dsqNama != null && _dsqNama!.isNotEmpty ? "($_dsqNama) " : ""}Terkena Diskualifikasi',
                    style: const TextStyle(
                      color: Color(0xFFFECDD3),
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // ── Kotak Informasi Atlit ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              vertical: 14,
              horizontal: 18,
            ),
            decoration: BoxDecoration(
              color: winnerColor.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: winnerBorder.withValues(alpha: 0.8),
                width: 1.8,
              ),
            ),
            child: Column(
              children: [
                Text(
                  winnerName.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  winnerKontingen.toUpperCase(),
                  style: TextStyle(
                    color: winnerBorder,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Kotak Nilai (Final Score Comparison) ──
          Row(
            children: [
              // Blue Corner Final Score
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(
                      0xFF0369A1,
                    ).withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF38BDF8),
                      width: isBiruWin ? 2.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'SUDUT BIRU',
                        style: TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '$biruScore',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  'VS',
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),

              // Red Corner Final Score
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(
                      0xFF9F1239,
                    ).withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFFB7185),
                      width: isMerahWin ? 2.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'SUDUT MERAH',
                        style: TextStyle(
                          color: Color(0xFFFB7185),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '$merahScore',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Auto-close Indicator
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.hourglass_bottom_rounded,
                size: 13,
                color: Color(0xFFFBBF24),
              ),
              const SizedBox(width: 6),
              Text(
                'Otomatis kembali ke standby dalam $_winnerDismissRemainingSeconds detik',
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Dismiss / Standby Button
          GestureDetector(
            onTap: _hideWinnerModal,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF475569)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'TUTUP BANNER SEKARANG',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Text(
                      '${_winnerDismissRemainingSeconds}s',
                      style: const TextStyle(
                        color: Color(0xFFFBBF24),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ── 6. FOOTER BAR ──
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF020617),
        border: const Border(top: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Sistem Scoreboard Arena Resmi IPSI © 2026',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          Row(
            children: [
              Icon(
                Icons.cell_tower,
                color: _isConnected
                    ? const Color(0xFF34D399)
                    : const Color(0xFFFB7185),
                size: 13,
              ),
              const SizedBox(width: 5),
              Text(
                _isConnected
                    ? 'Realtime Scoring Arena Sinkron'
                    : 'Koneksi Terputus',
                style: TextStyle(
                  color: _isConnected
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFFFB7185),
                  fontSize: 9.5,
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
