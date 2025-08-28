import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/connection.dart';
import '../models/room.dart';
import '../utils/code_generator.dart';
import 'adaptive_bitrate_service.dart';

class WebRTCService {
  static const Map<String, dynamic> _configuration = {
    'iceServers': [
      {
        'urls': [
          'stun:stun1.l.google.com:19302',
          'stun:stun2.l.google.com:19302',
        ],
      },
      // Add TURN servers for relay to reduce latency in restricted networks
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
    'bundlePolicy': 'max-bundle',
    'rtcpMuxPolicy': 'require',
    'iceCandidatePoolSize': 5, // Reduced for lower memory
    'iceTransportPolicy': 'all',
    'continualGatheringPolicy': 'gather_continually',
    'sdpSemantics': 'unified-plan',
    'enableDtlsSrtp': true,
    'enableRtpDataChannels': false,
  };

  static const Map<String, dynamic> _offerSdpConstraints = {
    'mandatory': {'OfferToReceiveAudio': false, 'OfferToReceiveVideo': false},
    'optional': [
      {'VoiceActivityDetection': false},
      {'IceRestart': true},
      // Latency optimizations
      {'DtlsSrtpKeyAgreement': true},
      {'googCpuOveruseDetection': true},
      {'googHighStartBitrate': 1000000}, // 1Mbps start bitrate
    ],
  };

  static const Map<String, dynamic> _answerSdpConstraints = {
    'mandatory': {'OfferToReceiveAudio': false, 'OfferToReceiveVideo': true},
    'optional': [
      {'VoiceActivityDetection': false},
      {'DtlsSrtpKeyAgreement': true},
      // Latency optimizations
      {'googCpuOveruseDetection': true},
      {'googHighStartBitrate': 1000000}, // 1Mbps start bitrate
    ],
  };

  // Stream controllers for events
  final StreamController<Connection> _connectionController =
      StreamController<Connection>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  final StreamController<WebRTCSignal> _signalController =
      StreamController<WebRTCSignal>.broadcast();

  // Limit to single connection
  static const int _maxConnections = 1;

  // Enhanced reconnection config
  static const Duration _reconnectionDelay = Duration(seconds: 1);
  static const int _maxReconnectionAttempts = 10;

  // State management
  final Map<String, webrtc.RTCPeerConnection> _peerConnections = {};
  final Map<String, Connection> _connections = {};
  webrtc.MediaStream? _localStream;
  String? _hostId;
  WebSocketChannel? _signalingChannel;
  final AdaptiveBitrateService _adaptiveBitrateService =
      AdaptiveBitrateService();
  QualitySettings? _currentQualitySettings;

  // Memory management
  Timer? _memoryCleanupTimer;
  Timer? _connectionHealthTimer;
  final Map<String, DateTime> _lastActivityTimestamps = {};
  final Map<String, int> _connectionQualityScores = {};

  // Reconnection tracking
  final Map<String, int> _reconnectionAttempts = {};

  // Getters for streams
  Stream<Connection> get connectionStream => _connectionController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<WebRTCSignal> get signalStream => _signalController.stream;

  // Getters for state
  Map<String, Connection> get connections => Map.unmodifiable(_connections);
  bool get hasLocalStream => _localStream != null;
  int get connectionCount => _connections.length;

  /// Initializes WebRTC service
  Future<void> initialize() async {
    try {
      await _initializeWebRTC();
      _startMemoryManagement();
      _startConnectionHealthMonitoring();
    } catch (e) {
      _errorController.add('Failed to initialize WebRTC: $e');
      rethrow;
    }
  }

  /// Starts memory management timer
  void _startMemoryManagement() {
    _memoryCleanupTimer?.cancel();
    _memoryCleanupTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      _performMemoryCleanup();
    });
  }

  /// Starts connection health monitoring
  void _startConnectionHealthMonitoring() {
    _connectionHealthTimer?.cancel();
    _connectionHealthTimer = Timer.periodic(const Duration(seconds: 30), (
      timer,
    ) {
      _monitorConnectionHealth();
    });
  }

  /// Performs memory cleanup
  void _performMemoryCleanup() {
    try {
      // Force garbage collection if available
      if (Platform.isMacOS || Platform.isLinux) {
        // On desktop platforms, we can be more aggressive with cleanup
        debugPrint('Performing memory cleanup...');
      }

      // Clean up inactive connections
      final now = DateTime.now();
      final inactiveConnections = <String>[];

      for (final entry in _lastActivityTimestamps.entries) {
        if (now.difference(entry.value) > const Duration(minutes: 10)) {
          inactiveConnections.add(entry.key);
        }
      }

      for (final connectionId in inactiveConnections) {
        debugPrint('Cleaning up inactive connection: $connectionId');
        removePeerConnection(connectionId);
      }
    } catch (e) {
      debugPrint('Error during memory cleanup: $e');
    }
  }

  /// Monitors connection health and optimizes performance
  void _monitorConnectionHealth() async {
    try {
      for (final connectionId in _connections.keys.toList()) {
        await _checkConnectionQuality(connectionId);
      }
    } catch (e) {
      debugPrint('Error monitoring connection health: $e');
    }
  }

  /// Checks and optimizes connection quality
  Future<void> _checkConnectionQuality(String connectionId) async {
    try {
      final peerConnection = _peerConnections[connectionId];
      if (peerConnection == null) return;

      final stats = await peerConnection.getStats();
      int qualityScore = 100;
      double fps = 0.0;

      for (final report in stats) {
        if (report.type == 'outbound-rtp' &&
            report.values['mediaType'] == 'video') {
          final values = report.values;
          final packetsLost = values['packetsLost'] as int? ?? 0;
          final packetsSent = values['packetsSent'] as int? ?? 1;
          final roundTripTime = values['roundTripTime'] as double? ?? 0.0;
          fps = values['framesPerSecond'] as double? ?? 0.0;

          // Calculate quality score based on metrics
          final packetLossRate = packetsLost / packetsSent;
          if (packetLossRate > 0.05) qualityScore -= 30;
          if (roundTripTime > 0.3) qualityScore -= 20;
          if (roundTripTime > 0.5) qualityScore -= 30;
          if (fps < (_currentQualitySettings?.frameRate ?? 30) * 0.8)
            qualityScore -= 20;

          _connectionQualityScores[connectionId] = qualityScore;

          // Optimize connection if quality is poor
          if (qualityScore < 50) {
            await _optimizeConnection(connectionId);
          }

          // Specific FPS optimization
          if (fps < (_currentQualitySettings?.frameRate ?? 30) * 0.8) {
            debugPrint(
              'Low FPS detected for $connectionId: $fps vs ${_currentQualitySettings?.frameRate}',
            );
            await _optimizeForFPS(connectionId);
          }

          break;
        }
      }

      // Update activity timestamp
      _lastActivityTimestamps[connectionId] = DateTime.now();
    } catch (e) {
      debugPrint('Error checking connection quality for $connectionId: $e');
    }
  }

  /// Optimizes for higher FPS
  Future<void> _optimizeForFPS(String connectionId) async {
    try {
      final peerConnection = _peerConnections[connectionId];
      if (peerConnection == null || _currentQualitySettings == null) return;

      // Restart negotiation with FPS priority
      final offer = await peerConnection.createOffer({
        'mandatory': {
          'OfferToReceiveVideo': true,
          'frameRate': _currentQualitySettings!.frameRate,
        },
        'optional': [
          {'googHighFrameRate': true},
          {'setFrameRate': _currentQualitySettings!.frameRate.toString()},
        ],
      });
      await peerConnection.setLocalDescription(offer);

      // Send new offer
      final connection = _connections[connectionId];
      if (connection != null) {
        final signal = WebRTCSignal.offer(
          roomCode: connection.roomCode,
          senderId: _hostId ?? '',
          receiverId: connection.viewerId,
          offer: offer,
        );
        _signalController.add(signal);
      }

      debugPrint('Optimized for higher FPS on $connectionId');
    } catch (e) {
      debugPrint('Error optimizing FPS for $connectionId: $e');
    }
  }

  /// Optimizes connection for better performance
  Future<void> _optimizeConnection(String connectionId) async {
    try {
      final peerConnection = _peerConnections[connectionId];
      if (peerConnection == null) return;

      // Reduce bitrate for poor quality connections
      if (_currentQualitySettings != null) {
        final reducedBitrate = (_currentQualitySettings!.bitrate * 0.6).round();
        _adaptiveBitrateService.adjustBitrateForLatency(
          connectionId,
          reducedBitrate,
        );
      }

      // Restart ICE if connection is very poor
      final qualityScore = _connectionQualityScores[connectionId] ?? 100;
      if (qualityScore < 30) {
        debugPrint('Restarting ICE for poor connection: $connectionId');
        await peerConnection.restartIce();
      }
    } catch (e) {
      debugPrint('Error optimizing connection $connectionId: $e');
    }
  }

  /// Initializes WebRTC platform
  Future<void> _initializeWebRTC() async {
    if (webrtc.WebRTC.platformIsDesktop) {
      await webrtc.WebRTC.initialize();
    }
  }

  /// Starts screen sharing as host
  Future<webrtc.MediaStream> startScreenShare(
    ScreenSource screenSource,
    QualitySettings qualitySettings,
  ) async {
    try {
      final Map<String, dynamic> constraints = {
        'video': {
          'mandatory': {
            'chromeMediaSource': 'desktop',
            'chromeMediaSourceId': screenSource.id,
            'maxWidth': qualitySettings.width,
            'maxHeight': qualitySettings.height,
            'maxFrameRate': qualitySettings.frameRate,
            'minFrameRate': qualitySettings.frameRate >= 60
                ? 30
                : 15, // Higher minimum for 60fps
            // Explicit frame rate for macOS
            'frameRate': qualitySettings.frameRate.toDouble(),
          },
          'optional': [
            // Performance optimizations
            {'googCpuOveruseDetection': true},
            {'googScreencastMinBitrate': qualitySettings.bitrate ~/ 2},
            {'googHighBitrate': qualitySettings.bitrate},
            {'googVeryHighBitrate': qualitySettings.bitrate * 2},
            {'googPayloadPadding': true},
            {'googHighStartBitrate': qualitySettings.bitrate},
            {'googBandwidthLimitedResolution': true},
            {'googContentHint': 'motion'}, // Optimize for motion content
            // Latency optimizations
            {'googLowLatency': true},
            {'googCpuOveruseDetection': true},
            {'googScreencastMinBitrate': 300000},

            // Disable unnecessary processing
            {'googNoiseReduction': false},
            {'googEchoCancellation': false},
            {'googAutoGainControl': false},
            {'googHighpassFilter': false},
            {'googTypingNoiseDetection': false},
            {'googExperimentalEchoCancellation': false},

            // Memory optimizations
            {'googMaxBitrate': qualitySettings.bitrate},
            {'googMinBitrate': qualitySettings.bitrate ~/ 4},

            // Force FPS
            {'frameRate': qualitySettings.frameRate.toString()},
            {'minFrameRate': qualitySettings.frameRate.toString()},
            {'maxFrameRate': qualitySettings.frameRate.toString()},
            {'setFrameRate': qualitySettings.frameRate.toString()},
            {'googScreencastFrameRate': qualitySettings.frameRate.toString()},
          ],
        },
        'audio': false,
      };

      // For ultra quality, add extra parameters
      if (qualitySettings.quality == VideoQuality.high &&
          qualitySettings.frameRate == 60) {
        constraints['video']['mandatory']['frameRate'] = 60.0;
        constraints['video']['optional'].addAll([
          {'setStartFrameRate': '60'},
          {'googHighFrameRate': true},
          {'googScreencastMinBitrate': '4000000'},
        ]);
      }

      debugPrint('Starting screen share with constraints: $constraints');

      _localStream = await webrtc.navigator.mediaDevices.getDisplayMedia(
        constraints,
      );

      // Verify applied FPS
      final videoTrack = _localStream!.getVideoTracks().first;
      final settings = videoTrack.getSettings();
      debugPrint('Applied video settings: $settings');

      _hostId = CodeGenerator.generateId();
      _currentQualitySettings = qualitySettings;

      return _localStream!;
    } catch (e) {
      _errorController.add('Failed to start screen sharing: $e');
      rethrow;
    }
  }

  /// Changes screen source without interrupting connections
  Future<void> changeScreenSource(
    ScreenSource screenSource,
    QualitySettings qualitySettings,
  ) async {
    try {
      if (_localStream == null) {
        throw Exception('No active screen sharing session');
      }

      // Create new stream with different source
      final Map<String, dynamic> constraints = {
        'video': {
          'mandatory': {
            'chromeMediaSource': 'desktop',
            'chromeMediaSourceId': screenSource.id,
            'maxWidth': qualitySettings.width,
            'maxHeight': qualitySettings.height,
            'maxFrameRate': qualitySettings.frameRate,
            'minFrameRate': qualitySettings.frameRate >= 60
                ? 30
                : 15, // Higher minimum for 60fps
          },
          'optional': [
            {'googCpuOveruseDetection': true},
            {'googScreencastMinBitrate': qualitySettings.bitrate ~/ 2},
            {'googHighBitrate': qualitySettings.bitrate},
            {'googVeryHighBitrate': qualitySettings.bitrate * 2},
            {'googPayloadPadding': true},
            {'googHighStartBitrate': qualitySettings.bitrate},
            {'googBandwidthLimitedResolution': true},
            {'googContentHint': 'motion'}, // Optimize for motion content
            {
              'googNoiseReduction': false,
            }, // Disable noise reduction for better performance
            {
              'googEchoCancellation': false,
            }, // Disable echo cancellation (not needed for screen share)
            {'googAutoGainControl': false}, // Disable auto gain control
            {'googHighpassFilter': false}, // Disable high-pass filter
            {
              'googTypingNoiseDetection': false,
            }, // Disable typing noise detection
            {
              'googExperimentalEchoCancellation': false,
            }, // Disable experimental echo cancellation
          ],
        },
        'audio': false,
      };

      final newStream = await webrtc.navigator.mediaDevices.getDisplayMedia(
        constraints,
      );

      // Replace tracks in all peer connections
      final newVideoTrack = newStream.getVideoTracks().first;
      for (final peerConnection in _peerConnections.values) {
        final senders = await peerConnection.getSenders();
        for (final sender in senders) {
          if (sender.track?.kind == 'video') {
            await sender.replaceTrack(newVideoTrack);
          }
        }
      }

      // Dispose old stream and update reference
      await _localStream!.dispose();
      _localStream = newStream;

      // Update all connections
      for (final connection in _connections.values) {
        final updatedConnection = connection.copyWith(
          localStream: _localStream,
        );
        _connections[connection.id] = updatedConnection;
        _connectionController.add(updatedConnection);
      }
    } catch (e) {
      _errorController.add('Failed to change screen source: $e');
      rethrow;
    }
  }

  /// Stops screen sharing
  Future<void> stopScreenShare() async {
    try {
      if (_localStream != null) {
        await _localStream!.dispose();
        _localStream = null;
      }

      // Close all peer connections
      for (final connection in _peerConnections.values) {
        await connection.close();
      }
      _peerConnections.clear();
      _connections.clear();

      // Clear state
      _lastActivityTimestamps.clear();
      _connectionQualityScores.clear();

      _hostId = null;
    } catch (e) {
      _errorController.add('Failed to stop screen sharing: $e');
    }
  }

  /// Creates a new peer connection for a viewer
  Future<Connection> createPeerConnection(
    String viewerId,
    String roomCode,
  ) async {
    try {
      // Check connection limit
      if (_connections.length >= _maxConnections) {
        debugPrint('Maximum connections reached, rejecting new connection');
        throw Exception('Maximum connections reached');
      }

      final connectionId = CodeGenerator.generateConnectionId(
        roomCode,
        viewerId,
      );

      final peerConnection = await webrtc.createPeerConnection(
        _configuration,
        {},
      );

      // Set up event handlers
      peerConnection.onConnectionState = (webrtc.RTCPeerConnectionState state) {
        _handleConnectionStateChange(connectionId, state);
      };

      peerConnection.onIceCandidate = (webrtc.RTCIceCandidate candidate) {
        _handleIceCandidate(connectionId, candidate);
      };

      peerConnection.onIceConnectionState =
          (webrtc.RTCIceConnectionState state) {
            _handleIceConnectionState(connectionId, state);
          };

      peerConnection.onTrack = (webrtc.RTCTrackEvent event) {
        debugPrint('Track added: ${event.track.kind} - ${event.track.id}');
        // Monitor track state
        event.track.onEnded = () {
          debugPrint('Track ended unexpectedly for $connectionId');
          _handleTrackEnded(connectionId);
        };
      };

      // Add local stream tracks with optimized configuration
      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          await peerConnection.addTrack(track, _localStream!);
        }
      }

      _peerConnections[connectionId] = peerConnection;

      final connection = Connection(
        id: connectionId,
        viewerId: viewerId,
        roomCode: roomCode,
        connectedAt: DateTime.now(),
        status: ConnectionStatus.connecting,
        peerConnection: peerConnection,
        localStream: _localStream,
      );

      _connections[connectionId] = connection;
      _connectionController.add(connection);

      // Initialize state tracking
      _lastActivityTimestamps[connectionId] = DateTime.now();
      _connectionQualityScores[connectionId] = 100;
      _reconnectionAttempts[connectionId] = 0;

      // Start adaptive bitrate monitoring
      if (_currentQualitySettings != null) {
        _adaptiveBitrateService.startMonitoring(
          connectionId,
          peerConnection,
          _currentQualitySettings!,
        );
      }

      return connection;
    } catch (e) {
      _errorController.add('Failed to create peer connection: $e');
      rethrow;
    }
  }

  /// Creates an offer for a peer connection
  Future<webrtc.RTCSessionDescription> createOffer(String connectionId) async {
    try {
      final peerConnection = _peerConnections[connectionId];
      if (peerConnection == null) {
        throw Exception('Peer connection not found for ID: $connectionId');
      }

      final offer = await peerConnection.createOffer(_offerSdpConstraints);
      await peerConnection.setLocalDescription(offer);

      return offer;
    } catch (e) {
      _errorController.add('Failed to create offer: $e');
      rethrow;
    }
  }

  /// Creates an answer for a peer connection
  Future<webrtc.RTCSessionDescription> createAnswer(String connectionId) async {
    try {
      final peerConnection = _peerConnections[connectionId];
      if (peerConnection == null) {
        throw Exception('Peer connection not found for ID: $connectionId');
      }

      final answer = await peerConnection.createAnswer(_answerSdpConstraints);
      await peerConnection.setLocalDescription(answer);

      return answer;
    } catch (e) {
      _errorController.add('Failed to create answer: $e');
      rethrow;
    }
  }

  /// Sets remote description for a peer connection
  Future<void> setRemoteDescription(
    String connectionId,
    webrtc.RTCSessionDescription description,
  ) async {
    try {
      final peerConnection = _peerConnections[connectionId];
      if (peerConnection == null) {
        throw Exception('Peer connection not found for ID: $connectionId');
      }

      await peerConnection.setRemoteDescription(description);
    } catch (e) {
      _errorController.add('Failed to set remote description: $e');
      rethrow;
    }
  }

  /// Adds ICE candidate to a peer connection
  Future<void> addIceCandidate(
    String connectionId,
    webrtc.RTCIceCandidate candidate,
  ) async {
    try {
      final peerConnection = _peerConnections[connectionId];
      if (peerConnection == null) {
        throw Exception('Peer connection not found for ID: $connectionId');
      }

      await peerConnection.addCandidate(candidate);
    } catch (e) {
      _errorController.add('Failed to add ICE candidate: $e');
      rethrow;
    }
  }

  /// Removes a peer connection
  Future<void> removePeerConnection(String connectionId) async {
    try {
      // Stop adaptive bitrate monitoring
      _adaptiveBitrateService.stopMonitoring(connectionId);

      final peerConnection = _peerConnections.remove(connectionId);
      if (peerConnection != null) {
        await peerConnection.close();
      }

      final connection = _connections.remove(connectionId);
      if (connection != null) {
        final updatedConnection = connection.copyWith(
          status: ConnectionStatus.disconnected,
        );
        _connectionController.add(updatedConnection);
      }

      // Clean up state
      _lastActivityTimestamps.remove(connectionId);
      _connectionQualityScores.remove(connectionId);
    } catch (e) {
      _errorController.add('Failed to remove peer connection: $e');
    }
  }

  /// Handles connection state changes
  void _handleConnectionStateChange(
    String connectionId,
    webrtc.RTCPeerConnectionState state,
  ) {
    final connection = _connections[connectionId];
    if (connection == null) return;

    ConnectionStatus status;
    switch (state) {
      case webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        status = ConnectionStatus.connected;
        debugPrint('WebRTC: Connection $connectionId established successfully');
        break;
      case webrtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        status = ConnectionStatus.disconnected;
        debugPrint(
          'WebRTC: Connection $connectionId disconnected, attempting reconnection...',
        );
        _attemptReconnection(connectionId);
        break;
      case webrtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        status = ConnectionStatus.error;
        debugPrint(
          'WebRTC: Connection $connectionId failed, attempting recovery...',
        );
        _attemptReconnection(connectionId);
        break;
      case webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        status = ConnectionStatus.connecting;
        break;
      default:
        return;
    }

    final updatedConnection = connection.copyWith(status: status);
    _connections[connectionId] = updatedConnection;
    _connectionController.add(updatedConnection);
  }

  /// Attempts to reconnect a failed connection
  void _attemptReconnection(String connectionId) async {
    final connection = _connections[connectionId];
    if (connection == null) return;

    final attempts = _reconnectionAttempts[connectionId] ?? 0;
    if (attempts >= _maxReconnectionAttempts) {
      debugPrint('Max reconnection attempts reached for $connectionId');
      await removePeerConnection(connectionId);
      return;
    }

    try {
      // Increment reconnection attempts
      _reconnectionAttempts[connectionId] = attempts + 1;

      // Mark as reconnecting
      final reconnectingConnection = connection.copyWith(
        status: ConnectionStatus.reconnecting,
      );
      _connections[connectionId] = reconnectingConnection;
      _connectionController.add(reconnectingConnection);

      // Shorter delay for single connection
      await Future.delayed(_reconnectionDelay);

      // Check if connection still exists and needs reconnection
      final currentConnection = _connections[connectionId];
      if (currentConnection == null ||
          currentConnection.status == ConnectionStatus.connected) {
        return;
      }

      // Restart ICE gathering
      final peerConnection = _peerConnections[connectionId];
      if (peerConnection != null) {
        await peerConnection.restartIce();

        // Re-add tracks if they're missing
        if (_localStream != null) {
          final senders = await peerConnection.getSenders();
          if (senders.isEmpty) {
            for (final track in _localStream!.getTracks()) {
              await peerConnection.addTrack(track, _localStream!);
            }
          }
        }

        // Create new offer for reconnection
        final offer = await peerConnection.createOffer(_offerSdpConstraints);
        await peerConnection.setLocalDescription(offer);

        // Send reconnection offer
        final signal = WebRTCSignal.offer(
          roomCode: connection.roomCode,
          senderId: _hostId ?? '',
          receiverId: connection.viewerId,
          offer: offer,
        );
        _signalController.add(signal);

        // Refresh stream
        if (_localStream != null) {
          final tracks = _localStream!.getTracks();
          for (final track in tracks) {
            track.enabled = false;
            await Future.delayed(const Duration(milliseconds: 50));
            track.enabled = true;
          }
        }
      }
    } catch (e) {
      _errorController.add('Reconnection failed for $connectionId: $e');
      // Retry immediately for single connection
      if (_connections.length <= 1) {
        await Future.delayed(const Duration(milliseconds: 500));
        _attemptReconnection(connectionId);
      }
    }
  }

  /// Handles ICE candidate events
  void _handleIceCandidate(
    String connectionId,
    webrtc.RTCIceCandidate candidate,
  ) {
    final connection = _connections[connectionId];
    if (connection == null) return;

    final signal = WebRTCSignal.iceCandidate(
      roomCode: connection.roomCode,
      senderId: _hostId ?? '',
      receiverId: connection.viewerId,
      candidate: candidate,
    );

    _signalController.add(signal);
  }

  /// Handles ICE connection state changes
  void _handleIceConnectionState(
    String connectionId,
    webrtc.RTCIceConnectionState state,
  ) {
    // Additional handling for ICE connection state if needed
  }

  /// Gets available screen sources
  Future<List<ScreenSource>> getScreenSources() async {
    try {
      final sources = await webrtc.desktopCapturer.getSources(
        types: [webrtc.SourceType.Screen, webrtc.SourceType.Window],
      );

      return sources
          .map(
            (source) => ScreenSource(
              id: source.id,
              name: source.name,
              type: source.type == webrtc.SourceType.Screen
                  ? ScreenSourceType.screen
                  : ScreenSourceType.window,
              thumbnail: source.thumbnail,
            ),
          )
          .toList();
    } catch (e) {
      _errorController.add('Failed to get screen sources: $e');
      return [];
    }
  }

  /// Handles track ended events
  void _handleTrackEnded(String connectionId) {
    final connection = _connections[connectionId];
    if (connection == null) return;

    debugPrint(
      'Track ended unexpectedly for $connectionId. Attempting reconnection...',
    );
    _attemptReconnection(connectionId);
  }

  /// Disposes of the service
  Future<void> dispose() async {
    await stopScreenShare();
    _adaptiveBitrateService.dispose();

    // Clean up timers
    _memoryCleanupTimer?.cancel();
    _connectionHealthTimer?.cancel();

    // Clear state
    _lastActivityTimestamps.clear();
    _connectionQualityScores.clear();

    await _connectionController.close();
    await _errorController.close();
    await _signalController.close();
    _signalingChannel?.sink.close();
  }
}
