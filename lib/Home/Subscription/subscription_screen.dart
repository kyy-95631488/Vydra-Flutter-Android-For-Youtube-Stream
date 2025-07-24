// subscription_screen.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vydra/Auth/Service/auth_service.dart';
import 'package:vydra/Auth/Api/api_manager.dart';
import 'package:vydra/Home/Settings/settings_screen.dart';
import 'package:vydra/Home/VideoPlayer/video_player_screen.dart';
import 'package:vydra/Home/ChannelDetail/channel_details_screen.dart';
import 'package:vydra/Component/NavBar/custom_bottom_navigation_bar.dart';
import 'package:vydra/Home/VideoList/video_list_screen.dart';
import 'package:shared_preferences/shared_preferences.dart'; // For caching

class SubscriptionScreen extends StatefulWidget {
  final User user;
  final String accessToken;

  const SubscriptionScreen({super.key, required this.user, required this.accessToken});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  List<dynamic> channels = [];
  List<dynamic> videos = [];
  bool isLoading = true;
  bool isLoadingMore = false;
  String? errorMessage;
  String? nextPageToken;
  String? selectedChannelId;
  final AuthService _authService = AuthService();
  final ApiManager _apiManager = ApiManager();
  final ScrollController _scrollController = ScrollController();
  int _selectedIndex = 1;
  late SharedPreferences _prefs; // For caching
  static const String _cacheKeyChannels = 'cached_channels';
  static const String _cacheKeyVideos = 'cached_videos';

  @override
  void initState() {
    super.initState();
    _initPrefs();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadCachedData();
    await fetchSubscriptions();
  }

