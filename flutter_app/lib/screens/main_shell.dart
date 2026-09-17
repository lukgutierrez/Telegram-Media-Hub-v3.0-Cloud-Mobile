import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../core/websocket_service.dart';
import 'search_360_screen.dart';
import 'quick_download_screen.dart';
import 'jobs_screen.dart';
import 'osint_screen.dart';
import 'settings_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentTabIndex = 0;
  int? _targetJobId;
  String? _prefilledTarget;

  void _onJobStarted(int jobId) {
    setState(() {
      _targetJobId = jobId;
      _currentTabIndex = 2; // Jump to Jobs tab
    });
  }

  void _onSelectTarget(String target) {
    setState(() {
      _prefilledTarget = target;
      _currentTabIndex = 1; // Jump to QuickDownloadScreen
    });
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WebSocketService>();
    final isConnected = ws.isConnected;

    final screens = [
      Search360Screen(onJobStarted: _onJobStarted),
      QuickDownloadScreen(onJobStarted: _onJobStarted, initialTarget: _prefilledTarget),
      JobsScreen(initialJobId: _targetJobId),
      OsintScreen(onSelectTarget: _onSelectTarget),
      const SettingsScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: LayoutBuilder(
          builder: (context, appConstraints) {
            final isMobile = appConstraints.maxWidth < 600;
            return Row(
              children: [
                const Icon(Icons.bolt, color: CyberTheme.neonCyan, size: 22),
                const SizedBox(width: 6),
                Text(
                  isMobile ? 'TMH 360°' : 'TELEGRAM MEDIA HUB 360°',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                if (!isMobile) ...[
                  const Text(
                    '@lukgtz',
                    style: TextStyle(color: CyberTheme.textMuted, fontSize: 11, fontFamily: 'monospace'),
                  ),
                  const SizedBox(width: 12),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isConnected ? CyberTheme.neonGreen : CyberTheme.neonRed).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: (isConnected ? CyberTheme.neonGreen : CyberTheme.neonRed).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isConnected ? CyberTheme.neonGreen : CyberTheme.neonRed,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isConnected ? 'EN VIVO' : 'OFFLINE',
                        style: TextStyle(
                          color: isConnected ? CyberTheme.neonGreen : CyberTheme.neonRed,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 850;
          if (isWide) {
            return Row(
              children: [
                NavigationRail(
                  backgroundColor: CyberTheme.bgCard,
                  selectedIndex: _currentTabIndex,
                  onDestinationSelected: (idx) => setState(() => _currentTabIndex = idx),
                  labelType: NavigationRailLabelType.all,
                  selectedLabelTextStyle: const TextStyle(color: CyberTheme.neonCyan, fontSize: 11, fontWeight: FontWeight.bold),
                  unselectedLabelTextStyle: const TextStyle(color: CyberTheme.textMuted, fontSize: 11),
                  selectedIconTheme: const IconThemeData(color: CyberTheme.neonCyan, size: 24),
                  unselectedIconTheme: const IconThemeData(color: CyberTheme.textMuted, size: 22),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.saved_search),
                      label: Text('Buscador 360°'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.download),
                      label: Text('Descargas'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.speed),
                      label: Text('Tareas'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.radar),
                      label: Text('OSINT'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings),
                      label: Text('Ajustes'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1, color: Colors.white10),
                Expanded(child: screens[_currentTabIndex]),
              ],
            );
          } else {
            return screens[_currentTabIndex];
          }
        },
      ),
      bottomNavigationBar: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth <= 850) {
            return BottomNavigationBar(
              currentIndex: _currentTabIndex,
              onTap: (idx) => setState(() => _currentTabIndex = idx),
              backgroundColor: CyberTheme.bgCard,
              selectedItemColor: CyberTheme.neonCyan,
              unselectedItemColor: CyberTheme.textMuted,
              type: BottomNavigationBarType.fixed,
              selectedFontSize: 11,
              unselectedFontSize: 10,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.saved_search), label: 'Buscador'),
                BottomNavigationBarItem(icon: Icon(Icons.download), label: 'Descargas'),
                BottomNavigationBarItem(icon: Icon(Icons.speed), label: 'Tareas'),
                BottomNavigationBarItem(icon: Icon(Icons.radar), label: 'OSINT'),
                BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Ajustes'),
              ],
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}
