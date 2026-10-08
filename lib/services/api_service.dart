import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import '../config/env.dart';

/// API Service — Replika dari useApiService.ts Nuxt.
/// Handles all REST API communication with Strapi backend.
/// Supports re-initialization when switching between Online/Offline modes.
class ApiService {
  static ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late Dio _dio;

  ApiService._internal() {
    _initDio();
  }

  void _initDio() {
    _dio = Dio(BaseOptions(
      baseUrl: Env.apiUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
      },
    ));

    // Ensure cleartext HTTP and local static DNS certificates succeed on mobile/desktop
    if (!kIsWeb) {
      final adapter = _dio.httpClientAdapter;
      if (adapter is IOHttpClientAdapter) {
        adapter.createHttpClient = () {
          final client = HttpClient();
          client.badCertificateCallback = (cert, host, port) => true;
          return client;
        };
      }
    }
  }

  /// Re-initialize Dio with the current Env URL (call after mode switch).
  static void reinitialize() {
    _instance = ApiService._internal();
  }

  /// Headers with static protection token (same as Nuxt's fetchWithNoAuth)
  Map<String, String> get _protectHeaders => {
        'Authorization': 'Bearer ${Env.tokenProtect}',
      };

  // ── READ (Find) ──

  /// Find multiple records from a collection.
  /// Equivalent to Nuxt's `findProtect(collection, params)`
  Future<Map<String, dynamic>> findProtect(
    String collection, {
    Map<String, dynamic>? params,
  }) async {
    final response = await _dio.get(
      '/$collection',
      queryParameters: params,
      options: Options(headers: _protectHeaders),
    );
    return response.data as Map<String, dynamic>;
  }

  /// Find one record by ID from a collection.
  /// Equivalent to Nuxt's `findOneProtect(collection, id, params)`
  Future<Map<String, dynamic>> findOneProtect(
    String collection,
    String id, {
    Map<String, dynamic>? params,
  }) async {
    final response = await _dio.get(
      '/$collection/$id',
      queryParameters: params,
      options: Options(headers: _protectHeaders),
    );
    return response.data as Map<String, dynamic>;
  }

  // ── CREATE ──

  /// Create a new record in a collection.
  /// Equivalent to Nuxt's createProtect(collection, payload)
  Future<Map<String, dynamic>> createProtect(
    String collection,
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.post(
      '/$collection',
      data: payload,
      options: Options(headers: _protectHeaders),
    );
    return response.data as Map<String, dynamic>;
  }

  // ── UPDATE ──

  /// Update a record by ID in a collection.
  /// Equivalent to Nuxt's updateProtect(collection, id, payload)
  Future<Map<String, dynamic>> updateProtect(
    String collection,
    String id,
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.put(
      '/$collection/$id',
      data: payload,
      options: Options(headers: _protectHeaders),
    );
    return response.data as Map<String, dynamic>;
  }

  // ── Custom endpoints ──

  /// Fetch sponsors for a given event.
  /// GET /sponsors?filters[event][documentId][$eq]={eventId}&populate=logo
  Future<List<dynamic>> fetchSponsorsByEvent(String eventDocumentId) async {
    try {
      final response = await _dio.get(
        '/sponsors',
        queryParameters: {
          'filters[event][documentId][\$eq]': eventDocumentId,
          'populate': 'logo',
          'pagination[pageSize]': 100,
        },
        options: Options(headers: _protectHeaders),
      );
      final data = response.data;
      if (data is List) return data;
      if (data is Map && data['data'] is List) return data['data'] as List;
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Fetch jadwal by event ID using custom backend endpoint.
  /// GET /jadwal/event/:eventId
  Future<List<dynamic>> fetchJadwalByEvent(String eventId) async {
    try {
      final response = await _dio.get(
        '/jadwal/event/$eventId',
        options: Options(
          headers: _protectHeaders,
          // Use base URL without /api prefix for custom endpoints
          // Actually the custom endpoint seems to be under /api too based on the Nuxt code
        ),
      );
      final data = response.data;
      if (data is List) return data;
      if (data is Map && data['data'] is List) return data['data'] as List;
      return [];
    } catch (e) {
      // Fallback will be handled by caller
      return [];
    }
  }
}
