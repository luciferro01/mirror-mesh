import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/room.dart';
import '../models/connection.dart';
import '../services/web_server_service.dart';
import '../services/webrtc_service.dart';
import '../services/room_service.dart';
import '../utils/network_utils.dart';

// Service providers
final webServerServiceProvider = Provider<WebServerService>((ref) {
  return WebServerService();
});

final webRTCServiceProvider = Provider<WebRTCService>((ref) {
  return WebRTCService();
});

final roomServiceProvider = Provider<RoomService>((ref) {
  final webServerService = ref.watch(webServerServiceProvider);
  final webRTCService = ref.watch(webRTCServiceProvider);
  return RoomService(webServerService, webRTCService);
});

// State providers
final currentRoomProvider = StreamProvider<Room?>((ref) {
  final roomService = ref.watch(roomServiceProvider);

  // Create a stream that starts with null (no room) and then listens to roomStream
  final controller = StreamController<Room?>();

  // Emit initial value
  controller.add(roomService.currentRoom);

  // Listen to room changes
  final subscription = roomService.roomStream.listen(
    (room) => controller.add(room),
    onError: (error) => controller.addError(error),
  );

  // Clean up when provider is disposed
  ref.onDispose(() {
    subscription.cancel();
    controller.close();
  });

  return controller.stream;
});

final connectionsProvider = StreamProvider<List<Connection>>((ref) {
  final roomService = ref.watch(roomServiceProvider);

  // Create a stream that starts with current connections and then listens to changes
  final controller = StreamController<List<Connection>>();

  // Emit initial value
  controller.add(roomService.connections.values.toList());

  // Listen to connection changes
  final subscription = roomService.connectionStream.listen(
    (connection) => controller.add(roomService.connections.values.toList()),
    onError: (error) => controller.addError(error),
  );

  // Clean up when provider is disposed
  ref.onDispose(() {
    subscription.cancel();
    controller.close();
  });

  return controller.stream;
});

final roomStatsProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final roomService = ref.watch(roomServiceProvider);

  // Create a stream that updates every second for real-time stats
  final controller = StreamController<Map<String, dynamic>>();

  Timer? timer;

  void updateStats() {
    final stats = roomService.getRoomStats();
    if (!controller.isClosed) {
      controller.add(stats);
    }
  }

  // Initial stats
  updateStats();

  // Update every second for real-time uptime
  timer = Timer.periodic(const Duration(seconds: 1), (timer) {
    updateStats();
  });

  // Clean up when provider is disposed
  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });

  return controller.stream;
});

final screenSourcesProvider = FutureProvider<List<ScreenSource>>((ref) {
  final roomService = ref.watch(roomServiceProvider);
  return roomService.getScreenSources();
});

final selectedScreenSourceProvider = StateProvider<ScreenSource?>((ref) {
  final appState = ref.watch(appStateProvider);
  return appState.selectedScreenSource;
});

final selectedQualityProvider = StateProvider<QualitySettings>((ref) {
  return QualitySettings.medium;
});

// Network and server state
final networkInfoProvider = StreamProvider<DeviceNetworkInfo>((ref) {
  // Create a stream that updates network info every 3 seconds
  final controller = StreamController<DeviceNetworkInfo>();

  Timer? timer;

  Future<void> updateNetworkInfo() async {
    try {
      final networkInfo = await NetworkUtils.getNetworkInfo();
      if (!controller.isClosed) {
        controller.add(networkInfo);
      }
    } catch (e) {
      if (!controller.isClosed) {
        controller.addError(e);
      }
    }
  }

  // Initial network info
  updateNetworkInfo();

  // Update every 3 seconds for more responsive network status
  timer = Timer.periodic(const Duration(seconds: 3), (timer) {
    updateNetworkInfo();
  });

  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });

  return controller.stream;
});

final serverStatusProvider = Provider<ServerStatus>((ref) {
  final webServerService = ref.watch(webServerServiceProvider);
  return ServerStatus(
    isRunning: webServerService.isRunning,
    port: webServerService.port,
    ipAddress: webServerService.ipAddress,
    serverUrl: webServerService.serverUrl,
  );
});

