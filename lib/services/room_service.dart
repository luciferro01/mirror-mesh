import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/room.dart';
import '../models/connection.dart';
import '../utils/code_generator.dart';

import 'web_server_service.dart';
import 'webrtc_service.dart';

class RoomService {
  final WebServerService _webServerService;
  final WebRTCService _webRTCService;

  Room? _currentRoom;
  final Map<String, Connection> _connections = {};

  // Stream controllers for events
  final StreamController<Room> _roomController =
      StreamController<Room>.broadcast();
  final StreamController<Connection> _connectionController =
      StreamController<Connection>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  // Subscriptions
  late StreamSubscription _webServerRoomSubscription;
  late StreamSubscription _webServerConnectionSubscription;
  late StreamSubscription _webServerSignalSubscription;
  late StreamSubscription _webRTCConnectionSubscription;
  late StreamSubscription _webRTCSignalSubscription;

  RoomService(this._webServerService, this._webRTCService) {
    _setupSubscriptions();
  }

  // Getters for streams
  Stream<Room> get roomStream => _roomController.stream;
  Stream<Connection> get connectionStream => _connectionController.stream;
  Stream<String> get errorStream => _errorController.stream;

  // Getters for state
  Room? get currentRoom => _currentRoom;
  bool get hasActiveRoom => _currentRoom != null && _currentRoom!.isActive;
  Map<String, Connection> get connections => Map.unmodifiable(_connections);
  int get connectionCount => _connections.length;

  /// Sets up subscriptions to underlying services
  void _setupSubscriptions() {
    // Web server subscriptions
    _webServerRoomSubscription = _webServerService.roomStream.listen(
      (room) {
        if (room.code == _currentRoom?.code) {
          _currentRoom = room;
          _roomController.add(room);
        }
      },
      onError: (error) {
        _errorController.add('Web server room error: $error');
      },
    );

    _webServerConnectionSubscription = _webServerService.connectionStream
        .listen(
          (connection) {
            _handleNewConnection(connection);
          },
          onError: (error) {
            _errorController.add('Web server connection error: $error');
          },
        );

    _webServerSignalSubscription = _webServerService.signalStream.listen(
      (signal) {
        _handleSignal(signal);
      },
      onError: (error) {
        _errorController.add('Web server signal error: $error');
      },
    );

    // WebRTC subscriptions
    _webRTCConnectionSubscription = _webRTCService.connectionStream.listen(
      (connection) {
        _connections[connection.id] = connection;
        _connectionController.add(connection);
        _updateRoomViewers();
      },
      onError: (error) {
        _errorController.add('WebRTC connection error: $error');
      },
    );

    _webRTCSignalSubscription = _webRTCService.signalStream.listen(
      (signal) {
        _forwardSignalToViewer(signal);
      },
      onError: (error) {
        _errorController.add('WebRTC signal error: $error');
      },
    );
  }

  /// Creates a new room and starts hosting
  Future<Room> createRoom({
    required ScreenSource screenSource,
    QualitySettings? qualitySettings,
  }) async {
    try {
      if (hasActiveRoom) {
        throw Exception('A room is already active');
      }

      // Start web server if not running
      if (!_webServerService.isRunning) {
        await _webServerService.startServer();
      }

      // Initialize WebRTC service
      await _webRTCService.initialize();

      // Start screen sharing
      await _webRTCService.startScreenShare(
        screenSource,
        qualitySettings ?? QualitySettings.medium,
      );

      // Create room
      final hostId = CodeGenerator.generateId();
      final room = _webServerService.createRoom(
        hostId,
        qualitySettings ?? QualitySettings.medium,
      );

      _currentRoom = room;
      _roomController.add(room);

      return room;
    } catch (e) {
      _errorController.add('Failed to create room: $e');
      rethrow;
    }
  }

  /// Stops the current room and all connections
  Future<void> stopRoom() async {
    try {
      if (_currentRoom == null) return;

      final roomCode = _currentRoom!.code;

      // Stop screen sharing and dispose resources
      await _webRTCService.stopScreenShare();

      // Remove room from web server and clean up
      _webServerService.removeRoom(roomCode);

      // Stop web server completely to clean up all state
      await _webServerService.stopServer();

      // Clear all connections
      _connections.clear();

      // Update room state to inactive
      final updatedRoom = _currentRoom!.copyWith(
        isActive: false,
        connectedViewers: [],
      );
      _currentRoom = null;
      _roomController.add(updatedRoom);

      // Clear any cached state
      await Future.delayed(const Duration(milliseconds: 100));

      debugPrint('Room $roomCode stopped and all data cleaned up');
    } catch (e) {
      _errorController.add('Failed to stop room: $e');
    }
  }

  /// Updates the quality settings for the current room
  Future<void> updateQualitySettings(QualitySettings qualitySettings) async {
    try {
      if (_currentRoom == null) {
        throw Exception('No active room');
      }

      final updatedRoom = _currentRoom!.copyWith(
        qualitySettings: qualitySettings,
      );
      _currentRoom = updatedRoom;
      _roomController.add(updatedRoom);

      // Update web server room
      _webServerService.updateRoom(updatedRoom);
    } catch (e) {
      _errorController.add('Failed to update quality settings: $e');
    }
  }

