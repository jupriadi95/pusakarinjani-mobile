import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/env.dart';
import '../models/gelanggang.dart';
import '../models/nilai.dart';

/// Socket Service — manages WebSocket connection via Socket.io.
/// Handles real-time scoring, jury consensus voting, KP discipline state, and Dewan Verification workflow.
class SocketService {
  io.Socket? _socket;
  bool _isConnected = false;

  // ── Stream controllers for reactive state ──
  final _connectionController = StreamController<bool>.broadcast();
  final _gelanggangUpdatedController = StreamController<Gelanggang>.broadcast();
  final _nilaiCreatedController = StreamController<Nilai>.broadcast();

  // ── Jury consensus voting events ──
  final _juriVoteBufferedController = StreamController<Map<String, dynamic>>.broadcast();
  final _juriVoteConfirmController = StreamController<Map<String, dynamic>>.broadcast();
  final _juriVoteRejectedController = StreamController<Map<String, dynamic>>.broadcast();

  // ── KP discipline & match status events ──
  final _kpStatusController = StreamController<Map<String, dynamic>>.broadcast();
  final _pesertaDsqController = StreamController<Map<String, dynamic>>.broadcast();
  final _skorUpdateController = StreamController<Map<String, dynamic>>.broadcast();

  // ── KP nilai persisted via REST — broadcast to all screens for realtime sync ──
  final _nilaiKpController = StreamController<Map<String, dynamic>>.broadcast();

  // ── Dewan Verification (Jatuhan & Pelanggaran) events ──
  final _verifikasiMulaiController = StreamController<Map<String, dynamic>>.broadcast();
  final _verifikasiVoteController = StreamController<Map<String, dynamic>>.broadcast();
  final _verifikasiSelesaiController = StreamController<Map<String, dynamic>>.broadcast();

  // ── Match Timer Synchronized Control events (Mulai, Jeda/Pause, Lanjut/Resume, Reset) ──
  final _timerControlController = StreamController<Map<String, dynamic>>.broadcast();

  // ── Match Completion / Finished events ──
  final _pertandinganSelesaiController = StreamController<Map<String, dynamic>>.broadcast();

  /// Stream of match completion events
  Stream<Map<String, dynamic>> get onPertandinganSelesai => _pertandinganSelesaiController.stream;

  /// Stream of connection status changes
  Stream<bool> get onConnectionChanged => _connectionController.stream;

  /// Stream of gelanggang updates (from 'gelanggang:updated' event)
  Stream<Gelanggang> get onGelanggangUpdated => _gelanggangUpdatedController.stream;

  /// Stream of new nilai created (from 'nilai:created' event)
  Stream<Nilai> get onNilaiCreated => _nilaiCreatedController.stream;

  /// Stream of buffered jury vote (waiting for 2nd/3rd jury)
  Stream<Map<String, dynamic>> get onJuriVoteBuffered => _juriVoteBufferedController.stream;

  /// Stream of confirmed jury vote (2+ jury consensus reached)
  Stream<Map<String, dynamic>> get onJuriVoteConfirm => _juriVoteConfirmController.stream;

  /// Stream of rejected jury vote (consensus window expired without agreement)
  Stream<Map<String, dynamic>> get onJuriVoteRejected => _juriVoteRejectedController.stream;

  /// Stream of KP status updates (binaan, teguran, pembinaan counts)
  Stream<Map<String, dynamic>> get onKpStatus => _kpStatusController.stream;

  /// Stream of KP nilai that were persisted via REST API (negative deductions broadcast)
  Stream<Map<String, dynamic>> get onNilaiKp => _nilaiKpController.stream;

  /// Stream of athlete disqualification alerts
  Stream<Map<String, dynamic>> get onPesertaDsq => _pesertaDsqController.stream;

  /// Stream of live scoreboard updates
  Stream<Map<String, dynamic>> get onSkorUpdate => _skorUpdateController.stream;

  /// Stream of Dewan verification start event
  Stream<Map<String, dynamic>> get onVerifikasiMulai => _verifikasiMulaiController.stream;

  /// Stream of Juri verification vote cast event
  Stream<Map<String, dynamic>> get onVerifikasiVote => _verifikasiVoteController.stream;

  /// Stream of Dewan verification completed/consensus result event
  Stream<Map<String, dynamic>> get onVerifikasiSelesai => _verifikasiSelesaiController.stream;

  /// Stream of Match Timer Control events (Mulai, Jeda/Pause, Lanjut/Resume, Reset)
  Stream<Map<String, dynamic>> get onTimerControl => _timerControlController.stream;

  final _babakChangedController = StreamController<Map<String, dynamic>>.broadcast();

  /// Stream of Babak / Round change events (Babak 1, Babak 2, Babak 3)
  Stream<Map<String, dynamic>> get onBabakChanged => _babakChangedController.stream;

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

    // ── Gelanggang status updates ──
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

