import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

const _mediaMaroon = Color(0xFF681D24);
const _mediaDeep = Color(0xFF421219);
const _mediaGold = Color(0xFFC69A43);
const _mediaGoldLight = Color(0xFFE5C77E);

class LessonMediaPlayerScreen extends StatelessWidget {
  const LessonMediaPlayerScreen({
    super.key,
    required this.title,
    required this.url,
    required this.type,
  });

  final String title;
  final String url;
  final String type;

  @override
  Widget build(BuildContext context) {
    final isVideo = type.toLowerCase() == 'video' || url.toLowerCase().contains('.m3u8');
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: _mediaDeep,
        foregroundColor: _mediaGoldLight,
      ),
      body: SafeArea(
        child: isVideo
            ? _VideoLessonPlayer(url: url)
            : _AudioLessonPlayer(url: url, title: title),
      ),
    );
  }
}

class _VideoLessonPlayer extends StatefulWidget {
  const _VideoLessonPlayer({required this.url});
  final String url;

  @override
  State<_VideoLessonPlayer> createState() => _VideoLessonPlayerState();
}

class _VideoLessonPlayerState extends State<_VideoLessonPlayer> {
  late final VideoPlayerController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = 'वीडियो लोड नहीं हो सका: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _time(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = value.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(_error!, textAlign: TextAlign.center),
      ));
    }
    if (!_controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: _mediaGold));
    }
    return Center(child: Padding(
      padding: const EdgeInsets.all(16),
      child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(child: VideoPlayer(_controller)),
            Container(
              color: _mediaDeep,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: _controller,
                builder: (context, value, _) => Column(
                  children: [
                    Row(children: [
                      IconButton(
                        color: _mediaGoldLight,
                        onPressed: () {
                          if (value.isPlaying) {
                            _controller.pause();
                          } else {
                            _controller.play();
                          }
                        },
                        icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                      ),
                      Expanded(child: Slider(
                        activeColor: _mediaGold,
                        inactiveColor: Colors.white24,
                        min: 0,
                        max: value.duration.inMilliseconds
                            .toDouble()
                            .clamp(1, double.infinity),
                        value: value.position.inMilliseconds
                            .toDouble()
                            .clamp(0, value.duration.inMilliseconds.toDouble()),
                        onChanged: (position) => _controller.seekTo(
                          Duration(milliseconds: position.round()),
                        ),
                      )),
                    ]),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(_time(value.position),
                        style: const TextStyle(color: _mediaGoldLight, fontSize: 11)),
                      Text(_time(value.duration),
                        style: const TextStyle(color: _mediaGoldLight, fontSize: 11)),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ));
  }
}

class _AudioLessonPlayer extends StatefulWidget {
  const _AudioLessonPlayer({required this.url, required this.title});
  final String url;
  final String title;

  @override
  State<_AudioLessonPlayer> createState() => _AudioLessonPlayerState();
}

class _AudioLessonPlayerState extends State<_AudioLessonPlayer> {
  final AudioPlayer _player = AudioPlayer();
  String? _error;
  bool _loading = true;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _prepare();
    _player.onDurationChanged.listen((value) {
      if (mounted) setState(() => _duration = value);
    });
    _player.onPositionChanged.listen((value) {
      if (mounted) setState(() => _position = value);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _position = _duration);
    });
  }

  Future<void> _prepare() async {
    try {
      await _player.setSourceUrl(widget.url);
      final duration = await _player.getDuration();
      if (mounted) setState(() {
        _duration = duration ?? Duration.zero;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = 'ऑडियो लोड नहीं हो सका: $e';
        _loading = false;
      });
    }
  }

  String _time(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = value.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _mediaGold));
    }
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(_error!, textAlign: TextAlign.center),
      ));
    }
    final maxMs = _duration.inMilliseconds.toDouble();
    final currentMs = _position.inMilliseconds.toDouble().clamp(0, maxMs > 0 ? maxMs : 1);
    return Center(child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 148,
          height: 148,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [_mediaDeep, _mediaMaroon],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: _mediaGold, width: 2),
            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 22)],
          ),
          child: const Icon(Icons.graphic_eq_rounded, size: 76, color: _mediaGoldLight),
        ),
        const SizedBox(height: 26),
        Text(widget.title, textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 24),
        Slider(
          activeColor: _mediaGold,
          min: 0,
          max: maxMs > 0 ? maxMs : 1,
          value: currentMs,
          onChanged: maxMs <= 0 ? null : (value) {
            final next = Duration(milliseconds: value.round());
            _player.seek(next);
            setState(() => _position = next);
          },
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(_time(_position), style: const TextStyle(fontSize: 12)),
          Text(_time(_duration), style: const TextStyle(fontSize: 12)),
        ]),
        const SizedBox(height: 16),
        StreamBuilder<PlayerState>(
          stream: _player.onPlayerStateChanged,
          initialData: _player.state,
          builder: (context, snapshot) {
            final playing = snapshot.data == PlayerState.playing;
            return CircleAvatar(
              radius: 34,
              backgroundColor: _mediaMaroon,
              child: IconButton(
                color: _mediaGoldLight,
                iconSize: 38,
                onPressed: () async {
                  if (playing) {
                    await _player.pause();
                  } else {
                    await _player.resume();
                  }
                },
                icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
              ),
            );
          },
        ),
      ]),
    ));
  }
}
