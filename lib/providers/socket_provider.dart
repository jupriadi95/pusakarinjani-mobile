import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/socket_service.dart';
export '../services/socket_service.dart';

/// Singleton SocketService provider.
/// All screens must use this provider to share one WebSocket connection
/// and ensure events are correctly routed across the app.
final socketServiceProvider = Provider<SocketService>((ref) {
  final service = SocketService();
  ref.onDispose(() => service.dispose());
  return service;
});
