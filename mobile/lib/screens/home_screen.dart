import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pos_screen.dart';
import 'sales_history_screen.dart';
import 'fiados_screen.dart';
import 'copias_screen.dart';
import 'closings_screen.dart';
import 'reports_screen.dart';
import 'inventory_screen.dart';
import 'cajas_screen.dart';
import 'repairs_screen.dart';
import 'withdrawals_screen.dart';
import 'consumptions_screen.dart';
import 'settings_screen.dart';
import '../services/db_service.dart';
import '../services/sync_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  final _screens = const [
    PosScreen(),
    SalesHistoryScreen(),
    FiadosScreen(),
    CopiasScreen(),
    RepairsScreen(),
    ClosingsScreen(),
    CajasScreen(),
    WithdrawalsScreen(),
    ConsumptionsScreen(),
    InventoryScreen(),
    ReportsScreen(),
    SettingsScreen(),
  ];

  final _icons = [
    Icons.point_of_sale,
    Icons.history,
    Icons.book,
    Icons.print,
    Icons.build,
    Icons.account_balance_wallet,
    Icons.store,
    Icons.arrow_downward,
    Icons.restaurant,
    Icons.inventory_outlined,
    Icons.bar_chart,
    Icons.settings,
  ];

  final _labels = [
    'POS', 'Ventas', 'Fiados', 'Copias', 'Reparar',
    'Cierres', 'Cajas', 'Retiros', 'Consumos', 'Invent.',
    'Reportes', 'Conexion',
  ];

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final db = context.watch<DbService>();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0EB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D9488),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('La Lomita', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '${db.products.length} prod.',
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ),
          ),
          Icon(
            sync.connected ? Icons.cloud_done : Icons.cloud_off,
            color: sync.connected ? Colors.white : Colors.white54,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        height: 64,
        destinations: List.generate(_screens.length, (i) =>
          NavigationDestination(
            icon: Icon(_icons[i], size: 22),
            selectedIcon: Icon(_icons[i], size: 22, color: const Color(0xFF0D9488)),
            label: _labels[i],
          ),
        ),
      ),
    );
  }
}
