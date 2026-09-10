import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/api_service.dart';
import 'core/theme.dart';
import 'core/websocket_service.dart';
import 'screens/auth_screen.dart';
import 'screens/main_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final apiService = ApiService();
  await apiService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: apiService),
        ChangeNotifierProxyProvider<ApiService, WebSocketService>(
          create: (ctx) => WebSocketService(apiService),
          update: (ctx, api, ws) => ws ?? WebSocketService(api),
        ),
      ],
      child: const TelegramMediaHubApp(),
    ),
  );
}

class TelegramMediaHubApp extends StatelessWidget {
  const TelegramMediaHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Telegram Media Hub 360°',
      debugShowCheckedModeBanner: false,
      theme: CyberTheme.themeData,
      home: Consumer<ApiService>(
        builder: (context, api, child) {
          if (api.isAuthenticated) {
            return const MainShell();
          }
          return const AuthScreen();
        },
      ),
    );
  }
}

