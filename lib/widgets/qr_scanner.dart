import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../config/theme.dart';

/// QR Scanner Widget — live camera preview for scanning arena QR codes.
class QrScannerWidget extends StatefulWidget {
  final ValueChanged<String> onScanned;
  final bool isActive;
  final String? prompt;

  const QrScannerWidget({
    super.key,
    required this.onScanned,
    this.isActive = true,
    this.prompt,
  });

  @override
  State<QrScannerWidget> createState() => _QrScannerWidgetState();
}

class _QrScannerWidgetState extends State<QrScannerWidget> {
  late final MobileScannerController _controller;
  bool _isScanned = false;
  bool _isTorchOn = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
      autoStart: widget.isActive,
    );
  }

  @override
  void didUpdateWidget(covariant QrScannerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        setState(() => _isScanned = false);
        _controller.start();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture capture) {
    if (!widget.isActive || _isScanned) return;
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final code = barcode.rawValue;
      if (code != null && code.trim().isNotEmpty) {
        setState(() => _isScanned = true);
        widget.onScanned(code.trim());
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return Container(
        color: PusakaTheme.slate950,
        alignment: Alignment.center,
        child: const Text(
          'Kamera Nonaktif',
          style: TextStyle(color: PusakaTheme.slate500, fontSize: 11),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: PusakaTheme.slate950,
        borderRadius: BorderRadius.circular(PusakaTheme.radiusXl),
        border: Border.all(color: PusakaTheme.indigo500.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: PusakaTheme.indigo600.withValues(alpha: 0.2),
            blurRadius: 20,
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Camera Preview
          MobileScanner(
            controller: _controller,
            onDetect: _handleBarcode,
            errorBuilder: (context, error, child) {
              return Container(
                color: PusakaTheme.slate900,
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.videocam_off, color: PusakaTheme.rose400, size: 36),
                    const SizedBox(height: 8),
                    Text(
                      'Kamera Tidak Tersedia\n${error.errorCode}',
                      style: const TextStyle(color: PusakaTheme.slate400, fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            },
          ),

          // Scanner Overlay Reticle Box
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: PusakaTheme.indigo400, width: 2),
            ),
          ),

          // Glowing animated scanner line indicator
          Positioned(
            top: 40,
            child: Container(
              width: 200,
              height: 2,
              decoration: BoxDecoration(
                color: PusakaTheme.amber400,
                boxShadow: [
                  BoxShadow(
                    color: PusakaTheme.amber400.withValues(alpha: 0.8),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),

          // Controls Top Bar (Torch & Flip Camera)
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Torch toggle
                IconButton(
                  icon: Icon(
                    _isTorchOn ? Icons.flash_on : Icons.flash_off,
                    color: _isTorchOn ? PusakaTheme.amber400 : Colors.white70,
                  ),
                  onPressed: () {
                    _controller.toggleTorch();
                    setState(() => _isTorchOn = !_isTorchOn);
                  },
                ),

                // Camera direction toggle
                IconButton(
                  icon: const Icon(Icons.cameraswitch, color: Colors.white70),
                  onPressed: () => _controller.switchCamera(),
                ),
              ],
            ),
          ),

          // Bottom prompt label
          Positioned(
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code_scanner, color: PusakaTheme.indigo400, size: 14),
                  SizedBox(width: 6),
                  Text(
                    widget.prompt ?? 'Arahkan kamera ke QR Code Arena',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
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
}
