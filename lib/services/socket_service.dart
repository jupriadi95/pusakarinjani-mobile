import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/env.dart';
import '../models/gelanggang.dart';
import '../models/nilai.dart';

/// Socket Service — manages WebSocket connection via Socket.io.
/// Replicates the socket.io setup from Nuxt's juri and monitor pages.
class SocketService {
  io.Socket? _socket;
  bool _isConnected = false;

  // ── Stream controllers for reactive state ──
  final _connectionController = StreamController<bool>.broadcast();
  final _gelanggangUpdatedController = StreamController<Gelanggang>.broadcast();
  final _nilaiCreatedController = StreamController<Nilai>.broadcast();

  /// Stream of connection status changes
  Stream<bool> get onConnectionChanged => _connectionController.stream;

  /// Stream of gelanggang updates (from 'gelanggang:updated' event)
  Stream<Gelanggang> get onGelanggangUpdated => _gelanggangUpdatedController.stream;

  /// Stream of new nilai created (from 'nilai:created' event)
  Stream<Nilai> get onNilaiCreated => _nilaiCreatedController.stream;

  /// Whether currently connected
  bool get isConnected => _isConnected;

  /// Connect to the Socket.io server and join a gelanggang room.
  void connect({String? gelanggangDocumentId}) {
    if (_socket != null) {
      _socket!.dispose();
    }

    _socket = io.io(
      Env.apiBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(2000)
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('[Socket] Connected to realtime server');
      _isConnected = true;
      _connectionController.add(true);

      // Join the gelanggang room if documentId is provided
      if (gelanggangDocumentId != null && gelanggangDocumentId.isNotEmpty) {
        _socket!.emit('join:gelanggang', gelanggangDocumentId);
        debugPrint('[Socket] Joined gelanggang room: $gelanggangDocumentId');
      }
    });

    _socket!.onDisconnect((_) {
      debugPrint('[Socket] Disconnected from realtime server');
      _isConnected = false;
      _connectionController.add(false);
    });

    _socket!.onConnectError((error) {
      debugPrint('[Socket] Connection error: $error');
      _isConnected = false;
      _connectionController.add(false);
    });

    // Listen for gelanggang updates (operator changes status)
    _socket!.on('gelanggang:updated', (data) {
      debugPrint('[Socket] gelanggang:updated received');
      try {
        if (data is Map<String, dynamic>) {
          final gelanggang = Gelanggang.fromJson(data);
          _gelanggangUpdatedController.add(gelanggang);
        }
      } catch (e) {
        debugPrint('[Socket] Error parsing gelanggang update: $e');
      }
    });

    // Listen for new nilai (juri adds score)
    _socket!.on('nilai:created', (data) {
      debugPrint('[Socket] nilai:created received');
      try {
        if (data is Map<String, dynamic>) {
          final nilai = Nilai.fromJson(data);
          _nilaiCreatedController.add(nilai);
        }
      } catch (e) {
        debugPrint('[Socket] Error parsing nilai: $e');
      }
    });

    _socket!.connect();
  }

  /// Join a specific gelanggang room
  void joinGelanggang(String documentId) {
    if (_socket != null && _isConnected) {
      _socket!.emit('join:gelanggang', documentId);
      debugPrint('[Socket] Joined gelanggang room: $documentId');
    }
  }

  /// Disconnect and clean up
  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
    _connectionController.add(false);
  }

  /// Dispose all stream controllers
  void dispose() {
    disconnect();
    _connectionController.close();
    _gelanggangUpdatedController.close();
    _nilaiCreatedController.close();
  }
}