    // ── Score created & confirmed events ──
    _socket!.on('nilai:created', (data) {
      debugPrint('[Socket] nilai:created received: $data');
      try {
        if (data is Map<String, dynamic>) {
          final nilai = Nilai.fromJson(data);
          _nilaiCreatedController.add(nilai);
        } else if (data is Map) {
          final nilai = Nilai.fromJson(Map<String, dynamic>.from(data));
          _nilaiCreatedController.add(nilai);
        }
      } catch (e) {
        debugPrint('[Socket] Error parsing nilai:created: $e');
      }
    });

    _socket!.on('nilai:sah', (data) {
      debugPrint('[Socket] nilai:sah received: $data');
      try {
        if (data is Map<String, dynamic>) {
          final nilai = Nilai.fromJson(data);
          _nilaiCreatedController.add(nilai);
        } else if (data is Map) {
          final nilai = Nilai.fromJson(Map<String, dynamic>.from(data));
          _nilaiCreatedController.add(nilai);
        }
      } catch (e) {
        debugPrint('[Socket] Error parsing nilai:sah: $e');
      }
    });

    // ── Juri consensus voting events ──
    _socket!.on('juri:vote:buffered', (data) {
      debugPrint('[Socket] juri:vote:buffered received: $data');
      if (data is Map<String, dynamic>) {
        _juriVoteBufferedController.add(data);
      } else if (data is Map) {
        _juriVoteBufferedController.add(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('juri:vote:confirm', (data) {
      debugPrint('[Socket] juri:vote:confirm received: $data');
      if (data is Map<String, dynamic>) {
        _juriVoteConfirmController.add(data);
      } else if (data is Map) {
        _juriVoteConfirmController.add(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('juri:vote:rejected', (data) {
      debugPrint('[Socket] juri:vote:rejected received: $data');
      if (data is Map<String, dynamic>) {
        _juriVoteRejectedController.add(data);
      } else if (data is Map) {
        _juriVoteRejectedController.add(Map<String, dynamic>.from(data));
      }
    });

    // ── KP discipline & match events ──
    _socket!.on('kp:status', (data) {
      debugPrint('[Socket] kp:status received: $data');
      if (data is Map<String, dynamic>) {
        _kpStatusController.add(data);
      } else if (data is Map) {
        _kpStatusController.add(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('peserta:dsq', (data) {
      debugPrint('[Socket] peserta:dsq received: $data');
      if (data is Map<String, dynamic>) {
        _pesertaDsqController.add(data);
      } else if (data is Map) {
        _pesertaDsqController.add(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('skor:update', (data) {
      debugPrint('[Socket] skor:update received: $data');
      if (data is Map<String, dynamic>) {
        _skorUpdateController.add(data);
      } else if (data is Map) {
        _skorUpdateController.add(Map<String, dynamic>.from(data));
      }
    });

    // ── Dewan Verification (Jatuhan / Pelanggaran) events ──
    // Only listen to 'verifikasi:mulai' — removed 'verifikasi:jatuhan' alias to prevent double-fire
    _socket!.on('verifikasi:mulai', (data) {
      debugPrint('[Socket] verifikasi:mulai received: $data');
      if (data is Map<String, dynamic>) {
        _verifikasiMulaiController.add(data);
      } else if (data is Map) {
        _verifikasiMulaiController.add(Map<String, dynamic>.from(data));
      }
    });

    // ── KP nilai persisted — broadcast to Monitor/Juri for realtime sync ──
    _socket!.on('nilai:kp', (data) {
      debugPrint('[Socket] nilai:kp received: $data');
      if (data is Map<String, dynamic>) {
        _nilaiKpController.add(data);
      } else if (data is Map) {
        _nilaiKpController.add(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('verifikasi:vote', (data) {
      debugPrint('[Socket] verifikasi:vote received: $data');
      if (data is Map<String, dynamic>) {
        _verifikasiVoteController.add(data);
      } else if (data is Map) {
        _verifikasiVoteController.add(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('verifikasi:selesai', (data) {
      debugPrint('[Socket] verifikasi:selesai received: $data');
      if (data is Map<String, dynamic>) {
        _verifikasiSelesaiController.add(data);
      } else if (data is Map) {
        _verifikasiSelesaiController.add(Map<String, dynamic>.from(data));
      }
    });

    // ── Timer Control Sync events (Mulai, Jeda/Pause, Lanjut/Resume, Reset) ──
    _socket!.on('timer:control', (data) {
      debugPrint('[Socket] timer:control received: $data');
      if (data is Map<String, dynamic>) {
        _timerControlController.add(data);
      } else if (data is Map) {
        _timerControlController.add(Map<String, dynamic>.from(data));
      }
    });

    // ── Babak / Round Change events (Babak 1, Babak 2, Babak 3) ──
    _socket!.on('babak:change', (data) {
      debugPrint('[Socket] babak:change received: $data');
      if (data is Map<String, dynamic>) {
        _babakChangedController.add(data);
      } else if (data is Map) {
        _babakChangedController.add(Map<String, dynamic>.from(data));
      }
    });

    // ── Match Completion / Finished events ──
    _socket!.on('pertandingan:selesai', (data) {
      debugPrint('[Socket] pertandingan:selesai received: $data');
      if (data is Map<String, dynamic>) {
        _pertandinganSelesaiController.add(data);
      } else if (data is Map) {
        _pertandinganSelesaiController.add(Map<String, dynamic>.from(data));
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

  /// Emit jury vote event to server for real-time 2-out-of-3 consensus evaluation
  void emitJuriVote(Map<String, dynamic> payload) {
    if (_socket != null && _isConnected) {
      _socket!.emit('juri:vote', payload);
      debugPrint('[Socket] Emitted juri:vote -> $payload');
    } else {
      debugPrint('[Socket] Cannot emit juri:vote: not connected');
    }
  }

  /// Emit KP action event to server for discipline penalties or bonuses
  void emitKpAction(Map<String, dynamic> payload) {
    if (_socket != null && _isConnected) {
      _socket!.emit('kp:action', payload);
      debugPrint('[Socket] Emitted kp:action -> $payload');
    } else {
      debugPrint('[Socket] Cannot emit kp:action: not connected');
    }
  }

  /// Emit KP status update event (sanction counters sync for binaan, teguran, peringatan)
  void emitKpStatus(Map<String, dynamic> payload) {
    if (_socket != null && _isConnected) {
      _socket!.emit('kp:status', payload);
      debugPrint('[Socket] Emitted kp:status -> $payload');
    } else {
      debugPrint('[Socket] Cannot emit kp:status: not connected');
    }
  }

  /// Emit Dewan Verification Start event (Verifikasi Jatuhan / Pelanggaran)
  void emitVerifikasiMulai(Map<String, dynamic> payload) {
    if (_socket != null && _isConnected) {
      _socket!.emit('verifikasi:mulai', payload);
      debugPrint('[Socket] Emitted verifikasi:mulai -> $payload');
    } else {
      debugPrint('[Socket] Cannot emit verifikasi:mulai: not connected');
    }
  }

  /// Emit nilai:kp event — broadcast KP score deduction to Monitor/Juri screens
  void emitNilaiKp(Map<String, dynamic> payload) {
    if (_socket != null && _isConnected) {
      _socket!.emit('nilai:kp', payload);
      debugPrint('[Socket] Emitted nilai:kp -> $payload');
    } else {
      debugPrint('[Socket] Cannot emit nilai:kp: not connected');
    }
  }

  /// Emit Juri Verification Vote event
  void emitVerifikasiVote(Map<String, dynamic> payload) {
    if (_socket != null && _isConnected) {
      _socket!.emit('verifikasi:vote', payload);
      debugPrint('[Socket] Emitted verifikasi:vote -> $payload');
    } else {
      debugPrint('[Socket] Cannot emit verifikasi:vote: not connected');
    }
  }

  /// Emit Dewan Verification Completed / Consensus Result event
  void emitVerifikasiSelesai(Map<String, dynamic> payload) {
    if (_socket != null && _isConnected) {
      _socket!.emit('verifikasi:selesai', payload);
      debugPrint('[Socket] Emitted verifikasi:selesai -> $payload');
    } else {
      debugPrint('[Socket] Cannot emit verifikasi:selesai: not connected');
    }
  }

  /// Emit Match Timer Synchronized Control event (Mulai, Jeda/Pause, Lanjut/Resume, Reset)
  void emitTimerControl(Map<String, dynamic> payload) {
    if (_socket != null && _isConnected) {
      _socket!.emit('timer:control', payload);
      debugPrint('[Socket] Emitted timer:control -> $payload');
    } else {
      debugPrint('[Socket] Cannot emit timer:control: not connected');
    }
  }

  /// Emit Match Completion / Selesai event
  void emitPertandinganSelesai(Map<String, dynamic> payload) {
    if (_socket != null && _isConnected) {
      _socket!.emit('pertandingan:selesai', payload);
      debugPrint('[Socket] Emitted pertandingan:selesai -> $payload');
    } else {
      debugPrint('[Socket] Cannot emit pertandingan:selesai: not connected');
    }
  }

  /// Emit Babak / Round Change event (Babak 1, Babak 2, Babak 3)
  void emitBabakChange(Map<String, dynamic> payload) {
    if (_socket != null && _isConnected) {
      _socket!.emit('babak:change', payload);
      debugPrint('[Socket] Emitted babak:change -> $payload');
    } else {
      debugPrint('[Socket] Cannot emit babak:change: not connected');
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
    _juriVoteBufferedController.close();
    _juriVoteConfirmController.close();
    _juriVoteRejectedController.close();
    _kpStatusController.close();
    _pesertaDsqController.close();
    _skorUpdateController.close();
    _verifikasiMulaiController.close();
    _verifikasiVoteController.close();
    _verifikasiSelesaiController.close();
    _timerControlController.close();
    _babakChangedController.close();
    _pertandinganSelesaiController.close();
    _nilaiKpController.close();
  }
}
