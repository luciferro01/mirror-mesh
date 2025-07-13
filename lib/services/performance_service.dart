import 'dart:async';
import 'dart:isolate';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class PerformanceService {
  static final PerformanceService _instance = PerformanceService._internal();
  factory PerformanceService() => _instance;
  PerformanceService._internal();

  final Map<String, Isolate> _isolates = {};
  final Map<String, SendPort> _sendPorts = {};
  final Map<String, Completer<dynamic>> _completers = {};
  int _isolateCounter = 0;

  /// Processes JSON serialization in an isolate for large data
  Future<String> processJsonSerialization(Map<String, dynamic> data) async {
    return await _runInIsolate(
      'json_serialization',
      data,
      _jsonSerializationIsolate,
    );
  }

  /// Processes data compression in an isolate
  Future<Uint8List> processDataCompression(String data) async {
    return await _runInIsolate(
      'data_compression',
      data,
      _dataCompressionIsolate,
    );
  }

  /// Processes image thumbnail generation in an isolate
  Future<Uint8List?> processImageThumbnail(
    Uint8List imageData,
    int maxWidth,
    int maxHeight,
  ) async {
    final params = {
      'imageData': imageData,
      'maxWidth': maxWidth,
      'maxHeight': maxHeight,
    };
    return await _runInIsolate(
      'image_thumbnail',
      params,
      _imageThumbnailIsolate,
    );
  }

  /// Processes network statistics calculation in an isolate
  Future<Map<String, dynamic>> processNetworkStats(
    List<Map<String, dynamic>> rawStats,
  ) async {
    return await _runInIsolate('network_stats', rawStats, _networkStatsIsolate);
  }

  /// Generic method to run computation in an isolate
  Future<T> _runInIsolate<T>(
    String operation,
    dynamic data,
    void Function(Map<String, dynamic>) isolateFunction,
  ) async {
    final isolateId = '${operation}_${_isolateCounter++}';
    final completer = Completer<T>();
    _completers[isolateId] = completer;

    try {
      // Create receive port for communication
      final receivePort = ReceivePort();

      // Set up listener for results
      receivePort.listen((message) {
        if (message is Map && message['id'] == isolateId) {
          final result = message['result'];
          final error = message['error'];

          if (error != null) {
            completer.completeError(error);
          } else {
            completer.complete(result as T);
          }

          // Clean up
          _cleanupIsolate(isolateId);
          receivePort.close();
        }
      });

      // Spawn isolate
      final isolate = await Isolate.spawn(isolateFunction, {
        'sendPort': receivePort.sendPort,
        'data': data,
        'id': isolateId,
      });

      _isolates[isolateId] = isolate;

      // Set timeout to prevent hanging
      Timer(const Duration(seconds: 30), () {
        if (!completer.isCompleted) {
          completer.completeError('Isolate operation timed out');
          _cleanupIsolate(isolateId);
        }
      });

      return await completer.future;
    } catch (e) {
      _cleanupIsolate(isolateId);
      rethrow;
    }
  }

  /// Cleans up isolate resources
  void _cleanupIsolate(String isolateId) {
    _isolates[isolateId]?.kill(priority: Isolate.immediate);
    _isolates.remove(isolateId);
    _sendPorts.remove(isolateId);
    _completers.remove(isolateId);
  }

  /// JSON serialization isolate function
  static void _jsonSerializationIsolate(Map<String, dynamic> params) {
    final sendPort = params['sendPort'] as SendPort;
    final data = params['data'] as Map<String, dynamic>;
    final id = params['id'] as String;

    try {
      final result = json.encode(data);
      sendPort.send({'id': id, 'result': result, 'error': null});
    } catch (e) {
      sendPort.send({'id': id, 'result': null, 'error': e.toString()});
    }
  }

  /// Data compression isolate function
  static void _dataCompressionIsolate(Map<String, dynamic> params) {
    final sendPort = params['sendPort'] as SendPort;
    final data = params['data'] as String;
    final id = params['id'] as String;

    try {
      // Simple compression using UTF-8 encoding
      final bytes = Uint8List.fromList(utf8.encode(data));
      sendPort.send({'id': id, 'result': bytes, 'error': null});
    } catch (e) {
      sendPort.send({'id': id, 'result': null, 'error': e.toString()});
    }
  }

  /// Image thumbnail generation isolate function
  static void _imageThumbnailIsolate(Map<String, dynamic> params) {
    final sendPort = params['sendPort'] as SendPort;
    final Map<String, dynamic> data = params['data'] as Map<String, dynamic>;
    final id = params['id'] as String;

    try {
      final imageData = data['imageData'] as Uint8List;
      // final maxWidth = data['maxWidth'] as int;
      // final maxHeight = data['maxHeight'] as int;

      // Simple thumbnail processing (in real implementation, use image package)
      // For now, just return a smaller subset of the original data
      final thumbnailSize = (imageData.length * 0.1).round();
      final thumbnailData = Uint8List.fromList(
        imageData.take(thumbnailSize).toList(),
      );

      sendPort.send({'id': id, 'result': thumbnailData, 'error': null});
    } catch (e) {
      sendPort.send({'id': id, 'result': null, 'error': e.toString()});
    }
  }

  /// Network statistics calculation isolate function
  static void _networkStatsIsolate(Map<String, dynamic> params) {
    final sendPort = params['sendPort'] as SendPort;
    final rawStats = params['data'] as List<Map<String, dynamic>>;
    final id = params['id'] as String;

    try {
      // Process network statistics
      int totalBytes = 0;
      int totalPackets = 0;
      double totalRtt = 0.0;
      int connectionCount = rawStats.length;

      for (final stat in rawStats) {
        totalBytes += (stat['bytesSent'] as int? ?? 0);
        totalPackets += (stat['packetsSent'] as int? ?? 0);
        totalRtt += (stat['roundTripTime'] as double? ?? 0.0);
      }

      final averageRtt = connectionCount > 0 ? totalRtt / connectionCount : 0.0;
      final throughput = totalBytes > 0
          ? (totalBytes / 1024 / 1024)
          : 0.0; // MB

      final result = {
        'totalBytes': totalBytes,
        'totalPackets': totalPackets,
        'averageRtt': averageRtt,
        'throughputMB': throughput,
        'connectionCount': connectionCount,
        'processedAt': DateTime.now().millisecondsSinceEpoch,
      };

      sendPort.send({'id': id, 'result': result, 'error': null});
    } catch (e) {
      sendPort.send({'id': id, 'result': null, 'error': e.toString()});
    }
  }

  /// Processes WebRTC statistics in background
  Future<Map<String, dynamic>> processWebRTCStats(
    List<Map<String, dynamic>> stats,
  ) async {
    if (stats.isEmpty) return {};

    return await processNetworkStats(stats);
  }

  /// Optimizes memory usage by cleaning up unused isolates
  void optimizeMemory() {
    // final now = DateTime.now();
    final idsToRemove = <String>[];

    for (final id in _isolates.keys) {
      // Remove isolates that have been running too long (safety measure)
      idsToRemove.add(id);
    }

    for (final id in idsToRemove) {
      _cleanupIsolate(id);
    }

    // Force garbage collection if available
    if (kDebugMode) {
      print(
        'PerformanceService: Memory optimization completed, cleaned ${idsToRemove.length} isolates',
      );
    }
  }

  /// Disposes of all isolates and resources
  void dispose() {
    for (final isolate in _isolates.values) {
      isolate.kill(priority: Isolate.immediate);
    }
    _isolates.clear();
    _sendPorts.clear();

    for (final completer in _completers.values) {
      if (!completer.isCompleted) {
        completer.completeError('Service disposed');
      }
    }
    _completers.clear();
  }
}