  /// Changes the screen source being shared
  Future<void> changeScreenSource(ScreenSource screenSource) async {
    try {
      if (_currentRoom == null) {
        throw Exception('No active room');
      }

      // Change screen source without interrupting connections
      await _webRTCService.changeScreenSource(
        screenSource,
        _currentRoom!.qualitySettings,
      );

      // Update room
      final updatedRoom = _currentRoom!.copyWith(
        activeScreenSource: screenSource,
      );
      _currentRoom = updatedRoom;
      _roomController.add(updatedRoom);
    } catch (e) {
      _errorController.add('Failed to change screen source: $e');
    }
  }

  /// Disconnects a specific viewer
  Future<void> disconnectViewer(String viewerId) async {
    try {
      final connection = _connections.values.firstWhere(
        (conn) => conn.viewerId == viewerId,
      );

      await _webRTCService.removePeerConnection(connection.id);
      _connections.remove(connection.id);

      _updateRoomViewers();
    } catch (e) {
      _errorController.add('Failed to disconnect viewer: $e');
    }
  }

  /// Gets the current room URL
  String? getRoomUrl() {
    if (_currentRoom == null) return null;
    return _currentRoom!.connectionUrl;
  }

  /// Gets available screen sources
  Future<List<ScreenSource>> getScreenSources() async {
    return await _webRTCService.getScreenSources();
  }

  /// Handles new connections from the web server
  void _handleNewConnection(Connection connection) async {
    try {
      // Create WebRTC peer connection for the new viewer
      final webrtcConnection = await _webRTCService.createPeerConnection(
        connection.viewerId,
        connection.roomCode,
      );

      // Create and send offer to initiate WebRTC handshake
      final offer = await _webRTCService.createOffer(webrtcConnection.id);

      // Send offer to viewer via WebSocket with optimized timing
      await Future.delayed(
        const Duration(milliseconds: 100),
      ); // Small delay for connection stability

      _webServerService.sendToViewer(connection.viewerId, {
        'type': 'offer',
        'senderId': 'host',
        'receiverId': connection.viewerId,
        'data': {'sdp': offer.sdp, 'type': offer.type},
      });
    } catch (e) {
      _errorController.add('Failed to handle new connection: $e');
    }
  }

  /// Handles WebRTC signaling messages
  void _handleSignal(WebRTCSignal signal) async {
    try {
      switch (signal.type) {
        case 'offer':
          // Handle offer from viewer (shouldn't happen in our setup)
          break;
        case 'answer':
          // Handle answer from viewer
          final description = RTCSessionDescription(
            signal.data['sdp'],
            signal.data['type'],
          );
          final connection = _findConnectionByViewerId(signal.senderId);
          if (connection != null) {
            await _webRTCService.setRemoteDescription(
              connection.id,
              description,
            );
          }
          break;
        case 'ice-candidate':
          // Handle ICE candidate from viewer
          final candidate = RTCIceCandidate(
            signal.data['candidate'],
            signal.data['sdpMid'],
            signal.data['sdpMLineIndex'],
          );
          final connection = _findConnectionByViewerId(signal.senderId);
          if (connection != null) {
            await _webRTCService.addIceCandidate(connection.id, candidate);
          }
          break;
      }
    } catch (e) {
      _errorController.add('Error handling signal: $e');
    }
  }

  /// Forwards WebRTC signals to viewers via WebSocket
  void _forwardSignalToViewer(WebRTCSignal signal) {
    if (_currentRoom == null) return;

    // Broadcast signal to the specific viewer or all viewers
    _webServerService.broadcastToRoom(_currentRoom!.code, signal.toJson());
  }

  /// Finds a connection by viewer ID
  Connection? _findConnectionByViewerId(String viewerId) {
    try {
      return _connections.values.firstWhere(
        (conn) => conn.viewerId == viewerId,
      );
    } catch (e) {
      return null;
    }
  }

  /// Updates room viewer count
  void _updateRoomViewers() {
    if (_currentRoom == null) return;

    final viewerIds = _connections.values.map((conn) => conn.viewerId).toList();
    final updatedRoom = _currentRoom!.copyWith(connectedViewers: viewerIds);
    _currentRoom = updatedRoom;
    _roomController.add(updatedRoom);

    // Update web server room
    _webServerService.updateRoom(updatedRoom);

    // Broadcast viewer count to all connected viewers
    _webServerService.broadcastToRoom(updatedRoom.code, {
      'type': 'viewer-count',
      'count': viewerIds.length,
      'totalConnections': _connections.length,
    });
  }

  /// Gets room statistics
  Map<String, dynamic> getRoomStats() {
    if (_currentRoom == null) return {};

    final connectedCount = _connections.values
        .where((conn) => conn.isConnected)
        .length;
    final connectingCount = _connections.values
        .where((conn) => conn.isConnecting)
        .length;
    final errorCount = _connections.values
        .where((conn) => conn.hasError)
        .length;

    return {
      'roomCode': _currentRoom!.code,
      'totalViewers': _connections.length,
      'connectedViewers': connectedCount,
      'connectingViewers': connectingCount,
      'errorViewers': errorCount,
      'isActive': _currentRoom!.isActive,
      'uptime': DateTime.now().difference(_currentRoom!.createdAt).inSeconds,
      'qualitySettings': _currentRoom!.qualitySettings.toJson(),
    };
  }

  /// Disposes of the service
  Future<void> dispose() async {
    await stopRoom();

    // Cancel subscriptions
    await _webServerRoomSubscription.cancel();
    await _webServerConnectionSubscription.cancel();
    await _webServerSignalSubscription.cancel();
    await _webRTCConnectionSubscription.cancel();
    await _webRTCSignalSubscription.cancel();

    // Close stream controllers
    await _roomController.close();
    await _connectionController.close();
    await _errorController.close();
  }
}
