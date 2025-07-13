import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/connection.dart';
import '../models/room.dart';
import '../utils/network_utils.dart';
import '../utils/code_generator.dart';

class WebServerService {
  HttpServer? _server;
  int? _port;
  String? _ipAddress;

  final Map<String, Room> _rooms = {};
  final Map<String, WebSocketChannel> _webSocketConnections = {};
  final Map<String, String> _viewerToConnectionMap =
      {}; // Maps viewerId to connectionId

  // Stream controllers for events
  final StreamController<Room> _roomController =
      StreamController<Room>.broadcast();
  final StreamController<Connection> _connectionController =
      StreamController<Connection>.broadcast();
  final StreamController<WebRTCSignal> _signalController =
      StreamController<WebRTCSignal>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  // Getters for streams
  Stream<Room> get roomStream => _roomController.stream;
  Stream<Connection> get connectionStream => _connectionController.stream;
  Stream<WebRTCSignal> get signalStream => _signalController.stream;
  Stream<String> get errorStream => _errorController.stream;

  // Getters for state
  Map<String, Room> get rooms => Map.unmodifiable(_rooms);
  bool get isRunning => _server != null;
  int? get port => _port;
  String? get ipAddress => _ipAddress;
  String? get serverUrl =>
      _ipAddress != null && _port != null ? 'http://$_ipAddress:$_port' : null;

  /// Starts the web server
  Future<void> startServer({int? preferredPort}) async {
    try {
      _ipAddress = await NetworkUtils.getLocalIPAddress();
      if (_ipAddress == null) {
        throw Exception('Unable to get local IP address');
      }

      // Find available port
      _port = preferredPort ?? await NetworkUtils.findAvailablePort();
      if (_port == null) {
        throw Exception('No available ports found');
      }

      // Create the request handler
      final handler = Pipeline()
          .addMiddleware(corsHeaders())
          .addMiddleware(logRequests())
          .addHandler(_createHandler());

      // Start the server
      _server = await shelf_io.serve(handler, _ipAddress!, _port!);

      debugPrint(
        'Web server started at ${_server!.address.address}:${_server!.port}',
      );
    } catch (e) {
      _errorController.add('Failed to start web server: $e');
      rethrow;
    }
  }

  /// Stops the web server
  Future<void> stopServer() async {
    try {
      if (_server != null) {
        await _server!.close();
        _server = null;
      }

      // Close all WebSocket connections
      for (final connection in _webSocketConnections.values) {
        await connection.sink.close();
      }
      _webSocketConnections.clear();

      // Clear viewer mappings
      _viewerToConnectionMap.clear();

      // Clear rooms
      _rooms.clear();

      _port = null;
      _ipAddress = null;
    } catch (e) {
      _errorController.add('Failed to stop web server: $e');
    }
  }

  /// Creates the main request handler
  Handler _createHandler() {
    final router = Router();

    // Room routes
    router.get('/room/<roomCode>', _handleRoomRequest);
    router.get('/api/room/<roomCode>/info', _handleRoomInfoRequest);

    // WebSocket route for signaling
    router.get('/ws/<roomCode>', (Request request) {
      final roomCode = request.params['roomCode'] ?? '';
      return webSocketHandler((WebSocketChannel webSocket, String? protocol) {
        try {
          _handleWebSocketConnection(webSocket, roomCode);
        } catch (e) {
          _errorController.add('WebSocket handler error: $e');
        }
      })(request);
    });

    // Health check
    router.get('/health', (Request request) {
      return Response.ok('OK');
    });

    // Default route - redirect to viewer interface
    router.get('/', (Request request) {
      return Response.ok(_getViewerIndexHtml());
    });

    // Catch all route
    router.all('/<ignored|.*>', (Request request) {
      return Response.notFound('Page not found');
    });

    return router.call;
  }

  /// Handles room requests (viewer interface)
  Response _handleRoomRequest(Request request, String roomCode) {
    final room = _rooms[roomCode];
    if (room == null) {
      return Response.notFound(_getRoomNotFoundHtml(roomCode));
    }

    return Response.ok(
      _getViewerHtml(room),
      headers: {'Content-Type': 'text/html'},
    );
  }

