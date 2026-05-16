import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_provider.dart';
import 'screens/home_screen.dart';
import 'screens/otp_monitor_screen.dart';
import 'screens/proxy_manager_screen.dart';
import 'screens/other_screen.dart';
import 'utils/app_theme.dart';

class PokemonCTApp extends StatelessWidget {
  const PokemonCTApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppProvider()..load(),
      child: MaterialApp(
        title: 'PokemonCT',
        theme: buildAppTheme(),
        debugShowCheckedModeBanner: false,
        home: const _MainShell(),
      ),
    );
  }
}

class _MainShell extends StatefulWidget {
  const _MainShell();

  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  int _index = 0;

  static const _pages = [
    HomeScreen(),
    OtpMonitorScreen(),
    ProxyManagerScreen(),
    OtherScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();

    if (!p.loaded) {
      return const Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('⚡', style: TextStyle(fontSize: 80)),
              SizedBox(height: 20),
              Text('PokemonCT',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2)),
              SizedBox(height: 8),
              Text('Account Manager',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12, letterSpacing: 0.5)),
              SizedBox(height: 32),
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 3,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.catching_pokemon),
            label: 'Tài khoản (${p.todoCount})',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.sms_outlined),
            label: 'OTP Monitor',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.vpn_lock),
            label: 'Proxy (${p.proxies.length})',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            label: 'Other',
          ),
        ],
      ),
    );
  }
}
