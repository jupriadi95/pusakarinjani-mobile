import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/theme.dart';
import '../../models/gelanggang.dart';
import '../../services/api_service.dart';
import '../../providers/gelanggang_provider.dart';
import '../../widgets/qr_scanner.dart';

/// Verify Screen — verify gelanggang arena code before accessing role console.
/// Port of Nuxt's tanding/verify.vue
class VerifyScreen extends ConsumerStatefulWidget {
  final String destination; // operator | juri | monitor

  const VerifyScreen({super.key, required this.destination});

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  String _code = '';
  bool _isLoading = false;
  bool _isScanMode = false;
  String _selectedJuriId = 'juri_1';
  final TextEditingController _pinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Force portrait orientation for verification screen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    if (widget.destination == 'juri') {
      _loadJuriId();
    }
  }

  Future<void> _loadJuriId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('saved_juri_id');
    if (saved != null && ['juri_1', 'juri_2', 'juri_3'].contains(saved)) {
      if (mounted) setState(() => _selectedJuriId = saved);
    }
  }

  Future<void> _setJuriId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_juri_id', id);
    if (mounted) setState(() => _selectedJuriId = id);
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  final _roleTitleMap = const {
    'operator': 'Dewan Pertandingan (KP)',
    'juri': 'Juri Pertandingan',
    'monitor': 'Monitoring Nilai Live',
  };

  Future<void> _verifyCode() async {
    final cleanCode = _code.trim();
    if (cleanCode.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final api = ApiService();
      final response = await api.findProtect('gelanggangs', params: {
        'filters[kode_gelanggang][\$eq]': cleanCode,
        'populate[0]': 'event',
        'populate[1]': 'event.cover',
      });

      final data = response['data'] as List?;
      if (data != null && data.isNotEmpty) {
        final gelanggang =
            Gelanggang.fromJson(data[0] as Map<String, dynamic>);

        // Save to provider
        await ref
            .read(activeGelanggangProvider.notifier)
            .setGelanggang(gelanggang);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Kode gelanggang arena berhasil diverifikasi!'),
              backgroundColor: PusakaTheme.emerald600,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );

          // Navigate to the role screen
          Navigator.of(context).pushReplacementNamed('/${widget.destination}');
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Kode gelanggang arena tidak ditemukan atau salah.'),
              backgroundColor: PusakaTheme.rose600,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Verifikasi kode gelanggang arena gagal.'),
            backgroundColor: PusakaTheme.rose600,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onQrScanned(String scannedCode) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _code = scannedCode;
        _pinController.text = scannedCode;
        _isScanMode = false;
      });
      _verifyCode();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration:
            const BoxDecoration(gradient: PusakaTheme.backgroundGradient),
        child: Stack(
          children: [
            // Ambient glow
            Positioned(
              top: MediaQuery.of(context).size.height * 0.2,
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

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Back Button
                    Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: PusakaTheme.slate900.withValues(alpha: 0.6),
                            borderRadius:
                                BorderRadius.circular(PusakaTheme.radiusMd),
                            border: Border.all(color: PusakaTheme.slate800),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.arrow_back,
                                  color: PusakaTheme.slate400, size: 16),
                              SizedBox(width: 6),
                              Text(
                                'Kembali ke Pilihan Peran',
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
                    ),

                    const Spacer(),

                    // Verification Card
                    Container(
                      constraints: const BoxConstraints(maxWidth: 420),
                      decoration: PusakaTheme.cardDecoration(
                        borderRadius: PusakaTheme.radius3xl,
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header Icon
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: PusakaTheme.indigo500.withValues(alpha: 0.1),
                              border: Border.all(
                                color:
                                    PusakaTheme.indigo500.withValues(alpha: 0.2),
                              ),
                            ),
                            child: const Icon(
                              Icons.qr_code,
                              color: PusakaTheme.indigo400,
                              size: 24,
                            ),
                          ),

                          const SizedBox(height: 16),

                          const Text(
                            'Verifikasi Kode Arena',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),

                          const SizedBox(height: 4),

                          Text.rich(
                            TextSpan(
                              text: 'Akses Peran: ',
                              style: const TextStyle(
                                color: PusakaTheme.slate400,
                                fontSize: 11,
                              ),
                              children: [
                                TextSpan(
                                  text: _roleTitleMap[widget.destination] ??
                                      'Petugas',
                                  style: const TextStyle(
                                    color: PusakaTheme.indigo400,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Juri Selection Bar (when destination is 'juri')
                          if (widget.destination == 'juri') ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: PusakaTheme.slate950,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: PusakaTheme.slate800),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(left: 4, bottom: 6),
                                    child: Text(
                                      'Pilih Posisi Juri Anda:',
                                      style: TextStyle(color: PusakaTheme.slate400, fontSize: 10, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      _buildJuriOption('Juri 1', 'juri_1'),
                                      const SizedBox(width: 6),
                                      _buildJuriOption('Juri 2', 'juri_2'),
                                      const SizedBox(width: 6),
                                      _buildJuriOption('Juri 3', 'juri_3'),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 20),

                          // Mode Selector Switch (Ketik OTP / Scan QR)
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: PusakaTheme.slate950,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: PusakaTheme.slate800),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(() => _isScanMode = false),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: !_isScanMode ? PusakaTheme.indigo600 : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.pin, size: 14, color: !_isScanMode ? Colors.white : PusakaTheme.slate400),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Ketik Kode OTP',
                                            style: TextStyle(
                                              color: !_isScanMode ? Colors.white : PusakaTheme.slate400,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(() => _isScanMode = true),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: _isScanMode ? PusakaTheme.indigo600 : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.qr_code_scanner, size: 14, color: _isScanMode ? Colors.white : PusakaTheme.slate400),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Scan QR Code',
                                            style: TextStyle(
                                              color: _isScanMode ? Colors.white : PusakaTheme.slate400,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
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

                          const SizedBox(height: 16),

                          // Stable IndexedStack for input modes
                          IndexedStack(
                            index: _isScanMode ? 1 : 0,
                            children: [
                              // Index 0: Ketik OTP
                              Container(
                                key: const ValueKey('pin_input_mode_container'),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: PusakaTheme.slate950.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(PusakaTheme.radiusLg),
                                  border: Border.all(color: PusakaTheme.slate800),
                                ),
                                child: Column(
                                  children: [
                                    const Text(
                                      'Ketik 8-Digit Kode OTP Arena',
                                      style: TextStyle(
                                        color: PusakaTheme.slate400,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    PinCodeTextField(
                                      key: const ValueKey('pin_code_text_field'),
                                      appContext: context,
                                      controller: _pinController,
                                      length: 8,
                                      onChanged: (value) {
                                        _code = value;
                                      },
                                      onCompleted: (value) {
                                        _code = value;
                                      },
                                      pinTheme: PinTheme(
                                        shape: PinCodeFieldShape.box,
                                        borderRadius: BorderRadius.circular(10),
                                        fieldHeight: 44,
                                        fieldWidth: 34,
                                        activeFillColor: PusakaTheme.slate900,
                                        inactiveFillColor: PusakaTheme.slate950,
                                        selectedFillColor: PusakaTheme.slate900,
                                        activeColor: PusakaTheme.indigo500,
                                        inactiveColor: PusakaTheme.slate700,
                                        selectedColor: PusakaTheme.indigo400,
                                      ),
                                      textStyle: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      enableActiveFill: true,
                                      keyboardType: TextInputType.text,
                                      animationType: AnimationType.fade,
                                      animationDuration:
                                          const Duration(milliseconds: 200),
                                    ),
                                  ],
                                ),
                              ),

                              // Index 1: Scan QR
                              SizedBox(
                                key: const ValueKey('qr_scanner_mode_container'),
                                height: 240,
                                child: QrScannerWidget(
                                  isActive: _isScanMode,
                                  onScanned: _onQrScanned,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Verify Button
                          if (_code.isNotEmpty && !_isScanMode)
                            SizedBox(
                              width: double.infinity,
                              child: GestureDetector(
                                onTap: _isLoading ? null : _verifyCode,
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(
                                    gradient: PusakaTheme.indigoGradient,
                                    borderRadius: BorderRadius.circular(
                                        PusakaTheme.radiusMd),
                                    boxShadow: [
                                      BoxShadow(
                                        color: PusakaTheme.indigo600
                                            .withValues(alpha: 0.3),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (_isLoading)
                                        const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                    Colors.white),
                                          ),
                                        )
                                      else
                                        const Icon(
                                            Icons.check_circle_outline,
                                            color: Colors.white,
                                            size: 16),
                                      const SizedBox(width: 8),
                                      Text(
                                        _isLoading
                                            ? 'MEMVERIFIKASI...'
                                            : 'VERIFIKASI & MASUK',
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
                            ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Help text
                    Text(
                      'Pastikan Anda mendapatkan kode gelanggang arena 8 digit resmi dari panitia.',
                      style: TextStyle(
                        color: PusakaTheme.slate500.withValues(alpha: 0.8),
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJuriOption(String label, String id) {
    final isSelected = _selectedJuriId == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setJuriId(id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? PusakaTheme.indigo600 : PusakaTheme.slate900,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? PusakaTheme.indigo400 : PusakaTheme.slate800,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : PusakaTheme.slate400,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
