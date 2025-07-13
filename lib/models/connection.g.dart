// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connection.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Connection _$ConnectionFromJson(Map<String, dynamic> json) => Connection(
  id: json['id'] as String,
  viewerId: json['viewerId'] as String,
  roomCode: json['roomCode'] as String,
  connectedAt: DateTime.parse(json['connectedAt'] as String),
  status: $enumDecode(_$ConnectionStatusEnumMap, json['status']),
  deviceInfo: json['deviceInfo'] as String?,
  ipAddress: json['ipAddress'] as String?,
  latency: (json['latency'] as num?)?.toInt(),
  bandwidth: (json['bandwidth'] as num?)?.toInt(),
);

Map<String, dynamic> _$ConnectionToJson(Connection instance) =>
    <String, dynamic>{
      'id': instance.id,
      'viewerId': instance.viewerId,
      'roomCode': instance.roomCode,
      'connectedAt': instance.connectedAt.toIso8601String(),
      'status': _$ConnectionStatusEnumMap[instance.status]!,
      'deviceInfo': instance.deviceInfo,
      'ipAddress': instance.ipAddress,
      'latency': instance.latency,
      'bandwidth': instance.bandwidth,
    };

const _$ConnectionStatusEnumMap = {
  ConnectionStatus.connecting: 'connecting',
  ConnectionStatus.connected: 'connected',
  ConnectionStatus.disconnected: 'disconnected',
  ConnectionStatus.error: 'error',
  ConnectionStatus.reconnecting: 'reconnecting',
};

WebRTCSignal _$WebRTCSignalFromJson(Map<String, dynamic> json) => WebRTCSignal(
  type: json['type'] as String,
  roomCode: json['roomCode'] as String,
  senderId: json['senderId'] as String,
  receiverId: json['receiverId'] as String?,
  data: json['data'] as Map<String, dynamic>,
  timestamp: DateTime.parse(json['timestamp'] as String),
);

Map<String, dynamic> _$WebRTCSignalToJson(WebRTCSignal instance) =>
    <String, dynamic>{
      'type': instance.type,
      'roomCode': instance.roomCode,
      'senderId': instance.senderId,
      'receiverId': instance.receiverId,
      'data': instance.data,
      'timestamp': instance.timestamp.toIso8601String(),
    };
