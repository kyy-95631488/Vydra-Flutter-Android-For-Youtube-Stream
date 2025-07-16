// playlist_videos_screen.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:animate_do/animate_do.dart';
import 'package:vydra/Auth/Api/api_manager.dart';
import 'package:vydra/Home/VideoPlayer/video_player_screen.dart';
import 'package:google_fonts/google_fonts.dart';

class PlaylistVideosScreen extends StatefulWidget {
  final String playlistId;
  final String playlistTitle;

  const PlaylistVideosScreen({
    super.key,
    required this.playlistId,
    required this.playlistTitle,
  });

  @override
  State<PlaylistVideosScreen> createState() => _PlaylistVideosScreenState();
}

class _PlaylistVideosScreenState extends State<PlaylistVideosScreen> {
  List<dynamic> _videos = [];
  List<dynamic> _filteredVideos = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreVideos = true;
  String? _nextPageToken;
  String? _errorMessage;
  String _searchQuery = '';
  final ApiManager _apiManager = ApiManager();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Map<String, String> _videoDurations = {}; // Store video durations

  @override
  void initState() {
    super.initState();
    _fetchPlaylistVideos();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _fetchPlaylistVideos({String? pageToken}) async {
    if (_isLoadingMore || !_hasMoreVideos) return;

    setState(() {
      if (pageToken == null) {
        _isLoading = true;
      } else {
        _isLoadingMore = true;
      }
      _errorMessage = null;
    });

    try {
      final url = Uri.parse(
        'https://www.googleapis.com/youtube/v3/playlistItems?part=snippet,contentDetails&playlistId=${widget.playlistId}&maxResults=50${pageToken != null ? '&pageToken=$pageToken' : ''}&key=${_apiManager.currentApiKey}',
      );

      final data = await _apiManager.makeApiRequest(url);

      final newVideos = data['items'] ?? [];
      final videoIds = newVideos
          .map((video) => video['snippet']['resourceId']['videoId'] as String?)
          .whereType<String>()
          .toList(); // Ensure only non-null Strings are included

      // Fetch durations for the new videos
      if (videoIds.isNotEmpty) {
        await _fetchVideoDurations(videoIds);
      }

      setState(() {
        if (pageToken == null) {
          _videos = newVideos;
        } else {
          _videos.addAll(newVideos);
        }
        _nextPageToken = data['nextPageToken'];
        _hasMoreVideos = _nextPageToken != null && newVideos.isNotEmpty;
        _updateFilteredVideos();
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error fetching playlist videos: $e';
        _isLoading = false;
        _isLoadingMore = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching playlist videos: $e')),
        );
      }
    }
  }

  Future<void> _fetchVideoDurations(List<String> videoIds) async {
    try {
      final url = Uri.parse(
        'https://www.googleapis.com/youtube/v3/videos?part=contentDetails&id=${videoIds.join(',')}&key=${_apiManager.currentApiKey}',
      );
      final data = await _apiManager.makeApiRequest(url);
      final items = data['items'] ?? [];

      setState(() {
        for (var item in items) {
          final videoId = item['id'];
          final duration = _parseDuration(item['contentDetails']['duration']);
          _videoDurations[videoId] = duration;
        }
      });
    } catch (e) {
      print('Error fetching video durations: $e');
    }
  }

  String _parseDuration(String isoDuration) {
    final regex = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?');
    final match = regex.firstMatch(isoDuration);
    if (match == null) return '0:00';

    final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
    final seconds = int.tryParse(match.group(3) ?? '0') ?? 0;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMoreVideos) {
      _fetchPlaylistVideos(pageToken: _nextPageToken);
    }
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim();
      _updateFilteredVideos();
    });
  }

  void _updateFilteredVideos() {
    if (_searchQuery.isEmpty) {
      _filteredVideos = List.from(_videos);
    } else {
      _filteredVideos = _videos.where((video) {
        final title = video['snippet']['title']?.toString().toLowerCase() ?? '';
        return title.contains(_searchQuery.toLowerCase());
      }).toList();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            expandedHeight: 200.0,
            floating: false,
            pinned: true,
            backgroundColor: const Color(0xFF1A1A2E),
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                shadows: [
                  Shadow(
                    blurRadius: 4.0,
                    color: Colors.black54,
                    offset: Offset(1, 1),
                  ),
                ],
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 50, bottom: 20, right: 20),
              title: FadeInDown(
                duration: const Duration(milliseconds: 600),
                child: Text(
                  widget.playlistTitle,
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    shadows: [
                      const Shadow(
                        blurRadius: 6.0,
                        color: Colors.black45,
                        offset: Offset(2, 2),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withOpacity(0.6),
                          Colors.transparent,
                        ],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                  ),
                  if (_videos.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: _videos[0]['snippet']['thumbnails']['high']['url'] ??
                          'https://via.placeholder.com/1500x500',
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(color: const Color(0xFFE0E0E0)),
                      errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.white, size: 40),
                    ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: FadeInUp(
                duration: const Duration(milliseconds: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _searchController,
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF0A0A23),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search videos in playlist...',
                        hintStyle: GoogleFonts.poppins(
                          color: Colors.grey[500],
                        ),
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF6200EA)),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Color(0xFF6200EA)),
                                onPressed: () {
                                  _searchController.clear();
                                  _onSearchChanged();
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Videos',
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0A0A23),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
          _isLoading
              ? const SliverToBoxAdapter(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF6200EA),
                      strokeWidth: 4,
                    ),
                  ),
                )
              : _errorMessage != null
                  ? SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FadeInUp(
                              duration: const Duration(milliseconds: 600),
                              child: Text(
                                _errorMessage!,
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  color: const Color(0xFFF44336),
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 20),
                            FadeInUp(
                              delay: const Duration(milliseconds: 200),
                              child: ElevatedButton(
                                onPressed: () => _fetchPlaylistVideos(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6200EA),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  elevation: 8,
                                  shadowColor: Colors.black26,
                                ),
                                child: Text(
                                  'Retry',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _filteredVideos.isEmpty
                      ? SliverToBoxAdapter(
                          child: FadeInUp(
                            duration: const Duration(milliseconds: 600),
                            child: Center(
                              child: Text(
                                _searchQuery.isEmpty
                                    ? 'No videos available in this playlist.'
                                    : 'No videos match your search.',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        )
                      : SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          sliver: SliverGrid(
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: screenWidth > 600 ? 3 : 2,
                              crossAxisSpacing: 20,
                              mainAxisSpacing: 20,
                              childAspectRatio: 0.7,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final video = _filteredVideos[index];
                                final videoId = video['snippet']['resourceId']['videoId'];
                                final thumbnail = video['snippet']['thumbnails']['high']['url'] ??
                                    'https://via.placeholder.com/150';
                                final title = video['snippet']['title'];
                                final duration = _videoDurations[videoId] ?? '0:00';

                                return FadeInUp(
                                  delay: Duration(milliseconds: 100 * (index % 10)),
                                  child: GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => VideoPlayerScreen(videoId: videoId),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.1),
                                            blurRadius: 12,
                                            offset: const Offset(0, 6),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          ClipRRect(
                                            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                                            child: Stack(
                                              children: [
                                                CachedNetworkImage(
                                                  imageUrl: thumbnail,
                                                  width: double.infinity,
                                                  height: 140,
                                                  fit: BoxFit.cover,
                                                  placeholder: (context, url) => Container(
                                                    width: double.infinity,
                                                    height: 140,
                                                    color: const Color(0xFFE0E0E0),
                                                  ),
                                                  errorWidget: (context, url, error) =>
                                                      const Icon(Icons.error, color: Colors.redAccent),
                                                ),
                                                Positioned.fill(
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        colors: [
                                                          Colors.transparent,
                                                          Colors.black.withOpacity(0.3),
                                                        ],
                                                        begin: Alignment.topCenter,
                                                        end: Alignment.bottomCenter,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                Positioned(
                                                  bottom: 8,
                                                  right: 8,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black.withOpacity(0.75),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      duration,
                                                      style: GoogleFonts.poppins(
                                                        fontSize: 12,
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.all(12.0),
                                            child: Text(
                                              title,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: const Color(0xFF0A0A23),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                              childCount: _filteredVideos.length,
                            ),
                          ),
                        ),
          if (_isLoadingMore && _searchQuery.isEmpty)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: CircularProgressIndicator(
                    color: Color(0xFF6200EA),
                    strokeWidth: 4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}