// Error handling
final errorProvider = StreamProvider<String?>((ref) {
  final roomService = ref.watch(roomServiceProvider);

  // Create a stream that starts with no error and then listens to error changes
  final controller = StreamController<String?>();

  // Emit initial value (no error)
  controller.add(null);

  // Listen to error changes
  final subscription = roomService.errorStream.listen(
    (error) => controller.add(error),
    onError: (error) => controller.addError(error),
  );

  // Clean up when provider is disposed
  ref.onDispose(() {
    subscription.cancel();
    controller.close();
  });

  return controller.stream;
});

// Room management actions
final roomActionsProvider = Provider<RoomActions>((ref) {
  final roomService = ref.watch(roomServiceProvider);
  return RoomActions(roomService);
});

// Data classes
class ServerStatus {
  final bool isRunning;
  final int? port;
  final String? ipAddress;
  final String? serverUrl;

  ServerStatus({
    required this.isRunning,
    this.port,
    this.ipAddress,
    this.serverUrl,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ServerStatus &&
        other.isRunning == isRunning &&
        other.port == port &&
        other.ipAddress == ipAddress &&
        other.serverUrl == serverUrl;
  }

  @override
  int get hashCode {
    return isRunning.hashCode ^
        port.hashCode ^
        ipAddress.hashCode ^
        serverUrl.hashCode;
  }
}

class RoomActions {
  final RoomService _roomService;

  RoomActions(this._roomService);

  Future<Room> createRoom({
    required ScreenSource screenSource,
    QualitySettings? qualitySettings,
  }) async {
    return await _roomService.createRoom(
      screenSource: screenSource,
      qualitySettings: qualitySettings,
    );
  }

  Future<void> stopRoom() async {
    await _roomService.stopRoom();
  }

  Future<void> updateQualitySettings(QualitySettings qualitySettings) async {
    await _roomService.updateQualitySettings(qualitySettings);
  }

  Future<void> changeScreenSource(ScreenSource screenSource) async {
    await _roomService.changeScreenSource(screenSource);
  }

  Future<void> disconnectViewer(String viewerId) async {
    await _roomService.disconnectViewer(viewerId);
  }

  String? getRoomUrl() {
    return _roomService.getRoomUrl();
  }

  Future<List<ScreenSource>> getScreenSources() async {
    return await _roomService.getScreenSources();
  }

  Map<String, dynamic> getRoomStats() {
    return _roomService.getRoomStats();
  }
}

// App state provider
final appStateProvider = StateNotifierProvider<AppStateNotifier, AppState>((
  ref,
) {
  return AppStateNotifier();
});

class AppStateNotifier extends StateNotifier<AppState> {
  AppStateNotifier() : super(AppState.initial());

  void setScreenSource(ScreenSource screenSource) {
    state = state.copyWith(selectedScreenSource: screenSource);
  }

  void setQualitySettings(QualitySettings qualitySettings) {
    state = state.copyWith(selectedQualitySettings: qualitySettings);
  }

  void setRoomCreating(bool isCreating) {
    state = state.copyWith(isCreatingRoom: isCreating);
  }

  void setError(String? error) {
    state = state.copyWith(error: error);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  void reset() {
    state = AppState.initial();
  }
}

class AppState {
  final ScreenSource? selectedScreenSource;
  final QualitySettings selectedQualitySettings;
  final bool isCreatingRoom;
  final String? error;

  AppState({
    this.selectedScreenSource,
    required this.selectedQualitySettings,
    this.isCreatingRoom = false,
    this.error,
  });

  factory AppState.initial() {
    return AppState(
      selectedQualitySettings: QualitySettings.medium,
      isCreatingRoom: false,
    );
  }

  AppState copyWith({
    ScreenSource? selectedScreenSource,
    QualitySettings? selectedQualitySettings,
    bool? isCreatingRoom,
    String? error,
  }) {
    return AppState(
      selectedScreenSource: selectedScreenSource ?? this.selectedScreenSource,
      selectedQualitySettings:
          selectedQualitySettings ?? this.selectedQualitySettings,
      isCreatingRoom: isCreatingRoom ?? this.isCreatingRoom,
      error: error ?? this.error,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppState &&
        other.selectedScreenSource == selectedScreenSource &&
        other.selectedQualitySettings == selectedQualitySettings &&
        other.isCreatingRoom == isCreatingRoom &&
        other.error == error;
  }

  @override
  int get hashCode {
    return selectedScreenSource.hashCode ^
        selectedQualitySettings.hashCode ^
        isCreatingRoom.hashCode ^
        error.hashCode;
  }
}
