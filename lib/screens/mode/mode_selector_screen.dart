import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../config/env.dart';
import '../../config/theme.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/qr_scanner.dart';

/// Mode Selector Screen — Displayed on app launch.
/// Allows the user to choose between Online (Cloud) and Offline (LAN) backend modes
/// before proceeding to the main Portal.
class ModeSelectorScreen extends StatefulWidget {
  const ModeSelectorScreen({super.key});

  @override
  State<ModeSelectorScreen> createState() => _ModeSelectorScreenState();
}

class _ModeSelectorScreenState extends State<ModeSelectorScreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  void _selectOnlineMode() {
    Env.setOnline();
    ApiService.reinitialize();
    Navigator.of(context).pushReplacementNamed('/home');
  }

  Future<void> _openOfflineAuthModal() async {
    // Load previously saved offline token if available
    final savedToken = await StorageService.loadOfflineToken() ?? '';

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _OfflineAuthBottomSheet(
        initialToken: savedToken,
        onConnect: (token) async {
          await StorageService.saveOfflineToken(token);
          Env.setOffline(token: token);
          ApiService.reinitialize();
          if (mounted) {
            Navigator.of(context).pushReplacementNamed('/home');
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        decoration:
            const BoxDecoration(gradient: PusakaTheme.backgroundGradient),
        child: Stack(
          children: [
            // Ambient glow orbs
            Positioned(
              top: screenSize.height * 0.12,
              left: screenSize.width * 0.2,
              child: Container(
                width: 350,
                height: 350,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: PusakaTheme.indigo600.withValues(alpha: 0.10),
                ),
              ),
            ),
            Positioned(
              bottom: 60,
              right: 30,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: PusakaTheme.emerald600.withValues(alpha: 0.06),
                ),
              ),
            ),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const Spacer(flex: 2),

                    // Emblem
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [PusakaTheme.indigo500, Color(0xFF9333EA)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                PusakaTheme.indigo500.withValues(alpha: 0.30),
                            blurRadius: 24,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(2.5),
                      child: Container(
                        decoration: BoxDecoration(
                          color: PusakaTheme.slate950,
                          borderRadius: BorderRadius.circular(19),
                        ),
                        padding: const EdgeInsets.all(10),
                        child: Image.asset(
                          'assets/img/logo_ipsi.webp',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                            Icons.sports_kabaddi,
                            color: PusakaTheme.amber400,
                            size: 32,
                          ),
                        ),
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 500.ms)
                        .scale(
                            begin: const Offset(0.8, 0.8),
                            duration: 500.ms,
                            curve: Curves.easeOut),

                    const SizedBox(height: 20),

                    // Title
                    const Text(
                      'PUSAKA RINJANI',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    )
                        .animate()
                        .fadeIn(delay: 200.ms, duration: 500.ms)
                        .slideY(begin: 0.1, duration: 500.ms),

                    const SizedBox(height: 6),

                    const Text(
                      'Sistem Manajemen Pertandingan Pencak Silat',
                      style: TextStyle(
                        color: PusakaTheme.slate400,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    )
                        .animate()
                        .fadeIn(delay: 300.ms, duration: 500.ms),

                    const SizedBox(height: 36),

                    // Section Title
                    const Text(
                      'PILIH MODE KONEKSI',
                      style: TextStyle(
                        color: PusakaTheme.slate300,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    )
                        .animate()
                        .fadeIn(delay: 400.ms, duration: 500.ms),

                    const SizedBox(height: 6),

                    const Text(
                      'Pilih koneksi server backend yang akan digunakan',
                      style: TextStyle(
                        color: PusakaTheme.slate500,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    )
                        .animate()
                        .fadeIn(delay: 450.ms, duration: 500.ms),

                    const SizedBox(height: 24),

                    // ── ONLINE MODE CARD ──
                    _buildModeCard(
                      title: 'ONLINE',
                      subtitle: 'Cloud Server',
                      description:
                          'Terhubung ke server cloud (internet). Token otentikasi terpasang otomatis.',
                      icon: Icons.cloud_rounded,
                      url: 'be.pusakarinjani.my.id',
                      gradientColors: [
                        const Color(0xFF3B82F6),
                        const Color(0xFF2563EB),
                      ],
                      glowColor: const Color(0xFF3B82F6),
                      badgeText: 'CLOUD',
                      badgeColor: const Color(0xFF1E40AF),
                      onTap: _selectOnlineMode,
                    )
                        .animate()
                        .fadeIn(delay: 500.ms, duration: 500.ms)
                        .slideX(begin: -0.05, duration: 500.ms),

                    const SizedBox(height: 14),

                    // ── OFFLINE / LAN MODE CARD ──
                    _buildModeCard(
                      title: 'OFFLINE / LAN',
                      subtitle: 'Server Lokal',
                      description:
                          'Terhubung ke server lokal. Masukkan token otentikasi atau scan QR Code token.',
                      icon: Icons.lan_rounded,
                      url: 'be-local.pusakarinjani.my.id',
                      gradientColors: [
                        const Color(0xFF10B981),
                        const Color(0xFF059669),
                      ],
                      glowColor: const Color(0xFF10B981),
                      badgeText: 'LOCAL',
                      badgeColor: const Color(0xFF065F46),
                      onTap: _openOfflineAuthModal,
                    )
                        .animate()
                        .fadeIn(delay: 600.ms, duration: 500.ms)
                        .slideX(begin: 0.05, duration: 500.ms),

                    const Spacer(flex: 2),

                    // Footer
                    Column(
                      children: [
                        Divider(
                            color:
                                PusakaTheme.slate800.withValues(alpha: 0.6)),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: PusakaTheme.indigo500,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'IPSI Digital Scoreboard System © 2026',
                              style: TextStyle(
                                color: PusakaTheme.slate500,
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],
                    )
                        .animate()
                        .fadeIn(delay: 700.ms, duration: 500.ms),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeCard({
    required String title,
    required String subtitle,
    required String description,
    required IconData icon,
    required String url,
    required List<Color> gradientColors,
    required Color glowColor,
    required String badgeText,
    required Color badgeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: PusakaTheme.slate900.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: glowColor.withValues(alpha: 0.30),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: glowColor.withValues(alpha: 0.10),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Icon
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors,
                ),
                boxShadow: [
                  BoxShadow(
                    color: glowColor.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),

            const SizedBox(width: 14),

            // Text Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: glowColor.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            color: glowColor,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: const TextStyle(
                      color: PusakaTheme.slate400,
                      fontSize: 11,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // URL indicator
                  Row(
                    children: [
                      Icon(
                        Icons.link_rounded,
                        size: 12,
                        color: glowColor.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          url,
                          style: TextStyle(
                            color: glowColor.withValues(alpha: 0.8),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios,
              color: glowColor.withValues(alpha: 0.5),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

/// Modal Bottom Sheet for Entering / Scanning Offline Token
class _OfflineAuthBottomSheet extends StatefulWidget {
  final String initialToken;
  final ValueChanged<String> onConnect;

  const _OfflineAuthBottomSheet({
    required this.initialToken,
    required this.onConnect,
  });

  @override
  State<_OfflineAuthBottomSheet> createState() =>
      _OfflineAuthBottomSheetState();
}

class _OfflineAuthBottomSheetState extends State<_OfflineAuthBottomSheet> {
  late final TextEditingController _tokenController;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController(text: widget.initialToken);
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      setState(() {
        _tokenController.text = data.text!.trim();
        _errorMessage = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Token ditempel dari papan klip'),
            backgroundColor: PusakaTheme.emerald600,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _openQrScanner() {
    showDialog(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Container(
          decoration: BoxDecoration(
            color: PusakaTheme.slate900,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: PusakaTheme.emerald500.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.qr_code_scanner,
                            color: PusakaTheme.emerald400, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'Scan QR Token Offline',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: PusakaTheme.slate400),
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                    ),
                  ],
                ),
              ),

              // Scanner Box
              SizedBox(
                height: 320,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: QrScannerWidget(
                      prompt: 'Arahkan kamera ke QR Code Token Offline',
                      onScanned: (scannedCode) {
                        Navigator.of(dialogCtx).pop();
                        setState(() {
                          _tokenController.text = scannedCode.trim();
                          _errorMessage = null;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Token berhasil dipindai dari QR Code!'),
                            backgroundColor: PusakaTheme.emerald600,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _handleSubmit() {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() {
        _errorMessage = 'Token otentikasi tidak boleh kosong!';
      });
      return;
    }

    Navigator.of(context).pop(); // Close bottom sheet
    widget.onConnect(token);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: PusakaTheme.slate950,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: PusakaTheme.emerald600.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: PusakaTheme.emerald950.withValues(alpha: 0.5),
            blurRadius: 30,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: PusakaTheme.slate700,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            const SizedBox(height: 18),

            // Header Row
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                    ),
                  ),
                  child: const Icon(Icons.lan_rounded,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Autentikasi Offline / LAN',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.dns_rounded,
                              size: 12, color: PusakaTheme.emerald400),
                          const SizedBox(width: 4),
                          Text(
                            Env.apiBaseUrl,
                            style: const TextStyle(
                              color: PusakaTheme.emerald400,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: PusakaTheme.slate400),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),

            const SizedBox(height: 18),
            Divider(color: PusakaTheme.slate800.withValues(alpha: 0.8)),
            const SizedBox(height: 14),

            // Prompt description
            const Text(
              'Masukkan token otentikasi backend lokal atau gunakan tombol Scan QR Code untuk mengisi otomatis.',
              style: TextStyle(
                color: PusakaTheme.slate400,
                fontSize: 12,
                height: 1.4,
              ),
            ),

            const SizedBox(height: 16),

            // Action Buttons Row (Scan QR & Paste)
            Row(
              children: [
                // Scan QR Button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openQrScanner,
                    icon: const Icon(Icons.qr_code_scanner, size: 18),
                    label: const Text(
                      'Scan QR Token',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          PusakaTheme.emerald950.withValues(alpha: 0.8),
                      foregroundColor: PusakaTheme.emerald400,
                      side: BorderSide(
                        color: PusakaTheme.emerald500.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                // Paste Clipboard Button
                ElevatedButton.icon(
                  onPressed: _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: const Text(
                    'Tempel',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        PusakaTheme.slate800.withValues(alpha: 0.8),
                    foregroundColor: PusakaTheme.slate200,
                    side: const BorderSide(
                      color: PusakaTheme.slate700,
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Token Input Field
            TextField(
              controller: _tokenController,
              maxLines: 3,
              minLines: 2,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                hintText: 'Ketik atau tempel token otentikasi di sini...',
                hintStyle: const TextStyle(
                  color: PusakaTheme.slate600,
                  fontSize: 12,
                ),
                filled: true,
                fillColor: PusakaTheme.slate900,
                contentPadding: const EdgeInsets.all(14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: PusakaTheme.slate700),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: _errorMessage != null
                        ? PusakaTheme.rose500
                        : PusakaTheme.slate800,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: PusakaTheme.emerald400,
                    width: 1.5,
                  ),
                ),
                suffixIcon: _tokenController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            color: PusakaTheme.slate500, size: 18),
                        onPressed: () {
                          setState(() {
                            _tokenController.clear();
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (_) {
                if (_errorMessage != null) {
                  setState(() => _errorMessage = null);
                }
              },
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: PusakaTheme.rose400, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: PusakaTheme.rose400,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 20),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _handleSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: PusakaTheme.emerald600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 4,
                  shadowColor:
                      PusakaTheme.emerald600.withValues(alpha: 0.4),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.login_rounded, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Hubungkan & Lanjutkan',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
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
}
