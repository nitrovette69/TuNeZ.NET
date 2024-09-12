import 'dart:async';

import 'package:flutter_discord_rpc/flutter_discord_rpc.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotify/spotify.dart';
import 'package:spotube/extensions/artist_simple.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/utils/platform.dart';

class DiscordNotifier extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() async {
    final enabled = ref.watch(
        userPreferencesProvider.select((s) => s.discordPresence && kIsDesktop));

    var lastPosition = audioPlayer.position;

    final subscriptions = [
      FlutterDiscordRPC.instance.isConnectedStream.listen((connected) async {
        final playback = ref.read(audioPlayerProvider);
        if (connected && playback.activeTrack != null) {
          await updatePresence(playback.activeTrack!);
        }
      }),
      audioPlayer.playerStateStream.listen((state) async {
        final playback = ref.read(audioPlayerProvider);
        if (playback.activeTrack == null) return;

        await updatePresence(ref.read(audioPlayerProvider).activeTrack!);
      }),
      audioPlayer.positionStream.listen((position) async {
        final playback = ref.read(audioPlayerProvider);
        if (playback.activeTrack != null) {
          final diff = position.inMilliseconds - lastPosition.inMilliseconds;
          if (diff > 500 || diff < -500) {
            await updatePresence(ref.read(audioPlayerProvider).activeTrack!);
          }
        }
        lastPosition = position;
      })
    ];

    ref.onDispose(() async {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
      await close();
      await FlutterDiscordRPC.instance.dispose();
    });

    if (!enabled && FlutterDiscordRPC.instance.isConnected) {
      await clear();
      await close();
    } else {
      await FlutterDiscordRPC.instance.connect(autoRetry: true);
    }
  }

  Future<void> updatePresence(Track track) async {
    final artistNames = track.artists?.asString();
    final isPlaying = audioPlayer.isPlaying;
    final position = audioPlayer.position;

    await FlutterDiscordRPC.instance.setActivity(
      activity: RPCActivity(
        details: track.name,
        state: artistNames != null ? "by $artistNames" : null,
        assets: RPCAssets(
          largeImage:
              track.album?.images?.first.url ?? "spotube-logo-foreground",
          largeText: track.album?.name ?? "Unknown album",
          smallImage: "spotube-logo-foreground",
          smallText: "Spotube",
        ),
        buttons: [
          RPCButton(
            label: "Listen on Spotify",
            url: track.externalUrls?.spotify ??
                "https://open.spotify.com/tracks/${track.id}",
          ),
        ],
        timestamps: RPCTimestamps(
          start: isPlaying
              ? DateTime.now().millisecondsSinceEpoch - position.inMilliseconds
              : null,
        ),
        activityType: ActivityType.listening,
      ),
    );
  }

  Future<void> clear() async {
    await FlutterDiscordRPC.instance.clearActivity();
  }

  Future<void> close() async {
    await FlutterDiscordRPC.instance.disconnect();
  }
}

final discordProvider =
    AsyncNotifierProvider<DiscordNotifier, void>(() => DiscordNotifier());