  @override
  void dispose() {
    _scrollController.dispose();
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

  Future<void> _loadCachedData() async {
    final cachedChannels = _prefs.getString(_cacheKeyChannels);
    final cachedVideos = _prefs.getString(_cacheKeyVideos);
    if (cachedChannels != null && cachedVideos != null) {
      setState(() {
        channels = jsonDecode(cachedChannels);
        videos = jsonDecode(cachedVideos);
        isLoading = false;
      });
    }
  }

  Future<void> _cacheData() async {
    await _prefs.setString(_cacheKeyChannels, jsonEncode(channels));
    await _prefs.setString(_cacheKeyVideos, jsonEncode(videos));
  }

  Future<void> fetchSubscriptions({String? pageToken}) async {
    setState(() {
      isLoading = pageToken == null;
      isLoadingMore = pageToken != null;
      errorMessage = null;
    });

    try {
      final accessToken = await _authService.getAccessToken();
      if (accessToken == null) {
        throw Exception('No valid access token. Please sign in again.');
      }

      final url = Uri.parse(
        'https://www.googleapis.com/youtube/v3/subscriptions?part=snippet&mine=true&maxResults=50${pageToken != null ? '&pageToken=$pageToken' : ''}',
      );

      final data = await _apiManager.makeApiRequest(
        url,
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      final fetchedChannels = data['items'] ?? [];
      nextPageToken = data['nextPageToken'];

      if (fetchedChannels.isEmpty && pageToken == null) {
        setState(() {
          errorMessage = 'No subscriptions found.';
          isLoading = false;
          isLoadingMore = false;
        });
        return;
      }

      setState(() {
        if (pageToken == null) {
          channels = fetchedChannels;
        } else {
          channels.addAll(fetchedChannels);
        }
      });

      await _cacheData();
      await fetchSubscriptionVideos(pageToken: pageToken);
    } catch (e) {
      print('Error fetching subscriptions: $e');
      setState(() {
        errorMessage = 'Error loading subscriptions: $e';
        isLoading = false;
        isLoadingMore = false;
      });
    }
  }

  Future<void> fetchSubscriptionVideos({String? pageToken}) async {
    try {
      final accessToken = await _authService.getAccessToken();
      if (accessToken == null) {
        throw Exception('No valid access token. Please sign in again.');
      }

      final channelIds = channels
          .map((channel) => channel['snippet']['resourceId']['channelId'])
          .where((id) => id != null)
          .cast<String>()
          .toList();

      if (channelIds.isEmpty) {
        setState(() {
          videos = [];
          isLoading = false;
          isLoadingMore = false;
        });
        await _cacheData();
        return;
      }

      List<dynamic> allVideos = [];
      const int maxVideosPerChannel = 5; // Reduced to save quota
      for (String channelId in channelIds) {
        // Check cache first
        final cacheKey = 'videos_$channelId${pageToken ?? ''}';
        final cachedVideos = _prefs.getString(cacheKey);
        if (cachedVideos != null) {
          allVideos.addAll(jsonDecode(cachedVideos));
          continue;
        }

        final url = Uri.parse(
          'https://www.googleapis.com/youtube/v3/search?part=snippet&maxResults=$maxVideosPerChannel&order=date${pageToken != null ? '&pageToken=$pageToken' : ''}&type=video&channelId=$channelId&key=${_apiManager.currentApiKey}',
        );

        final data = await _apiManager.makeApiRequest(url);
        final videoItems = data['items'] ?? [];
        allVideos.addAll(videoItems);
        await _prefs.setString(cacheKey, jsonEncode(videoItems)); // Cache videos
      }

      final videoIds = allVideos
          .map((item) => item['id']?['videoId'])
          .where((id) => id != null)
          .cast<String>()
          .toList();

      if (videoIds.isEmpty) {
        setState(() {
          videos = [];
          isLoading = false;
          isLoadingMore = false;
        });
        await _cacheData();
        return;
      }

      // Batch video details request
      const int batchSize = 50; // Max IDs per request
      List<dynamic> fetchedVideos = [];
      for (int i = 0; i < videoIds.length; i += batchSize) {
        final batchIds = videoIds.sublist(
            i, i + batchSize > videoIds.length ? videoIds.length : i + batchSize);
        final videosUrl = Uri.parse(
          'https://www.googleapis.com/youtube/v3/videos?part=snippet,contentDetails&id=${batchIds.join(',')}&key=${_apiManager.currentApiKey}',
        );

        final videosData = await _apiManager.makeApiRequest(videosUrl);
        fetchedVideos.addAll(videosData['items'] ?? []);
      }

      fetchedVideos.sort((a, b) {
        final aDate = DateTime.parse(a['snippet']['publishedAt']);
        final bDate = DateTime.parse(b['snippet']['publishedAt']);
        return bDate.compareTo(aDate);
      });

      setState(() {
        if (pageToken == null) {
          videos = fetchedVideos;
        } else {
          videos.addAll(fetchedVideos);
        }
        isLoading = false;
        isLoadingMore = false;
      });
      await _cacheData();
    } catch (e) {
      print('Error fetching subscription videos: $e');
      setState(() {
        errorMessage = 'Error loading subscription videos: $e';
        isLoading = false;
        isLoadingMore = false;
      });
    }
  }

  Future<void> fetchMoreVideos() async {
    if (nextPageToken != null && !isLoadingMore) {
      await fetchSubscriptionVideos(pageToken: nextPageToken);
    }
  }

  Future<void> _refreshSubscriptions() async {
    setState(() {
      nextPageToken = null;
      channels = [];
      videos = [];
      selectedChannelId = null;
    });
    await _prefs.clear(); // Clear cache on refresh
    await fetchSubscriptions();
  }

  void _onNavItemTapped(int index) {
    if (_selectedIndex == index) {
      if (index == 1) {
        _refreshSubscriptions();
      }
      return;
    }

    setState(() {
      _selectedIndex = index;
    });

    switch (index) {
      case 0:
        Navigator.pop(context);
        break;
      case 1:
        break;
      case 2:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SettingsScreen()),
        ).then((_) {
          setState(() {
            _selectedIndex = 1;
          });
        });
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredVideos = selectedChannelId == null
        ? videos
        : videos.where((video) => video['snippet']['channelId'] == selectedChannelId).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshSubscriptions,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: const Text(
                    'Subscriptions',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
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
                                  onPressed: _refreshSubscriptions,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                child: const Text(
                                  'Channels',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: 120,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: channels.length,
                                  itemBuilder: (context, index) {
                                    return _buildChannelCard(channels[index]);
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                child: DropdownButton<String>(
                                  value: selectedChannelId,
                                  hint: const Text(
                                    'All Channels',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                  dropdownColor: const Color(0xFF1E293B),
                                  isExpanded: true,
                                  items: [
                                    const DropdownMenuItem<String>(
                                      value: null,
                                      child: Text(
                                        'All Channels',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    ...channels.map((channel) {
                                      final channelId = channel['snippet']['resourceId']['channelId'] ?? '';
                                      final channelTitle = channel['snippet']['title'] ?? 'Unknown Channel';
                                      return DropdownMenuItem<String>(
                                        value: channelId,
                                        child: Text(
                                          channelTitle,
                                          style: const TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 16,
                                            color: Colors.white,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      selectedChannelId = value;
                                    });
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Text(
                                  selectedChannelId == null
                                      ? 'Videos from Subscriptions'
                                      : 'Videos from ${channels.firstWhere((c) => c['snippet']['resourceId']['channelId'] == selectedChannelId, orElse: () => {'snippet': {'title': 'Selected Channel'}})['snippet']['title']}',
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
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
                    if (index < filteredVideos.length) {
                      return _buildVideoCard(filteredVideos[index]);
                    } else if (isLoadingMore) {
                      return const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: ModernLoadingWidget()),
                      );
                    }
                    return null;
                  },
                  childCount: filteredVideos.length + (isLoadingMore ? 1 : 0),
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

  Widget _buildChannelCard(dynamic channel) {
    final thumbnail = channel['snippet']['thumbnails']['default']['url'] ?? '';
    final title = channel['snippet']['title'] ?? 'Unknown Channel';
    final channelId = channel['snippet']['resourceId']['channelId'] ?? '';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChannelDetailsScreen(
              channelId: channelId,
              channelTitle: title,
            ),
          ),
        );
      },
      child: Container(
        width: 80,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundImage: CachedNetworkImageProvider(thumbnail),
              backgroundColor: Colors.grey[800],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
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
          crossAxisAlignment: CrossAxisAlignment.start,
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
                    width: 120,
                    height: 90,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: 120,
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