import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerSheet extends StatefulWidget {
  final String title;
  final bool returnList;

  const BarcodeScannerSheet({super.key, this.title = 'Escanear', this.returnList = false});

  static Future<String?> show(BuildContext context, {String title = 'Escanear'}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (_) => BarcodeScannerSheet(title: title, returnList: false),
    );
  }

  static Future<List<String>?> showMulti(BuildContext context, {String title = 'Escanear'}) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (_) => BarcodeScannerSheet(title: title, returnList: true),
    );
  }

  @override
  State<BarcodeScannerSheet> createState() => _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends State<BarcodeScannerSheet> {
  final controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
  );
  final List<String> _scannedCodes = [];
  String _lastScanned = '';
  Timer? _cooldown;

  @override
  void dispose() {
    _cooldown?.cancel();
    controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_cooldown != null && _cooldown!.isActive) return;

    for (final b in capture.barcodes) {
      final code = b.rawValue;
      if (code == null || code.isEmpty) continue;
      if (code == _lastScanned) continue;

      _lastScanned = code;
      _cooldown = Timer(const Duration(milliseconds: 800), () {});

      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.click);

      setState(() {
        if (!widget.returnList) {
          _scannedCodes.clear();
        }
        _scannedCodes.add(code);
      });

      if (!widget.returnList) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) Navigator.pop(context, code);
        });
      }
    }
  }

  void _removeCode(int index) {
    setState(() {
      _scannedCodes.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (widget.returnList && _scannedCodes.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context, _scannedCodes),
                      icon: const Icon(Icons.check_circle, color: Colors.green, size: 22),
                      label: Text('Listo (${_scannedCodes.length})', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    ),
                  IconButton(
                    onPressed: () {
                      if (widget.returnList) {
                        Navigator.pop(context, _scannedCodes.isNotEmpty ? _scannedCodes : null);
                      } else {
                        Navigator.pop(context);
                      }
                    },
                    icon: const Icon(Icons.close, color: Colors.white, size: 26),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: MobileScanner(controller: controller, onDetect: _onDetect),
              ),
            ),

            // Lista de codigos escaneados (modo multi)
            if (widget.returnList && _scannedCodes.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 140),
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _scannedCodes.length,
                  itemBuilder: (context, index) => Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _scannedCodes[index],
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          '#${index + 1}',
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _removeCode(index),
                          child: const Icon(Icons.close, color: Colors.red, size: 18),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Apunta la camara al codigo de barras. Escanea continuo.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