  /// Handles room info API requests
  Response _handleRoomInfoRequest(Request request, String roomCode) {
    final room = _rooms[roomCode];
    if (room == null) {
      return Response.notFound(json.encode({'error': 'Room not found'}));
    }

    return Response.ok(
      json.encode({
        'roomCode': room.code,
        'isActive': room.isActive,
        'connectedViewers': room.connectedViewers.length,
        'qualitySettings': room.qualitySettings.toJson(),
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// Handles WebSocket connections for signaling
  void _handleWebSocketConnection(WebSocketChannel webSocket, String roomCode) {
    final room = _rooms[roomCode];
    if (room == null) {
      webSocket.sink.close(4404, 'Room not found');
      return;
    }

    final connectionId = CodeGenerator.generateId();
    _webSocketConnections[connectionId] = webSocket;

    // Handle incoming messages
    webSocket.stream.listen(
      (message) {
        _handleWebSocketMessage(connectionId, roomCode, message);
      },
      onError: (error) {
        _errorController.add('WebSocket error: $error');
        _removeWebSocketConnection(connectionId);
      },
      onDone: () {
        _removeWebSocketConnection(connectionId);
      },
    );

    // Send welcome message
    _sendWebSocketMessage(connectionId, {
      'type': 'welcome',
      'roomCode': roomCode,
      'connectionId': connectionId,
    });
  }

  /// Handles incoming WebSocket messages
  void _handleWebSocketMessage(
    String connectionId,
    String roomCode,
    dynamic message,
  ) {
    try {
      final data = json.decode(message);
      final messageType = data['type'] as String?;

      switch (messageType) {
        case 'join':
          _handleJoinRoom(connectionId, roomCode, data);
          break;
        case 'offer':
          _handleWebRTCOffer(connectionId, roomCode, data);
          break;
        case 'answer':
          _handleWebRTCAnswer(connectionId, roomCode, data);
          break;
        case 'ice-candidate':
          _handleIceCandidate(connectionId, roomCode, data);
          break;
        case 'leave':
          _handleLeaveRoom(connectionId, roomCode);
          break;
        default:
          _errorController.add('Unknown message type: $messageType');
      }
    } catch (e) {
      _errorController.add('Error handling WebSocket message: $e');
    }
  }

  /// Handles join room requests
  void _handleJoinRoom(
    String connectionId,
    String roomCode,
    Map<String, dynamic> data,
  ) {
    final room = _rooms[roomCode];
    if (room == null) return;

    final viewerId = data['viewerId'] as String? ?? CodeGenerator.generateId();
    final deviceInfo = data['deviceInfo'] as String?;

    // Map viewer to connection for targeted messaging
    _viewerToConnectionMap[viewerId] = connectionId;

    // Create connection
    final connection = Connection(
      id: connectionId,
      viewerId: viewerId,
      roomCode: roomCode,
      connectedAt: DateTime.now(),
      status: ConnectionStatus.connecting,
      deviceInfo: deviceInfo,
    );

    // Update room
    final updatedRoom = room.copyWith(
      connectedViewers: [...room.connectedViewers, viewerId],
    );
    _rooms[roomCode] = updatedRoom;

    // Notify listeners
    _connectionController.add(connection);
    _roomController.add(updatedRoom);

    // Send join confirmation
    _sendWebSocketMessage(connectionId, {
      'type': 'joined',
      'viewerId': viewerId,
      'roomCode': roomCode,
    });
  }

  /// Handles WebRTC offer messages
  void _handleWebRTCOffer(
    String connectionId,
    String roomCode,
    Map<String, dynamic> data,
  ) {
    final signal = WebRTCSignal.fromJson({
      'type': 'offer',
      'roomCode': roomCode,
      'senderId': data['senderId'],
      'receiverId': data['receiverId'],
      'data': data['data'],
      'timestamp': DateTime.now().toIso8601String(),
    });

    _signalController.add(signal);
  }

  /// Handles WebRTC answer messages
  void _handleWebRTCAnswer(
    String connectionId,
    String roomCode,
    Map<String, dynamic> data,
  ) {
    final signal = WebRTCSignal.fromJson({
      'type': 'answer',
      'roomCode': roomCode,
      'senderId': data['senderId'],
      'receiverId': data['receiverId'],
      'data': data['data'],
      'timestamp': DateTime.now().toIso8601String(),
    });

    _signalController.add(signal);
  }

  /// Handles ICE candidate messages
  void _handleIceCandidate(
    String connectionId,
    String roomCode,
    Map<String, dynamic> data,
  ) {
    final signal = WebRTCSignal.fromJson({
      'type': 'ice-candidate',
      'roomCode': roomCode,
      'senderId': data['senderId'],
      'receiverId': data['receiverId'],
      'data': data['data'],
      'timestamp': DateTime.now().toIso8601String(),
    });

    _signalController.add(signal);
  }

  /// Handles leave room requests
  void _handleLeaveRoom(String connectionId, String roomCode) {
    final room = _rooms[roomCode];
    if (room == null) return;

    // Find the viewer ID for this connection
    String? viewerIdToRemove;
    for (final entry in _viewerToConnectionMap.entries) {
      if (entry.value == connectionId) {
        viewerIdToRemove = entry.key;
        break;
      }
    }

    // Remove connection
    _removeWebSocketConnection(connectionId);

    // Remove viewer mapping
    if (viewerIdToRemove != null) {
      _viewerToConnectionMap.remove(viewerIdToRemove);

      // Update room (remove viewer)
      final updatedRoom = room.copyWith(
        connectedViewers: room.connectedViewers
            .where((id) => id != viewerIdToRemove)
            .toList(),
      );
      _rooms[roomCode] = updatedRoom;
      _roomController.add(updatedRoom);
    }
  }

  /// Sends a message to a specific WebSocket connection
  void _sendWebSocketMessage(
    String connectionId,
    Map<String, dynamic> message,
  ) {
    final connection = _webSocketConnections[connectionId];
    if (connection != null) {
      connection.sink.add(json.encode(message));
    }
  }

  /// Broadcasts a message to all connections in a room
  void broadcastToRoom(String roomCode, Map<String, dynamic> message) {
    // Send to all connections in the room
    final List<String> connectionsToRemove = [];

    for (final entry in _webSocketConnections.entries) {
      try {
        entry.value.sink.add(json.encode(message));
      } catch (e) {
        // Connection is closed, mark for removal
        connectionsToRemove.add(entry.key);
      }
    }

    // Remove dead connections
    for (final connectionId in connectionsToRemove) {
      _webSocketConnections.remove(connectionId);
    }
  }

  /// Sends a message to a specific viewer
  void sendToViewer(String viewerId, Map<String, dynamic> message) {
    final connectionId = _viewerToConnectionMap[viewerId];
    if (connectionId != null) {
      final connection = _webSocketConnections[connectionId];
      if (connection != null) {
        try {
          connection.sink.add(json.encode(message));
        } catch (e) {
          // Connection is closed, remove it
          _removeWebSocketConnection(connectionId);
          _viewerToConnectionMap.remove(viewerId);
        }
      }
    }
  }

  /// Removes a WebSocket connection
  void _removeWebSocketConnection(String connectionId) {
    final connection = _webSocketConnections.remove(connectionId);
    connection?.sink.close();

    // Also remove viewer mapping
    String? viewerIdToRemove;
    for (final entry in _viewerToConnectionMap.entries) {
      if (entry.value == connectionId) {
        viewerIdToRemove = entry.key;
        break;
      }
    }

    if (viewerIdToRemove != null) {
      _viewerToConnectionMap.remove(viewerIdToRemove);
    }
  }

  /// Creates a new room
  Room createRoom(String hostId, QualitySettings qualitySettings) {
    final room = Room(
      id: CodeGenerator.generateId(),
      code: CodeGenerator.generateRoomCode(),
      hostId: hostId,
      createdAt: DateTime.now(),
      qualitySettings: qualitySettings,
      hostIP: _ipAddress,
      serverPort: _port,
      isActive: true,
    );

    _rooms[room.code] = room;
    _roomController.add(room);

    return room;
  }

  /// Updates an existing room
  void updateRoom(Room room) {
    _rooms[room.code] = room;
    _roomController.add(room);
  }

  /// Removes a room
  void removeRoom(String roomCode) {
    final room = _rooms.remove(roomCode);
    if (room != null) {
      // Close all connections for this room
      // This is simplified - in a real implementation, you'd track connections per room
      final updatedRoom = room.copyWith(isActive: false);
      _roomController.add(updatedRoom);
    }
  }

  /// Gets the viewer HTML page
  String _getViewerHtml(Room room) {
    return '''
<!DOCTYPE html>
<html>
<head>
    <title>Mirror Mesh - Room ${room.code}</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif;
            background: linear-gradient(135deg, #1a1a1a 0%, #2d2d2d 100%);
            color: white;
            overflow-x: hidden;
            min-height: 100vh;
            position: relative;
        }
        
        .container { 
            max-width: 100%;
            margin: 0 auto;
            padding: 16px;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
        }
        
        .header { 
            text-align: center;
            margin-bottom: 24px;
            padding: 20px 0;
        }
        
        .logo {
            font-size: 28px;
            font-weight: bold;
            color: #00ff88;
            margin-bottom: 8px;
        }
        
        .room-code { 
            font-size: 20px;
            font-weight: bold;
            color: #00ff88;
            background: rgba(0, 255, 136, 0.1);
            padding: 12px 20px;
            border-radius: 12px;
            border: 2px solid rgba(0, 255, 136, 0.3);
            letter-spacing: 2px;
            margin: 16px 0;
        }
        
        .video-container { 
            position: relative;
            width: 100%;
            flex: 1;
            display: flex;
            align-items: center;
            justify-content: center;
            background: #000;
            border-radius: 12px;
            overflow: hidden;
            margin-bottom: 20px;
            min-height: 300px;
        }
        
        #remoteVideo { 
            width: 100%;
            height: 100%;
            object-fit: contain;
            background: #000;
        }
        
        .video-overlay {
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: linear-gradient(45deg, #1a1a1a 25%, transparent 25%), 
                        linear-gradient(-45deg, #1a1a1a 25%, transparent 25%), 
                        linear-gradient(45deg, transparent 75%, #1a1a1a 75%), 
                        linear-gradient(-45deg, transparent 75%, #1a1a1a 75%);
            background-size: 20px 20px;
            background-position: 0 0, 0 10px, 10px -10px, -10px 0px;
            display: flex;
            align-items: center;
            justify-content: center;
            flex-direction: column;
        }
        
        .waiting-message {
            font-size: 18px;
            color: #00ff88;
            margin-bottom: 12px;
            text-align: center;
        }
        
        .waiting-subtitle {
            font-size: 14px;
            color: rgba(255, 255, 255, 0.7);
            text-align: center;
        }
        
        .controls { 
            display: flex;
            gap: 12px;
            margin-bottom: 20px;
            flex-wrap: wrap;
        }
        
        .status { 
            padding: 16px;
            border-radius: 12px;
            text-align: center;
            font-size: 14px;
            font-weight: 500;
            margin-bottom: 20px;
            transition: all 0.3s ease;
        }
        
        .status.connecting { 
            background: linear-gradient(135deg, #ff6b00 0%, #ff8f00 100%);
            box-shadow: 0 4px 15px rgba(255, 107, 0, 0.3);
        }
        
        .status.connected { 
            background: linear-gradient(135deg, #00ff88 0%, #00cc6a 100%);
            color: #000;
            box-shadow: 0 4px 15px rgba(0, 255, 136, 0.3);
        }
        
        .status.error { 
            background: linear-gradient(135deg, #ff4444 0%, #cc1111 100%);
            box-shadow: 0 4px 15px rgba(255, 68, 68, 0.3);
        }
        
        .btn { 
            padding: 14px 24px;
            border: none;
            border-radius: 12px;
            cursor: pointer;
            font-size: 16px;
            font-weight: 600;
            transition: all 0.3s ease;
            flex: 1;
            min-width: 120px;
            position: relative;
            overflow: hidden;
        }
        
        .btn:before {
            content: '';
            position: absolute;
            top: 0;
            left: -100%;
            width: 100%;
            height: 100%;
            background: linear-gradient(90deg, transparent, rgba(255, 255, 255, 0.2), transparent);
            transition: left 0.5s;
        }
        
        .btn:hover:before {
            left: 100%;
        }
        
        .btn-primary { 
            background: linear-gradient(135deg, #00ff88 0%, #00cc6a 100%);
            color: #000;
            box-shadow: 0 4px 15px rgba(0, 255, 136, 0.3);
        }
        
        .btn-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(0, 255, 136, 0.4);
        }
        
        .btn-secondary { 
            background: linear-gradient(135deg, #6c757d 0%, #495057 100%);
            color: white;
            box-shadow: 0 4px 15px rgba(108, 117, 125, 0.3);
        }
        
        .btn-secondary:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(108, 117, 125, 0.4);
        }
        
        .btn:disabled {
            opacity: 0.6;
            cursor: not-allowed;
            transform: none !important;
        }
        
        .loading-spinner {
            width: 20px;
            height: 20px;
            border: 2px solid rgba(0, 0, 0, 0.3);
            border-radius: 50%;
            border-top-color: #000;
            animation: spin 1s ease-in-out infinite;
            margin-right: 8px;
        }
        
        .info-panel {
            background: rgba(42, 42, 42, 0.8);
            border-radius: 12px;
            padding: 16px;
            margin-bottom: 16px;
            border: 1px solid rgba(0, 255, 136, 0.2);
        }
        
        .info-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 8px 0;
            border-bottom: 1px solid rgba(255, 255, 255, 0.1);
        }
        
        .info-row:last-child {
            border-bottom: none;
        }
        
        .info-label {
            font-size: 12px;
            color: rgba(255, 255, 255, 0.7);
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        .info-value {
            font-size: 14px;
            color: #00ff88;
            font-weight: 500;
        }
        
        .connection-indicator {
            display: inline-block;
            width: 8px;
            height: 8px;
            border-radius: 50%;
            background: #00ff88;
            margin-right: 8px;
            animation: pulse 2s infinite;
        }
        
        .fullscreen-btn {
            position: absolute;
            top: 16px;
            right: 16px;
            background: rgba(0, 0, 0, 0.7);
            border: none;
            color: white;
            padding: 12px;
            border-radius: 50%;
            cursor: pointer;
            font-size: 18px;
            transition: all 0.3s ease;
            z-index: 10;
        }
        
        .fullscreen-btn:hover {
            background: rgba(0, 255, 136, 0.8);
            color: #000;
        }
        
        @keyframes spin {
            to { transform: rotate(360deg); }
        }
        
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        
        @media (max-width: 768px) {
            .container {
                padding: 12px;
            }
            
            .logo {
                font-size: 24px;
            }
            
            .room-code {
                font-size: 18px;
                padding: 10px 16px;
            }
            
            .btn {
                padding: 12px 20px;
                font-size: 14px;
            }
            
            .controls {
                flex-direction: column;
            }
            
            .video-container {
                min-height: 250px;
            }
        }
        
        @media (orientation: landscape) and (max-width: 768px) {
            .header {
                margin-bottom: 16px;
                padding: 12px 0;
            }
            
            .room-code {
                font-size: 16px;
                margin: 8px 0;
            }
            
            .video-container {
                min-height: 200px;
            }
        }
        
        /* Full screen styles */
        .video-container.fullscreen {
            position: fixed;
            top: 0;
            left: 0;
            width: 100vw;
            height: 100vh;
            z-index: 1000;
            border-radius: 0;
            margin: 0;
        }
        
        /* Dark theme adjustments for better contrast */
        .dark-overlay {
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.9);
            z-index: -1;
        }
    </style>
</head>
<body>
    <div class="dark-overlay"></div>
    <div class="container">
        <div class="header">
            <div class="logo">📱 Mirror Mesh</div>
            <div class="room-code">${room.code}</div>
        </div>
        
        <div class="info-panel">
            <div class="info-row">
                <span class="info-label">Status</span>
                <span class="info-value" id="connectionStatus">
                    <span class="connection-indicator"></span>Ready to connect
                </span>
            </div>
            <div class="info-row">
                <span class="info-label">Quality</span>
                <span class="info-value">${room.qualitySettings.width}×${room.qualitySettings.height} • ${room.qualitySettings.frameRate}fps</span>
            </div>
            <div class="info-row" id="viewerCountRow" style="display: none;">
                <span class="info-label">Viewers</span>
                <span class="info-value" id="viewerCount">0</span>
            </div>
        </div>
        
        <div class="video-container" id="videoContainer">
            <video id="remoteVideo" autoplay playsinline muted></video>
            <div class="video-overlay" id="videoOverlay">
                <div class="waiting-message">📺 Waiting for screen share...</div>
                <div class="waiting-subtitle">The host will start sharing shortly</div>
            </div>
            <button class="fullscreen-btn" id="fullscreenBtn" onclick="toggleFullscreen()" style="display: none;">
                ⛶
            </button>
        </div>
        
        <div class="controls">
            <button id="connectBtn" class="btn btn-primary">
                <span id="connectText">🔗 Connect</span>
            </button>
            <button id="disconnectBtn" class="btn btn-secondary" disabled>
                ❌ Disconnect
            </button>
        </div>
        
        <div id="status" class="status">Ready to connect to room ${room.code}</div>
    </div>

    <script>
        // Enhanced WebRTC viewer implementation
        const roomCode = '${room.code}';
        const wsUrl = 'ws://${room.hostIP}:${room.serverPort}/ws/' + roomCode;
        
        let ws = null;
        let peerConnection = null;
        let isConnected = false;
        let connectionTimeout = null;
        let viewerId = null; // Store viewer ID consistently
        
        // WebRTC configuration
        const rtcConfig = {
            iceServers: [
                { urls: 'stun:stun.l.google.com:19302' },
                { urls: 'stun:stun1.l.google.com:19302' }
            ]
        };
        
        // UI elements
        const connectBtn = document.getElementById('connectBtn');
        const disconnectBtn = document.getElementById('disconnectBtn');
        const statusEl = document.getElementById('status');
        const remoteVideo = document.getElementById('remoteVideo');
        const videoOverlay = document.getElementById('videoOverlay');
        const fullscreenBtn = document.getElementById('fullscreenBtn');
        const connectionStatus = document.getElementById('connectionStatus');
        const connectText = document.getElementById('connectText');
        
        // Event listeners
        connectBtn.onclick = connect;
        disconnectBtn.onclick = disconnect;
        
        // Auto-connect on load
        window.addEventListener('load', () => {
            // Small delay to ensure UI is ready
            setTimeout(connect, 500);
        });
        
        // Handle page visibility changes
        document.addEventListener('visibilitychange', () => {
            if (document.hidden && isConnected) {
                updateStatus('Connection paused (tab hidden)', 'connecting');
            } else if (!document.hidden && isConnected) {
                updateStatus('Connected and streaming', 'connected');
            }
        });
        
        function connect() {
            if (isConnected) return;
            
            updateStatus('Connecting to room...', 'connecting');
            connectBtn.disabled = true;
            connectText.innerHTML = '<div class="loading-spinner"></div>Connecting...';
            
            // Connection timeout
            connectionTimeout = setTimeout(() => {
                if (!isConnected) {
                    updateStatus('Connection timeout - Please check network', 'error');
                    resetConnection();
                }
            }, 10000);
            
            try {
                ws = new WebSocket(wsUrl);
                setupWebSocket();
            } catch (error) {
                updateStatus('Failed to connect: ' + error.message, 'error');
                resetConnection();
            }
        }
        
        function setupWebSocket() {
            ws.onopen = function() {
                updateStatus('Connected to room - Setting up video...', 'connecting');
                clearTimeout(connectionTimeout);
                
                // Generate viewerId once and reuse it
                viewerId = generateViewerId();
                
                // Send join message
                const joinMessage = {
                    type: 'join',
                    viewerId: viewerId,
                    deviceInfo: getDeviceInfo()
                };
                ws.send(JSON.stringify(joinMessage));
                
                // Initialize WebRTC
                initializePeerConnection();
            };
            
            ws.onmessage = function(event) {
                try {
                    const data = JSON.parse(event.data);
                    handleSignalingMessage(data);
                } catch (error) {
                    console.error('Error parsing message:', error);
                }
            };
            
            ws.onclose = function(event) {
                if (event.code === 4404) {
                    updateStatus('Room not found or expired', 'error');
                } else if (isConnected) {
                    updateStatus('Connection lost - Attempting to reconnect...', 'connecting');
                    setTimeout(() => {
                        if (!isConnected) connect();
                    }, 3000);
                } else {
                    updateStatus('Disconnected from room', 'error');
                }
                resetConnection();
            };
            
            ws.onerror = function(error) {
                updateStatus('Connection error - Check network and try again', 'error');
                console.error('WebSocket error:', error);
                resetConnection();
            };
        }
        
        function initializePeerConnection() {
            peerConnection = new RTCPeerConnection(rtcConfig);
            
            peerConnection.onicecandidate = function(event) {
                if (event.candidate && ws.readyState === WebSocket.OPEN) {
                    ws.send(JSON.stringify({
                        type: 'ice-candidate',
                        senderId: viewerId,
                        data: event.candidate
                    }));
                }
            };
            
            peerConnection.ontrack = function(event) {
                const [stream] = event.streams;
                remoteVideo.srcObject = stream;
                
                remoteVideo.onloadedmetadata = function() {
                    updateStatus('🎥 Screen sharing active', 'connected');
                    videoOverlay.style.display = 'none';
                    fullscreenBtn.style.display = 'block';
                    isConnected = true;
                    connectBtn.disabled = true;
                    disconnectBtn.disabled = false;
                    connectText.innerHTML = '🔗 Connected';
                };
            };
            
            peerConnection.onconnectionstatechange = function() {
                const state = peerConnection.connectionState;
                console.log('Connection state:', state);
                
                switch (state) {
                    case 'connected':
                        updateConnectionStatus('🟢 Connected', 'connected');
                        break;
                    case 'connecting':
                        updateConnectionStatus('🟡 Connecting...', 'connecting');
                        break;
                    case 'disconnected':
                        updateConnectionStatus('🔴 Disconnected', 'error');
                        break;
                    case 'failed':
                        updateStatus('Connection failed - Please try again', 'error');
                        resetConnection();
                        break;
                }
            };
        }
        
        function handleSignalingMessage(message) {
            console.log('Received signaling message:', message.type, message);
            
            switch (message.type) {
                case 'welcome':
                    console.log('Welcomed to room:', message.roomCode);
                    break;
                    
                case 'joined':
                    console.log('Successfully joined room as viewer:', viewerId);
                    updateStatus('Joined room - Waiting for host to share screen...', 'connecting');
                    break;
                    
                case 'offer':
                    console.log('Received offer from host, processing...');
                    handleOffer(message.data);
                    break;
                    
                case 'ice-candidate':
                    console.log('Received ICE candidate from host');
                    handleIceCandidate(message.data);
                    break;
                    
                case 'viewer-count':
                    updateViewerCount(message.count);
                    break;
                    
                default:
                    console.log('Unknown message type:', message.type);
            }
        }
        
        async function handleOffer(offer) {
            try {
                console.log('Setting remote description with offer...');
                await peerConnection.setRemoteDescription(offer);
                
                console.log('Creating answer...');
                const answer = await peerConnection.createAnswer();
                await peerConnection.setLocalDescription(answer);
                
                if (ws.readyState === WebSocket.OPEN) {
                    console.log('Sending answer to host...');
                    ws.send(JSON.stringify({
                        type: 'answer',
                        senderId: viewerId,
                        data: answer
                    }));
                    updateStatus('Sent answer to host - Establishing connection...', 'connecting');
                } else {
                    console.error('WebSocket not open when trying to send answer');
                }
            } catch (error) {
                console.error('Error handling offer:', error);
                updateStatus('Failed to establish video connection', 'error');
            }
        }
        
        async function handleIceCandidate(candidate) {
            try {
                await peerConnection.addIceCandidate(candidate);
            } catch (error) {
                console.error('Error adding ICE candidate:', error);
            }
        }
        
        function disconnect() {
            if (ws) {
                ws.close();
            }
            if (peerConnection) {
                peerConnection.close();
            }
            resetConnection();
            updateStatus('Disconnected from room', 'error');
        }
        
        function resetConnection() {
            isConnected = false;
            connectBtn.disabled = false;
            disconnectBtn.disabled = true;
            connectText.innerHTML = '🔗 Connect';
            videoOverlay.style.display = 'flex';
            fullscreenBtn.style.display = 'none';
            updateConnectionStatus('⚪ Not connected', 'error');
            
            if (remoteVideo.srcObject) {
                remoteVideo.srcObject = null;
            }
            
            clearTimeout(connectionTimeout);
        }
        
        function updateStatus(message, type) {
            statusEl.textContent = message;
            statusEl.className = 'status ' + type;
        }
        
        function updateConnectionStatus(message, type) {
            connectionStatus.innerHTML = '<span class="connection-indicator"></span>' + message;
        }
        
        function updateViewerCount(count) {
            const viewerCountRow = document.getElementById('viewerCountRow');
            const viewerCount = document.getElementById('viewerCount');
            
            if (count > 0) {
                viewerCountRow.style.display = 'flex';
                viewerCount.textContent = count;
            } else {
                viewerCountRow.style.display = 'none';
            }
        }
        
        function toggleFullscreen() {
            const videoContainer = document.getElementById('videoContainer');
            
            if (!document.fullscreenElement) {
                videoContainer.requestFullscreen().catch(err => {
                    console.log('Error attempting to enable fullscreen:', err);
                });
            } else {
                document.exitFullscreen();
            }
        }
        
        function generateViewerId() {
            return 'viewer_' + Math.random().toString(36).substring(2, 15) + '_' + Date.now();
        }
        
        function getDeviceInfo() {
            const ua = navigator.userAgent;
            let device = 'Unknown Device';
            
            if (/Android/i.test(ua)) {
                device = 'Android Device';
            } else if (/iPhone|iPad|iPod/i.test(ua)) {
                device = 'iOS Device';
            } else if (/Windows/i.test(ua)) {
                device = 'Windows Device';
            } else if (/Mac/i.test(ua)) {
                device = 'Mac Device';
            } else if (/Linux/i.test(ua)) {
                device = 'Linux Device';
            }
            
            return device + ' (' + (navigator.platform || 'Unknown Platform') + ')';
        }
        
        // Handle orientation changes on mobile
        window.addEventListener('orientationchange', () => {
            setTimeout(() => {
                if (remoteVideo.srcObject) {
                    remoteVideo.play();
                }
            }, 500);
        });
        
        // Prevent context menu on long press (mobile)
        document.addEventListener('contextmenu', (e) => {
            if (e.target === remoteVideo) {
                e.preventDefault();
            }
        });
        
        // Wake lock for mobile devices (prevent screen sleep)
        let wakeLock = null;
        
        async function requestWakeLock() {
            try {
                if ('wakeLock' in navigator) {
                    wakeLock = await navigator.wakeLock.request('screen');
                    console.log('Wake lock acquired');
                }
            } catch (err) {
                console.log('Wake lock failed:', err);
            }
        }
        
        // Request wake lock when video starts
        remoteVideo.addEventListener('play', requestWakeLock);
        
        // Release wake lock when disconnecting
        function releaseWakeLock() {
            if (wakeLock) {
                wakeLock.release();
                wakeLock = null;
                console.log('Wake lock released');
            }
        }
        
        window.addEventListener('beforeunload', releaseWakeLock);
    </script>
</body>
</html>
    ''';
  }

  /// Gets the viewer index HTML page
  String _getViewerIndexHtml() {
    return '''
<!DOCTYPE html>
<html>
<head>
    <title>Mirror Mesh - Join Room</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { margin: 0; padding: 20px; font-family: Arial, sans-serif; background: #1a1a1a; color: white; text-align: center; }
        .container { max-width: 400px; margin: 50px auto; }
        .form-group { margin: 20px 0; }
        .form-control { width: 100%; padding: 12px; border: 1px solid #444; border-radius: 4px; background: #2a2a2a; color: white; font-size: 16px; }
        .btn { padding: 12px 24px; border: none; border-radius: 4px; cursor: pointer; font-size: 16px; }
        .btn-primary { background: #007bff; color: white; }
        .btn-primary:hover { background: #0056b3; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Mirror Mesh</h1>
        <p>Enter a room code to join a screen sharing session</p>
        
        <div class="form-group">
            <input type="text" id="roomCode" class="form-control" placeholder="Enter room code" maxlength="6">
        </div>
        
        <button id="joinBtn" class="btn btn-primary">Join Room</button>
    </div>

    <script>
        document.getElementById('joinBtn').onclick = function() {
            const roomCode = document.getElementById('roomCode').value.trim().toUpperCase();
            if (roomCode.length === 6) {
                window.location.href = '/room/' + roomCode;
            } else {
                alert('Please enter a valid 6-character room code');
            }
        };
        
        document.getElementById('roomCode').addEventListener('keypress', function(e) {
            if (e.key === 'Enter') {
                document.getElementById('joinBtn').click();
            }
        });
    </script>
</body>
</html>
    ''';
  }

  /// Gets the room not found HTML page
  String _getRoomNotFoundHtml(String roomCode) {
    return '''
<!DOCTYPE html>
<html>
<head>
    <title>Mirror Mesh - Room Not Found</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { margin: 0; padding: 20px; font-family: Arial, sans-serif; background: #1a1a1a; color: white; text-align: center; }
        .container { max-width: 400px; margin: 50px auto; }
        .error { color: #ff4444; }
        .btn { padding: 12px 24px; border: none; border-radius: 4px; cursor: pointer; font-size: 16px; }
        .btn-primary { background: #007bff; color: white; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Mirror Mesh</h1>
        <p class="error">Room "$roomCode" not found</p>
        <p>The room may have expired or the code is incorrect.</p>
        <button class="btn btn-primary" onclick="window.location.href='/'">Try Again</button>
    </div>
</body>
</html>
    ''';
  }

  /// Disposes of the service
  Future<void> dispose() async {
    await stopServer();
    await _roomController.close();
    await _connectionController.close();
    await _signalController.close();
    await _errorController.close();
  }
}
