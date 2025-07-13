import 'package:json_annotation/json_annotation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

part 'connection.g.dart';

@JsonSerializable()
class Connection {
  final String id;
  final String viewerId;
  final String roomCode;
  final DateTime connectedAt;
  final ConnectionStatus status;
  final String? deviceInfo;
  final String? ipAddress;
  final int? latency;
  final int? bandwidth;

  @JsonKey(includeFromJson: false, includeToJson: false)
  final RTCPeerConnection? peerConnection;

  @JsonKey(includeFromJson: false, includeToJson: false)
  final MediaStream? localStream;

  @JsonKey(includeFromJson: false, includeToJson: false)
  final MediaStream? remoteStream;

  Connection({
    required this.id,
    required this.viewerId,
    required this.roomCode,
    required this.connectedAt,
    required this.status,
    this.deviceInfo,
    this.ipAddress,
    this.latency,
    this.bandwidth,
    this.peerConnection,
    this.localStream,
    this.remoteStream,
  });

  factory Connection.fromJson(Map<String, dynamic> json) =>
      _$ConnectionFromJson(json);
  Map<String, dynamic> toJson() => _$ConnectionToJson(this);

  Connection copyWith({
    String? id,
    String? viewerId,
    String? roomCode,
    DateTime? connectedAt,
    ConnectionStatus? status,
    String? deviceInfo,
    String? ipAddress,
    int? latency,
    int? bandwidth,
    RTCPeerConnection? peerConnection,
    MediaStream? localStream,
    MediaStream? remoteStream,
  }) {
    return Connection(
      id: id ?? this.id,
      viewerId: viewerId ?? this.viewerId,
      roomCode: roomCode ?? this.roomCode,
      connectedAt: connectedAt ?? this.connectedAt,
      status: status ?? this.status,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      ipAddress: ipAddress ?? this.ipAddress,
      latency: latency ?? this.latency,
      bandwidth: bandwidth ?? this.bandwidth,
      peerConnection: peerConnection ?? this.peerConnection,
      localStream: localStream ?? this.localStream,
      remoteStream: remoteStream ?? this.remoteStream,
    );
  }

  bool get isConnected => status == ConnectionStatus.connected;
  bool get isDisconnected => status == ConnectionStatus.disconnected;
  bool get isConnecting => status == ConnectionStatus.connecting;
  bool get hasError => status == ConnectionStatus.error;
}

@JsonSerializable()
class WebRTCSignal {
  final String type;
  final String roomCode;
  final String senderId;
  final String? receiverId;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  WebRTCSignal({
    required this.type,
    required this.roomCode,
    required this.senderId,
    this.receiverId,
    required this.data,
    required this.timestamp,
  });

  factory WebRTCSignal.fromJson(Map<String, dynamic> json) =>
      _$WebRTCSignalFromJson(json);
  Map<String, dynamic> toJson() => _$WebRTCSignalToJson(this);

  static WebRTCSignal offer({
    required String roomCode,
    required String senderId,
    String? receiverId,
    required RTCSessionDescription offer,
  }) {
    return WebRTCSignal(
      type: 'offer',
      roomCode: roomCode,
      senderId: senderId,
      receiverId: receiverId,
      data: offer.toMap(),
      timestamp: DateTime.now(),
    );
  }

  static WebRTCSignal answer({
    required String roomCode,
    required String senderId,
    String? receiverId,
    required RTCSessionDescription answer,
  }) {
    return WebRTCSignal(
      type: 'answer',
      roomCode: roomCode,
      senderId: senderId,
      receiverId: receiverId,
      data: answer.toMap(),
      timestamp: DateTime.now(),
    );
  }

  static WebRTCSignal iceCandidate({
    required String roomCode,
    required String senderId,
    String? receiverId,
    required RTCIceCandidate candidate,
  }) {
    return WebRTCSignal(
      type: 'ice-candidate',
      roomCode: roomCode,
      senderId: senderId,
      receiverId: receiverId,
      data: candidate.toMap(),
      timestamp: DateTime.now(),
    );
  }
}

enum ConnectionStatus {
  connecting,
  connected,
  disconnected,
  error,
  reconnecting,
}

enum SignalType { offer, answer, iceCandidate, roomJoin, roomLeave, error }
