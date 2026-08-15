import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../models/gelanggang.dart';
import '../../models/jadwal.dart';
import '../../models/peserta.dart';
import '../../providers/gelanggang_provider.dart';
import '../../providers/jadwal_provider.dart';
import '../../providers/nilai_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/corner_card.dart';
import '../../widgets/kp_button.dart';

/// Operator Screen — Arena management console.
/// Port of Nuxt's tanding/operator/index.vue
class OperatorScreen extends ConsumerStatefulWidget {
  const OperatorScreen({super.key});

  @override
  ConsumerState<OperatorScreen> createState() => _OperatorScreenState();
}

class _OperatorScreenState extends ConsumerState<OperatorScreen> {
  bool _tandingStatus = false;
  Peserta? _atlit1;
  Peserta? _atlit2;
  Jadwal? _selectedJadwal;
  final _api = ApiService();

  @override
  void initState() {
    super.initState();
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
      // Fetch jadwal
      ref.read(jadwalListProvider.notifier).fetchJadwal(gelanggang);
    }
  }

  void _applyJadwalSelection(Jadwal j) {
    setState(() {
      _selectedJadwal = j;
      _atlit1 = j.merahPeserta;
      _atlit2 = j.biruPeserta;
    });
  }

  Future<bool> _updateGelanggang(
      String status, String at1Id, String at2Id) async {
    final gelanggang = ref.read(activeGelanggangProvider);
    if (gelanggang?.documentId == null) return false;

    try {
      await _api.updateProtect('gelanggangs', gelanggang!.documentId!, {
        'data': {
          'status_tanding': status,
          'atlit_1_id': at1Id,
          'atlit_2_id': at2Id,
        },
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _handleMulai() async {
    final a1Id = _atlit1?.documentId ?? _atlit1?.id?.toString();
    final a2Id = _atlit2?.documentId ?? _atlit2?.id?.toString();

    if (a1Id == null || a2Id == null) {
      _showSnack('Pilih partai tanding atau peserta terlebih dahulu.',
          PusakaTheme.amber500);
      return;
    }

    if (a1Id == a2Id) {
      _showSnack('Peserta Sudut Merah dan Biru tidak boleh sama.',
          PusakaTheme.amber500);
      return;
    }

    final ok = await _updateGelanggang('berlangsung', a1Id, a2Id);
    if (ok) {
      setState(() => _tandingStatus = true);
      _showSnack(
          'Pertandingan Dimulai! Partai #${_selectedJadwal?.nomorPartai ?? '-'}',
          PusakaTheme.emerald600);
    } else {
      _showSnack('Gagal memperbarui status gelanggang.', PusakaTheme.rose600);
    }
  }

  Future<void> _handleStop() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PusakaTheme.slate900,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Selesai Tanding?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: const Text(
            'Apakah Anda yakin ingin menyelesaikan pertandingan partai ini?',
            style: TextStyle(color: PusakaTheme.slate400)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal',
                style: TextStyle(color: PusakaTheme.slate400)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: PusakaTheme.rose600),
            child: const Text('Ya, Selesaikan'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _updateGelanggang('standby', '', '');
      setState(() => _tandingStatus = false);
      _showSnack(
          'Pertandingan Selesai! Gelanggang kembali ke standby.',
          PusakaTheme.emerald600);
    }
  }

  Future<void> _handleKpNilai(int nilai, Peserta? atlit) async {
    if (atlit?.documentId == null) return;
    final nilaiNotifier = ref.read(nilaiListProvider.notifier);
    final ok = await nilaiNotifier.createNilai(
      jumlah: nilai,
      pesertaDocId: atlit!.documentId!,
    );
    if (ok) {
      _showSnack('Nilai KP berhasil ditambahkan', PusakaTheme.emerald600);
    } else {
      _showSnack('Gagal menambahkan nilai KP', PusakaTheme.rose600);
    }
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    // Set gelanggang back to standby on exit
    _updateGelanggang('standby', '', '');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gelanggang = ref.watch(activeGelanggangProvider);
    final jadwalState = ref.watch(jadwalListProvider);

    ref.listen<Gelanggang?>(activeGelanggangProvider, (previous, next) {
      if (next != null) {
        ref.read(jadwalListProvider.notifier).fetchJadwal(next);
      }
    });

    // Auto-fetch if gelanggang is available but jadwal hasn't been fetched yet
    if (gelanggang != null && jadwalState is AsyncData && (jadwalState.value == null || jadwalState.value!.isEmpty) && _selectedJadwal == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(jadwalListProvider.notifier).fetchJadwal(gelanggang);
      });
    }

    return Scaffold(
      body: Container(
        decoration:
            const BoxDecoration(gradient: PusakaTheme.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              // Top Header Bar
              _buildHeader(gelanggang),

              // Main Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Partai Selector
                      _buildPartaiSelector(gelanggang, jadwalState),
                      const SizedBox(height: 16),

                      // Dual Corner Cards
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: CornerCard(
                              atlit: _atlit1,
                              isRed: true,
                              actionArea: KpButton(
                                atlit: _atlit1,
                                isRed: true,
                                onPushNilai: (v) =>
                                    _handleKpNilai(v, _atlit1),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CornerCard(
                              atlit: _atlit2,
                              isRed: false,
                              actionArea: KpButton(
                                atlit: _atlit2,
                                isRed: false,
                                onPushNilai: (v) =>
                                    _handleKpNilai(v, _atlit2),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Action Bar
                      _buildActionBar(),
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

  Widget _buildHeader(Gelanggang? gelanggang) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom:
              BorderSide(color: PusakaTheme.slate800.withValues(alpha: 0.8)),
        ),
      ),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: PusakaTheme.slate900,
                borderRadius: BorderRadius.circular(PusakaTheme.radiusMd),
                border: Border.all(color: PusakaTheme.slate800),
              ),
              child: const Icon(Icons.arrow_back,
                  color: PusakaTheme.slate400, size: 18),
            ),
          ),
          const SizedBox(width: 12),

          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: PusakaTheme.indigo950,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: PusakaTheme.indigo700),
                      ),
                      child: const Text(
                        'OPERATOR CONSOLE',
                        style: TextStyle(
                          color: PusakaTheme.indigo400,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Arena ${gelanggang?.kodeGelanggang ?? '-'}',
                      style: const TextStyle(
                        color: PusakaTheme.slate300,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  gelanggang?.event?.namaEvent ?? 'Kejuaraan Pencak Silat',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Status Badge & Refresh Button
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _tandingStatus
                      ? PusakaTheme.emerald950.withValues(alpha: 0.8)
                      : PusakaTheme.slate900.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _tandingStatus
                        ? PusakaTheme.emerald400.withValues(alpha: 0.5)
                        : PusakaTheme.slate800,
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
                        color: _tandingStatus
                            ? PusakaTheme.emerald400
                            : PusakaTheme.slate500,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _tandingStatus ? 'BERLANGSUNG' : 'STANDBY',
                      style: TextStyle(
                        color: _tandingStatus
                            ? PusakaTheme.emerald400
                            : PusakaTheme.slate400,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  if (gelanggang != null) {
                    ref.read(jadwalListProvider.notifier).fetchJadwal(gelanggang);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: PusakaTheme.slate900,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: PusakaTheme.slate800),
                  ),
                  child: const Icon(Icons.refresh, color: PusakaTheme.indigo400, size: 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPartaiSelector(Gelanggang? gelanggang, AsyncValue<List<Jadwal>> jadwalState) {
    return Container(
      decoration: PusakaTheme.cardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.format_list_numbered,
                      color: PusakaTheme.indigo400, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Pilih Partai Tanding',
                    style: TextStyle(
                      color: PusakaTheme.indigo400,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              if (_selectedJadwal != null)
                Text(
                  'PARTAI #${_selectedJadwal!.nomorPartai ?? '-'}',
                  style: const TextStyle(
                    color: PusakaTheme.amber400,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          jadwalState.when(
            data: (list) {
              if (list.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: PusakaTheme.slate950,
                    borderRadius:
                        BorderRadius.circular(PusakaTheme.radiusMd),
                    border: Border.all(color: PusakaTheme.slate700),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Belum ada jadwal pertandingan di arena ini',
                        style: TextStyle(
                          color: PusakaTheme.slate500,
                          fontSize: 11,
                        ),
                      ),
                      if (gelanggang != null)
                        GestureDetector(
                          onTap: () => ref.read(jadwalListProvider.notifier).fetchJadwal(gelanggang),
                          child: const Icon(Icons.refresh, color: PusakaTheme.indigo400, size: 16),
                        ),
                    ],
                  ),
                );
              }

              // Auto-select first jadwal if none selected
              if (_selectedJadwal == null && list.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _applyJadwalSelection(list.first);
                });
              }

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: PusakaTheme.slate950,
                  borderRadius:
                      BorderRadius.circular(PusakaTheme.radiusMd),
                  border: Border.all(color: PusakaTheme.slate700),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedJadwal != null
                        ? (_selectedJadwal!.documentId ??
                            _selectedJadwal!.id?.toString())
                        : null,
                    isExpanded: true,
                    dropdownColor: PusakaTheme.slate900,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                    items: list.map((j) {
                      final id = j.documentId ?? j.id?.toString() ?? '';
                      return DropdownMenuItem(
                        value: id,
                        child: Text(
                          'Partai #${j.nomorPartai ?? '-'} | ${j.kelas?.namaKelas ?? 'Kelas'} | M: ${j.merahPeserta?.namaLengkap ?? 'TBD'} vs B: ${j.biruPeserta?.namaLengkap ?? 'TBD'}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      final found = list.firstWhere(
                        (j) =>
                            (j.documentId ?? j.id?.toString()) == val,
                      );
                      _applyJadwalSelection(found);
                    },
                  ),
                ),
              );
            },
            loading: () => Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      color: PusakaTheme.indigo500,
                      strokeWidth: 2,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Memuat data jadwal partai...',
                    style: TextStyle(color: PusakaTheme.slate400, fontSize: 11),
                  ),
                  if (gelanggang != null) ...[
                    const SizedBox(width: 16),
                    InkWell(
                      onTap: () => ref.read(jadwalListProvider.notifier).fetchJadwal(gelanggang),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Text('Muat Ulang', style: TextStyle(color: PusakaTheme.indigo400, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Gagal memuat jadwal: $e',
                      style: const TextStyle(color: PusakaTheme.rose400, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (gelanggang != null)
                    InkWell(
                      onTap: () => ref.read(jadwalListProvider.notifier).fetchJadwal(gelanggang),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: PusakaTheme.indigo600,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Coba Lagi', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
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

  Widget _buildActionBar() {
    return Center(
      child: GestureDetector(
        onTap: _tandingStatus ? _handleStop : _handleMulai,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: _tandingStatus
                ? PusakaTheme.roseGradient
                : PusakaTheme.emeraldGradient,
            borderRadius: BorderRadius.circular(PusakaTheme.radiusLg),
            boxShadow: [
              BoxShadow(
                color: (_tandingStatus
                        ? PusakaTheme.rose600
                        : PusakaTheme.emerald600)
                    .withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _tandingStatus
                    ? Icons.stop_circle_outlined
                    : Icons.play_circle_outline,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _tandingStatus
                    ? 'SELESAIKAN PERTANDINGAN'
                    : 'MULAI PERTANDINGAN',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: PusakaTheme.slate800.withValues(alpha: 0.8)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: const [
          Text(
            'Console Operator Gelanggang © 2026 IPSI',
            style: TextStyle(
              color: PusakaTheme.slate500,
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
          Row(
            children: [
              Icon(Icons.cell_tower,
                  color: PusakaTheme.indigo400, size: 12),
              SizedBox(width: 4),
              Text(
                'WebSocket Synchronized',
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
    );
  }
}
