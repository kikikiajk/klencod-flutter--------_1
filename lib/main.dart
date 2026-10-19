import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

const String kArtist = 'سيد احمد المنصوري';
const String kFolder = 'assets/latmiyat/';
final RegExp kAudioExt =
    RegExp(r'\.(mp3|m4a|aac|wav|ogg|opus|flac)$', caseSensitive: false);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kArtist,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const PlayerPage(),
    );
  }
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final AudioPlayer _player = AudioPlayer();
  List<String> _paths = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  String _title(String path) {
    final name = path.split('/').last;
    final decoded = Uri.decodeFull(name);
    final original = decoded.replaceAll(kAudioExt, '');
    final cleaned = original
        .replaceAll(RegExp(r'-ar$', caseSensitive: false), '')
        .replaceAll(RegExp(r'(?:ال)?سيد\s+[أاإ]حمد\s+المنصوري'), '')
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r'^[\s\-–—|:،.]+|[\s\-–—|:،.]+$'), '')
        .trim();
    return cleaned.isEmpty ? original : cleaned;
  }

  Future<void> _init() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final paths = manifest
          .listAssets()
          .where((p) =>
              p.startsWith(kFolder) && kAudioExt.hasMatch(p))
          .toList()
        ..sort();

      if (paths.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'ما لقيت ملفات صوت داخل $kFolder';
        });
        return;
      }

      final playlist = ConcatenatingAudioSource(
        children: [
          for (final p in paths)
            AudioSource.asset(p),
        ],
      );
      await _player.setAudioSource(playlist);

      setState(() {
        _paths = paths;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'صار خطأ: $e';
      });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(kArtist), centerTitle: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center)))
              : Column(
                  children: [
                    Expanded(
                      child: StreamBuilder<int?>(
                        stream: _player.currentIndexStream,
                        builder: (context, snap) {
                          final current = snap.data;
                          return ListView.builder(
                            itemCount: _paths.length,
                            itemBuilder: (context, i) => ListTile(
                              leading: Text('${i + 1}'),
                              title: Text(_title(_paths[i])),
                              selected: i == current,
                              onTap: () async {
                                await _player.seek(Duration.zero, index: i);
                                _player.play();
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    _controls(),
                  ],
                ),
    );
  }

  Widget _controls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (context, snap) {
                final pos = snap.data ?? Duration.zero;
                final dur = _player.duration ?? Duration.zero;
                final max = dur.inMilliseconds.toDouble();
                final val = pos.inMilliseconds.toDouble().clamp(0.0, max > 0 ? max : 1.0);
                return Column(children: [
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Slider(
                      value: val,
                      max: max > 0 ? max : 1.0,
                      onChanged: (v) =>
                          _player.seek(Duration(milliseconds: v.toInt())),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [Text(_fmt(pos)), Text(_fmt(dur))],
                    ),
                  ),
                ]);
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                StreamBuilder<bool>(
                  stream: _player.shuffleModeEnabledStream,
                  builder: (context, snap) {
                    final on = snap.data ?? false;
                    return IconButton(
                      icon: Icon(Icons.shuffle,
                          color: on ? Colors.tealAccent : null),
                      onPressed: () =>
                          _player.setShuffleModeEnabled(!on),
                    );
                  },
                ),
                IconButton(
                  iconSize: 36,
                  icon: const Icon(Icons.skip_next),
                  onPressed: _player.seekToNext,
                ),
                StreamBuilder<PlayerState>(
                  stream: _player.playerStateStream,
                  builder: (context, snap) {
                    final playing = snap.data?.playing ?? false;
                    return IconButton.filled(
                      iconSize: 44,
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                      onPressed: playing ? _player.pause : _player.play,
                    );
                  },
                ),
                IconButton(
                  iconSize: 36,
                  icon: const Icon(Icons.skip_previous),
                  onPressed: _player.seekToPrevious,
                ),
                StreamBuilder<LoopMode>(
                  stream: _player.loopModeStream,
                  builder: (context, snap) {
                    final mode = snap.data ?? LoopMode.off;
                    const next = {
                      LoopMode.off: LoopMode.all,
                      LoopMode.all: LoopMode.one,
                      LoopMode.one: LoopMode.off,
                    };
                    return IconButton(
                      icon: Icon(
                        mode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                        color: mode == LoopMode.off ? null : Colors.tealAccent,
                      ),
                      onPressed: () => _player.setLoopMode(next[mode]!),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}