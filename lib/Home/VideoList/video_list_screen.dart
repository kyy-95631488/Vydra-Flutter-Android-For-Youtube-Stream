// video_list_screen.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vydra/Component/NavBar/custom_bottom_navigation_bar.dart';
import 'package:vydra/Home/VideoPlayer/video_player_screen.dart';
import 'package:vydra/Auth/Service/auth_service.dart';
import 'package:vydra/Auth/Api/api_manager.dart';
import 'package:vydra/Home/Settings/settings_screen.dart'; // Import the new SettingsScreen

class VideoListScreen extends StatefulWidget {
  final User user;
  final String accessToken;

  const VideoListScreen({super.key, required this.user, required this.accessToken});

  @override
  State<VideoListScreen> createState() => _VideoListScreenState();
}

class _VideoListScreenState extends State<VideoListScreen> {
  List<dynamic> videos = [];
  List<dynamic> shorts = [];
  bool isLoading = true;
  bool isLoadingMore = false;
  String? highlightVideoId;
  String? errorMessage;
  String? nextPageToken;
  final AuthService _authService = AuthService();
  String? _currentAccessToken;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final ScrollController _scrollController = ScrollController();
  final ApiManager _apiManager = ApiManager();
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentAccessToken = widget.accessToken;
    fetchUserVideos();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !isLoadingMore &&
        nextPageToken != null) {
      fetchMoreVideos();
    }
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
      if (_searchQuery.isEmpty) {
        fetchUserVideos();
      } else {
        searchVideos(_searchQuery);
      }
    });
  }

  Future<void> fetchUserVideos({String? pageToken}) async {
    setState(() {
      isLoading = pageToken == null;
      isLoadingMore = pageToken != null;
      errorMessage = null;
    });

    try {
      _currentAccessToken = await _authService.getAccessToken();
      if (_currentAccessToken == null) {
        throw Exception('No valid access token. Please sign in again.');
      }

      final historyVideos = await _fetchWatchHistory(pageToken: pageToken);
      final recommendedVideos = await _fetchRecommendedVideos(pageToken: pageToken);

      final allVideos = [...historyVideos, ...recommendedVideos];

      if (allVideos.isEmpty && pageToken == null) {
        await fetchDefaultVideos();
        setState(() {
          errorMessage = 'No personalized videos found. Showing popular videos.';
        });
        return;
      }

      final fetchedVideos = <dynamic>[];
      final fetchedShorts = <dynamic>[];

      for (var video in allVideos) {
        final duration = video['contentDetails']?['duration'] ?? '';
        final isShort = _isShortVideo(duration);
        if (isShort) {
          fetchedShorts.add(video);
        } else {
          fetchedVideos.add(video);
        }
      }

      setState(() {
        if (pageToken == null) {
          videos = fetchedVideos;
          shorts = fetchedShorts;
          highlightVideoId = videos.isNotEmpty ? videos[0]['id'] : null;
        } else {
          videos.addAll(fetchedVideos);
          shorts.addAll(fetchedShorts);
        }
        isLoading = false;
        isLoadingMore = false;
      });
    } catch (e) {
      print('Error fetching user videos: $e');
      await fetchDefaultVideos(pageToken: pageToken);
      setState(() {
        errorMessage = 'Error loading personalized videos: $e. Showing popular videos.';
        isLoading = false;
        isLoadingMore = false;
      });
    }
  }

  Future<void> fetchMoreVideos() async {
    if (nextPageToken != null && !isLoadingMore) {
      if (_searchQuery.isNotEmpty) {
        await searchVideos(_searchQuery, pageToken: nextPageToken);
      } else {
        await fetchUserVideos(pageToken: nextPageToken);
      }
    }
  }

  Future<List<dynamic>> _fetchWatchHistory({String? pageToken}) async {
    final url = Uri.parse(
      'https://www.googleapis.com/youtube/v3/videos?part=snippet,contentDetails&myRating=like&maxResults=10${pageToken != null ? '&pageToken=$pageToken' : ''}',
    );

    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $_currentAccessToken'},
    );

    if (response.statusCode == 200) {
      try {
        final data = json.decode(response.body);
        nextPageToken = data['nextPageToken'];
        return data['items'] ?? [];
      } catch (e) {
        throw Exception('Failed to parse response: $e');
      }
    } else {
      try {
        final errorData = json.decode(response.body);
        final errorMessage = errorData['error']?['message'] ?? 'Unknown error';
        throw Exception(
          'Failed to load watch history: ${response.statusCode} - $errorMessage',
        );
      } catch (e) {
        throw Exception(
          'Failed to load watch history: ${response.statusCode} - Failed to parse error: $e',
        );
      }
    }
  }

  Future<List<dynamic>> _fetchRecommendedVideos({String? pageToken}) async {
    final url = Uri.parse(
      'https://www.googleapis.com/youtube/v3/activities?part=snippet,contentDetails&home=true&maxResults=10${pageToken != null ? '&pageToken=$pageToken' : ''}',
    );

    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $_currentAccessToken'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      nextPageToken = data['nextPageToken'];
      final items = data['items'] ?? [];
      final videoIds = items
          .where((item) => item['contentDetails']?['upload']?['videoId'] != null)
          .map((item) => item['contentDetails']['upload']['videoId'])
          .toList();

      if (videoIds.isEmpty) return [];

      final videosUrl = Uri.parse(
        'https://www.googleapis.com/youtube/v3/videos?part=snippet,contentDetails&id=${videoIds.join(',')}',
      );

      final videosResponse = await http.get(
        videosUrl,
        headers: {'Authorization': 'Bearer $_currentAccessToken'},
      );

      if (videosResponse.statusCode == 200) {
        final videosData = json.decode(videosResponse.body);
        return videosData['items'] ?? [];
      } else {
        final errorData = json.decode(videosResponse.body);
        throw Exception(
          'Failed to load recommended videos: ${videosResponse.statusCode} - ${errorData['error']?['message'] ?? 'Unknown error'}',
        );
      }
    } else {
      final errorData = json.decode(response.body);
      throw Exception(
        'Failed to load activities: ${response.statusCode} - ${errorData['error']?['message'] ?? 'Unknown error'}',
      );
    }
  }

  Future<void> fetchDefaultVideos({String? pageToken}) async {
    final url = Uri.parse(
      'https://www.googleapis.com/youtube/v3/videos?part=snippet,contentDetails&chart=mostPopular&maxResults=20${pageToken != null ? '&pageToken=$pageToken' : ''}&key=API_KEY',
    );

    try {
      final data = await _apiManager.makeApiRequest(url);
      nextPageToken = data['nextPageToken'];
      if (data['items'] == null) {
        throw Exception('No videos found in response');
      }

      final videoList = data['items'] as List<dynamic>;
      final fetchedVideos = <dynamic>[];
      final fetchedShorts = <dynamic>[];

      for (var video in videoList) {
        final duration = video['contentDetails']?['duration'] ?? '';
        final isShort = _isShortVideo(duration);
        if (isShort) {
          fetchedShorts.add(video);
        } else {
          fetchedVideos.add(video);
        }
      }

      setState(() {
        if (pageToken == null) {
          videos = fetchedVideos;
          shorts = fetchedShorts;
          highlightVideoId = videos.isNotEmpty ? videos[0]['id'] : null;
        } else {
          videos.addAll(fetchedVideos);
          shorts.addAll(fetchedShorts);
        }
        isLoading = false;
        isLoadingMore = false;
      });
    } catch (e) {
      print('Error fetching default videos: $e');
      setState(() {
        errorMessage = 'Error loading default videos: $e';
        isLoading = false;
        isLoadingMore = false;
      });
    }
  }

  Future<void> searchVideos(String query, {String? pageToken}) async {
    setState(() {
      isLoading = pageToken == null;
      isLoadingMore = pageToken != null;
      errorMessage = null;
    });

    final url = Uri.parse(
      'https://www.googleapis.com/youtube/v3/search?part=snippet&maxResults=20&q=$query${pageToken != null ? '&pageToken=$pageToken' : ''}&type=video&key=API_KEY',
    );

    try {
      final data = await _apiManager.makeApiRequest(url);
      nextPageToken = data['nextPageToken'];

      final videoIds = (data['items'] as List<dynamic>)
          .map((item) => item['id']?['videoId'])
          .where((id) => id != null)
          .cast<String>()
          .toList();

      if (videoIds.isEmpty) {
        setState(() {
          videos = [];
          shorts = [];
          highlightVideoId = null;
          isLoading = false;
          isLoadingMore = false;
          errorMessage = 'No videos found for "$query"';
        });
        return;
      }

      final videosUrl = Uri.parse(
        'https://www.googleapis.com/youtube/v3/videos?part=snippet,contentDetails&id=${videoIds.join(',')}&key=${_apiManager.currentApiKey}',
      );

      final videosData = await _apiManager.makeApiRequest(videosUrl);
      final videoList = videosData['items'] as List<dynamic>;

      final fetchedVideos = <dynamic>[];
      final fetchedShorts = <dynamic>[];

      for (var video in videoList) {
        final duration = video['contentDetails']?['duration'] ?? '';
        final isShort = _isShortVideo(duration);
        if (isShort) {
          fetchedShorts.add(video);
        } else {
          fetchedVideos.add(video);
        }
      }

      setState(() {
        if (pageToken == null) {
          videos = fetchedVideos;
          shorts = fetchedShorts;
          highlightVideoId = videos.isNotEmpty ? videos[0]['id'] : null;
        } else {
          videos.addAll(fetchedVideos);
          shorts.addAll(fetchedShorts);
        }
        isLoading = false;
        isLoadingMore = false;
      });
    } catch (e) {
      print('Error searching videos: $e');
      setState(() {
        errorMessage = 'Error searching videos: $e';
        isLoading = false;
        isLoadingMore = false;
      });
    }
  }

  bool _isShortVideo(String duration) {
    if (duration.isEmpty) return false;
    try {
      final regex = RegExp(r'PT(?:(\d+)M)?(?:(\d+)S)?');
      final match = regex.firstMatch(duration);
      if (match == null) return false;

      final minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
      final seconds = int.tryParse(match.group(2) ?? '0') ?? 0;
      final totalSeconds = (minutes * 60) + seconds;
      return totalSeconds < 60;
    } catch (e) {
      return false;
    }
  }

  Future<void> _refreshVideos() async {
    _currentAccessToken = await _authService.getAccessToken();
    if (_currentAccessToken == null) {
      setState(() {
        errorMessage = 'Please sign in again to refresh videos';
        isLoading = false;
      });
      await fetchDefaultVideos();
      return;
    }
    nextPageToken = null;
    if (_searchQuery.isNotEmpty) {
      await searchVideos(_searchQuery);
    } else {
      await fetchUserVideos();
    }
  }

  void _onNavItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    switch (index) {
      case 0:
        // Home: Already on VideoListScreen
        break;
      case 1:
        // Subscription: Placeholder for subscription screen
        // Navigator.push(context, MaterialPageRoute(builder: (context) => SubscriptionScreen()));
        break;
      case 2:
        // Settings: Navigate to settings screen
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SettingsScreen()),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshVideos,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search videos...',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                        prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.7)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: isLoading
                    ? const Center(child: ModernLoadingWidget())
                    : errorMessage != null
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  errorMessage!,
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _refreshVideos,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (highlightVideoId != null)
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _searchQuery.isEmpty ? 'Highlight Video' : 'Top Result',
                                        style: const TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 22,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      _buildHighlightVideo(videos[0]),
                                    ],
                                  ),
                                ),
                              if (shorts.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Shorts',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 22,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        height: 200,
                                        child: ListView.builder(
                                          scrollDirection: Axis.horizontal,
                                          itemCount: shorts.length,
                                          itemBuilder: (context, index) {
                                            return _buildShortsCard(shorts[index]);
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Text(
                                  _searchQuery.isEmpty ? 'Videos' : 'Search Results',
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index < videos.length) {
                      return _buildVideoCard(videos[index]);
                    } else if (isLoadingMore) {
                      return const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: ModernLoadingWidget()),
                      );
                    }
                    return null;
                  },
                  childCount: videos.length + (isLoadingMore ? 1 : 0),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: CustomBottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onNavItemTapped,
      ),
    );
  }

  String _formatDuration(String duration) {
    if (duration.isEmpty) return '';

    try {
      final regex = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?');
      final match = regex.firstMatch(duration);
      if (match == null) return '';

      final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
      final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
      final seconds = int.tryParse(match.group(3) ?? '0') ?? 0;

      if (hours > 0) {
        return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
      } else if (minutes > 0) {
        return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
      } else {
        return '0:${seconds.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return '';
    }
  }

  Widget _buildHighlightVideo(dynamic video) {
    final thumbnail = video['snippet']['thumbnails']['high']['url'] ?? '';
    final title = video['snippet']['title'] ?? 'Untitled';
    final channel = video['snippet']['channelTitle'] ?? 'Unknown Channel';
    final videoId = video['id'] ?? '';
    final duration = _formatDuration(video['contentDetails']['duration'] ?? '');

    return GestureDetector(
      onTap: () {
        if (videoId.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoPlayerScreen(videoId: videoId),
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: thumbnail,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      height: 200,
                      color: Colors.grey[800],
                      child: const Center(child: ModernLoadingWidget()),
                    ),
                    errorWidget: (context, url, error) => const Icon(Icons.error),
                  ),
                  if (duration != null && duration.toString().isNotEmpty)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.75),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            duration.toString(),
                            style: const TextStyle(
                              fontFamily: 'Poppins',
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    channel,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoCard(dynamic video) {
    final thumbnail = video['snippet']['thumbnails']['medium']['url'] ?? '';
    final title = video['snippet']['title'] ?? 'Untitled';
    final channel = video['snippet']['channelTitle'] ?? 'Unknown Channel';
    final videoId = video['id'] ?? '';
    final duration = _formatDuration(video['contentDetails']['duration'] ?? '');

    return GestureDetector(
      onTap: () {
        if (videoId.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoPlayerScreen(videoId: videoId),
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xFF1E293B).withOpacity(0.9),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              child: Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: thumbnail,
                    width: 160,
                    height: 90,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: 160,
                      height: 90,
                      color: Colors.grey[800],
                      child: const Center(child: ModernLoadingWidget()),
                    ),
                    errorWidget: (context, url, error) => const Icon(Icons.error),
                  ),
                  if (duration.isNotEmpty)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          duration,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      channel,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShortsCard(dynamic video) {
    final thumbnail = video['snippet']['thumbnails']['medium']['url'] ?? '';
    final title = video['snippet']['title'] ?? 'Untitled';
    final videoId = video['id'] ?? '';
    final duration = _formatDuration(video['contentDetails']['duration'] ?? '');

    return GestureDetector(
      onTap: () {
        if (videoId.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoPlayerScreen(videoId: videoId),
            ),
          );
        }
      },
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              CachedNetworkImage(
                imageUrl: thumbnail,
                width: 120,
                height: 200,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  width: 120,
                  height: 200,
                  color: Colors.grey[800],
                  child: const Center(child: ModernLoadingWidget()),
                ),
                errorWidget: (context, url, error) => const Icon(Icons.error),
              ),
              if (duration.isNotEmpty)
                Positioned(
                  bottom: 36,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      duration,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                    ],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ModernLoadingWidget extends StatefulWidget {
  const ModernLoadingWidget({super.key});

  @override
  _ModernLoadingWidgetState createState() => _ModernLoadingWidgetState();
}

class _ModernLoadingWidgetState extends State<ModernLoadingWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _opacityAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    Colors.blueAccent,
                    Colors.purpleAccent,
                    Colors.pinkAccent,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blueAccent.withOpacity(0.4),
                    blurRadius: 12,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.videocam,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}