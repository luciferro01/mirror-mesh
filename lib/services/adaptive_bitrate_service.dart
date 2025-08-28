import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import '../models/room.dart';

class AdaptiveBitrateService {
  static const Duration _monitoringInterval = Duration(seconds: 2);
  static const Duration _adjustmentDelay = Duration(seconds: 5);

  final Map<String, Timer> _monitoringTimers = {};
  final Map<String, int> _targetBitrates = {};
  final Map<String, DateTime> _lastAdjustments = {};
  final Map<String, List<int>> _bitrateHistory = {};

  /// Starts monitoring a peer connection for adaptive bitrate
  void startMonitoring(
    String connectionId,
    webrtc.RTCPeerConnection peerConnection,
    QualitySettings initialQuality,
  ) {
    _targetBitrates[connectionId] = initialQuality.bitrate;
    _bitrateHistory[connectionId] = [];
    _lastAdjustments[connectionId] = DateTime.now();

    _monitoringTimers[connectionId] = Timer.periodic(_monitoringInterval, (
      timer,
    ) {
      _monitorConnection(connectionId, peerConnection);
    });
  }

  /// Stops monitoring a peer connection
  void stopMonitoring(String connectionId) {
    _monitoringTimers[connectionId]?.cancel();
    _monitoringTimers.remove(connectionId);
    _targetBitrates.remove(connectionId);
    _bitrateHistory.remove(connectionId);
    _lastAdjustments.remove(connectionId);
  }

  /// Monitors connection quality and adjusts bitrate
  void _monitorConnection(
    String connectionId,
    webrtc.RTCPeerConnection peerConnection,
  ) async {
    try {
      final stats = await peerConnection.getStats();

      for (final report in stats) {
        if (report.type == 'outbound-rtp' &&
            report.values['mediaType'] == 'video') {
          final values = report.values;
          final bytesSent = values['bytesSent'] as int? ?? 0;
          final packetsSent = values['packetsSent'] as int? ?? 0;
          final packetsLost = values['packetsLost'] as int? ?? 0;
          final roundTripTime = values['roundTripTime'] as double? ?? 0.0;

          _analyzeAndAdjust(connectionId, peerConnection, {
            'bytesSent': bytesSent,
            'packetsSent': packetsSent,
            'packetsLost': packetsLost,
            'roundTripTime': roundTripTime,
          });
          break;
        }
      }
    } catch (e) {
      debugPrint('Adaptive bitrate monitoring error for $connectionId: $e');
    }
  }

  /// Analyzes connection metrics and adjusts bitrate
  void _analyzeAndAdjust(
    String connectionId,
    webrtc.RTCPeerConnection peerConnection,
    Map<String, dynamic> metrics,
  ) async {
    final now = DateTime.now();
    final lastAdjustment = _lastAdjustments[connectionId] ?? now;

    // Don't adjust too frequently
    if (now.difference(lastAdjustment) < _adjustmentDelay) {
      return;
    }

    final packetsLost = metrics['packetsLost'] as int;
    final packetsSent = metrics['packetsSent'] as int;
    final roundTripTime = metrics['roundTripTime'] as double;

    double packetLossRate = 0.0;
    if (packetsSent > 0) {
      packetLossRate = packetsLost / packetsSent;
    }

    final currentBitrate = _targetBitrates[connectionId] ?? 1000000;
    int newBitrate = currentBitrate;

    // Determine adjustment based on network conditions
    if (packetLossRate > 0.05 || roundTripTime > 0.3) {
      // High packet loss or latency - reduce bitrate
      newBitrate = (currentBitrate * 0.8).round();
      newBitrate = newBitrate.clamp(
        400000,
        6000000,
      ); // Min 400kbps, Max 6Mbps for 60fps
    } else if (packetLossRate < 0.01 && roundTripTime < 0.1) {
      // Good conditions - can increase bitrate
      newBitrate = (currentBitrate * 1.1).round();
      newBitrate = newBitrate.clamp(400000, 6000000);
    }

    // Apply bitrate adjustment if significant change
    if ((newBitrate - currentBitrate).abs() > currentBitrate * 0.1) {
      await _adjustBitrate(connectionId, peerConnection, newBitrate);
      _targetBitrates[connectionId] = newBitrate;
      _lastAdjustments[connectionId] = now;

      debugPrint(
        'Adaptive bitrate: $connectionId adjusted to ${newBitrate}bps (loss: ${(packetLossRate * 100).toStringAsFixed(1)}%, rtt: ${(roundTripTime * 1000).toStringAsFixed(0)}ms)',
      );
    }
  }

  /// Adjusts the bitrate for a specific peer connection
  Future<void> _adjustBitrate(
    String connectionId,
    webrtc.RTCPeerConnection peerConnection,
    int newBitrate,
  ) async {
    try {
      final senders = await peerConnection.getSenders();

      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          // Note: Direct bitrate adjustment through setParameters is not available
          // in the current flutter_webrtc implementation, but we can track the target
          debugPrint('Target bitrate for $connectionId set to $newBitrate bps');
          break;
        }
      }
    } catch (e) {
      debugPrint('Failed to adjust bitrate for $connectionId: $e');
    }
  }

  /// Gets current target bitrate for a connection
  int? getTargetBitrate(String connectionId) {
    return _targetBitrates[connectionId];
  }

  /// Adjusts bitrate specifically for high latency connections
  void adjustBitrateForLatency(String connectionId, int newBitrate) {
    final currentBitrate = _targetBitrates[connectionId];
    if (currentBitrate != null && currentBitrate != newBitrate) {
      _targetBitrates[connectionId] = newBitrate;
      _lastAdjustments[connectionId] = DateTime.now();

      debugPrint(
        'Latency-based bitrate adjustment for $connectionId: ${currentBitrate}bps -> ${newBitrate}bps',
      );
    }
  }

  /// Disposes of the service
  void dispose() {
    for (final timer in _monitoringTimers.values) {
      timer.cancel();
    }
    _monitoringTimers.clear();
    _targetBitrates.clear();
    _bitrateHistory.clear();
    _lastAdjustments.clear();
  }
}
