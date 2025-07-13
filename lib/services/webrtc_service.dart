import 'dart:async';

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
          'stun:stun3.l.google.com:19302',
          'stun:stun4.l.google.com:19302',
        ],
      },
    ],
    'bundlePolicy': 'max-bundle',
    'rtcpMuxPolicy': 'require',
    'iceCandidatePoolSize': 50, // Increased for faster connections
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
    ],
  };

  static const Map<String, dynamic> _answerSdpConstraints = {
    'mandatory': {'OfferToReceiveAudio': false, 'OfferToReceiveVideo': true},
    'optional': [
      {'VoiceActivityDetection': false},
      {'DtlsSrtpKeyAgreement': true},
    ],
  };

  // Stream controllers for events
  final StreamController<Connection> _connectionController =
      StreamController<Connection>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  final StreamController<WebRTCSignal> _signalController =
      StreamController<WebRTCSignal>.broadcast();

  // State management
  final Map<String, webrtc.RTCPeerConnection> _peerConnections = {};
  final Map<String, Connection> _connections = {};
  webrtc.MediaStream? _localStream;
  String? _hostId;
  WebSocketChannel? _signalingChannel;
  final AdaptiveBitrateService _adaptiveBitrateService =
      AdaptiveBitrateService();
  QualitySettings? _currentQualitySettings;

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
    } catch (e) {
      _errorController.add('Failed to initialize WebRTC: $e');
      rethrow;
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
          },
          'optional': [
            {'googCpuOveruseDetection': true},
            {'googScreencastMinBitrate': qualitySettings.bitrate ~/ 2},
            {'googHighBitrate': qualitySettings.bitrate},
            {'googVeryHighBitrate': qualitySettings.bitrate * 2},
            {'googPayloadPadding': true},
            {'googScreencastMinBitrate': 300000},
            {'googCpuOveruseDetection': true},
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

      _localStream = await webrtc.navigator.mediaDevices.getDisplayMedia(
        constraints,
      );
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

    try {
      // Mark as reconnecting
      final reconnectingConnection = connection.copyWith(
        status: ConnectionStatus.reconnecting,
      );
      _connections[connectionId] = reconnectingConnection;
      _connectionController.add(reconnectingConnection);

      // Wait a bit before attempting reconnection
      await Future.delayed(const Duration(milliseconds: 1000));

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
      }
    } catch (e) {
      _errorController.add('Reconnection failed for $connectionId: $e');
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

  /// Disposes of the service
  Future<void> dispose() async {
    await stopScreenShare();
    _adaptiveBitrateService.dispose();
    await _connectionController.close();
    await _errorController.close();
    await _signalController.close();
    _signalingChannel?.sink.close();
  }
}
