import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/sync_service.dart';
import '../utils/format.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlCtrl = TextEditingController();
  bool _autoSync = true;

  @override
  void initState() {
    super.initState();
    final sync = context.read<SyncService>();
    _urlCtrl.text = sync.serverUrl;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveAndConnect() async {
    final sync = context.read<SyncService>();
    await sync.saveServerUrl(_urlCtrl.text.trim());
    final ok = await sync.testConnection();
    if (ok) {
      await sync.pullFromServer();
      if (_autoSync) sync.startAutoSync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conectado y sincronizado')),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sync.lastError ?? 'Error de conexión')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Firebase Cloud Sync Card ──
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sincronización en la Nube', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                    'Sincroniza tus datos en tiempo real mediante Firebase Firestore. '
                    'Cualquier cambio se reflejará instantáneamente en computadoras y otros celulares.',
                    style: TextStyle(color: Colors.black54, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Activar Firebase Cloud Sync'),
                    subtitle: const Text('Conexión directa en tiempo real'),
                    value: sync.firebaseEnabled,
                    onChanged: (v) => sync.toggleFirebase(v),
                  ),
                  if (sync.firebaseEnabled) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          sync.connected ? Icons.cloud_done : Icons.cloud_off,
                          color: sync.connected ? Colors.green : Colors.red,
                          size: 28,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            sync.connected ? 'Conectado a Firestore ✓' : 'Desconectado de Firestore',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: sync.connected ? Colors.green : Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (sync.lastError != null && sync.firebaseEnabled) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
                                const SizedBox(width: 6),
                                Text('Error de conexión', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              sync.lastError!,
                              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => sync.initFirebase(force: true),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar conexión Firebase'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0D9488),
                        ),
                      ),
                    ),
                    if (sync.lastSync != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Última sincronización: ${fmtDate(sync.lastSync!.toIso8601String())}',
                        style: const TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ── Server Connection Card (optional, when Firebase is OFF) ──
          if (!sync.firebaseEnabled) ...[
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Conexión con el PC', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                      'El PC debe tener el programa abierto (server.py). Usa la IP de la red local.\n'
                      'Ejemplo: http://192.168.1.50:5000',
                      style: TextStyle(color: Colors.black54, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _urlCtrl,
                      decoration: InputDecoration(
                        labelText: 'URL del servidor',
                        hintText: 'http://192.168.1.50:5000',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.dns),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Sincronización automática cada 30s'),
                      value: _autoSync,
                      onChanged: (v) => setState(() => _autoSync = v),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: sync.syncing ? null : () => sync.testConnection(),
                            icon: const Icon(Icons.wifi_find),
                            label: const Text('Probar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: sync.syncing ? null : _saveAndConnect,
                            icon: sync.syncing
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.sync),
                            label: const Text('Conectar'),
                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          // ── Estado general ──
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Estado', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _statusRow(
                    'Modo',
                    sync.firebaseEnabled ? 'Firebase Cloud' : 'Servidor Local',
                    sync.firebaseEnabled ? const Color(0xFF0D9488) : Colors.blue,
                  ),
                  _statusRow(
                    'Conexión',
                    sync.connected ? 'Conectado' : 'Desconectado',
                    sync.connected ? Colors.green : Colors.red,
                  ),
                  _statusRow(
                    'Productos cargados',
                    '${sync.db.products.length}',
                    Colors.black87,
                  ),
                  _statusRow(
                    'Ventas cargadas',
                    '${sync.db.sales.length}',
                    Colors.black87,
                  ),
                  _statusRow(
                    'Fiados / abonos',
                    '${sync.db.sales.where((s) => s['paymentMethod'] == 'credit').length} ventas, ${sync.db.fiadosPagos.length} abonos',
                    Colors.black87,
                  ),
                  if (sync.lastSync != null)
                    _statusRow('Última sync', fmtDate(sync.lastSync!.toIso8601String()), Colors.black54),
                  if (sync.lastError != null && !sync.firebaseEnabled)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(sync.lastError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                    ),
                  if (sync.firebaseEnabled) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: sync.syncing ? null : () => sync.pushToFirebase(),
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('Subir datos locales a Firebase'),
                    ),
                  ],
                  if (!sync.firebaseEnabled) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: sync.syncing ? null : () => sync.sync(),
                      icon: const Icon(Icons.cloud_download),
                      label: const Text('Descargar datos del PC'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: sync.syncing ? null : () => sync.pushToServer(),
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('Subir datos al PC'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          Flexible(child: Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: color), textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}
