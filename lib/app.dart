import 'package:flutter/material.dart';
import 'config/theme.dart';
import 'screens/home/home_screen.dart';
import 'screens/verify/verify_screen.dart';
import 'screens/operator/operator_screen.dart';
import 'screens/juri/juri_screen.dart';
import 'screens/monitor/monitor_screen.dart';
import 'screens/timekeeper/timekeeper_screen.dart';

/// Root application widget with routing configuration.
class PusakaApp extends StatelessWidget {
  const PusakaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pusaka — Manajemen Pertandingan Silat',
      debugShowCheckedModeBanner: false,
      theme: PusakaTheme.darkTheme,
      initialRoute: '/',
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    final name = settings.name;

    switch (name) {
      case '/':
        return _buildRoute(const HomeScreen(), settings);

      case '/verify/operator':
        return _buildRoute(
          const VerifyScreen(destination: 'operator'),
          settings,
        );

      case '/verify/juri':
        return _buildRoute(
          const VerifyScreen(destination: 'juri'),
          settings,
        );

      case '/verify/monitor':
        return _buildRoute(
          const VerifyScreen(destination: 'monitor'),
          settings,
        );

      case '/verify/timekeeper':
        return _buildRoute(
          const VerifyScreen(destination: 'timekeeper'),
          settings,
        );

      case '/operator':
        return _buildRoute(const OperatorScreen(), settings);

      case '/juri':
        return _buildRoute(const JuriScreen(), settings);

      case '/monitor':
        return _buildRoute(const MonitorScreen(), settings);

      case '/timekeeper':
        return _buildRoute(const TimekeeperScreen(), settings);

      default:
        return _buildRoute(const HomeScreen(), settings);
    }
  }

  MaterialPageRoute _buildRoute(Widget page, RouteSettings settings) {
    return MaterialPageRoute(
      builder: (_) => page,
      settings: settings,
    );
  }
}
