import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_provider.dart';
import 'screens/home_screen.dart';
import 'screens/otp_monitor_screen.dart';
import 'screens/proxy_manager_screen.dart';
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
              Text('🎮', style: TextStyle(fontSize: 64)),
              SizedBox(height: 16),
              Text('PokemonCT',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold)),
              SizedBox(height: 24),
              CircularProgressIndicator(color: AppColors.primary),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.catching_pokemon),
            label: 'Tài khoản (${p.todoCount})',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.sms_outlined),
                if (p.imapRunning)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.done,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            label: 'OTP Monitor',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.vpn_lock),
            label: 'Proxy (${p.proxies.length})',
          ),
        ],
      ),
    );
  }
}
