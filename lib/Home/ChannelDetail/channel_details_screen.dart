// channel_details_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:vydra/Auth/Api/api_manager.dart';
import 'package:vydra/Auth/Service/auth_service.dart';
import 'package:vydra/Home/VideoPlayer/video_player_screen.dart';
import 'package:animate_do/animate_do.dart';

class ChannelDetailsScreen extends StatefulWidget {
  final String channelId;
  final String channelTitle;

  const ChannelDetailsScreen({
    super.key,
    required this.channelId,
    required this.channelTitle,
  });

  @override
  State<ChannelDetailsScreen> createState() => _ChannelDetailsScreenState();
}

class _ChannelDetailsScreenState extends State<ChannelDetailsScreen> {
  Map<String, dynamic>? _channelDetails;
  List<dynamic> _videos = [];
  List<dynamic> _filteredVideos = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreVideos = true;
  bool _isSubscribed = false;
  String? _errorMessage;
  String? _nextPageToken;
  String? _uploadsPlaylistId;
  String _searchQuery = '';
  final ApiManager _apiManager = ApiManager();
  final AuthService _authService = AuthService();
  String? _accessToken;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeData();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _initializeData() async {
    await _fetchChannelDetails();
    await _fetchUploadsPlaylistId();
    await _fetchChannelVideos();
    await _checkSubscriptionStatus();
  }

  Future<void> _fetchChannelDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final url = Uri.parse(
        'https://www.googleapis.com/youtube/v3/channels?part=snippet,statistics,brandingSettings,contentDetails&id=${widget.channelId}&key=${_apiManager.currentApiKey}',
      );

      final data = await _apiManager.makeApiRequest(url);

      if (data['items']?.isNotEmpty ?? false) {
        setState(() {
          _channelDetails = data['items'][0];
          _isLoading = false;
        });
      } else {
        throw Exception('Channel details not found.');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading channel details: $e';
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading channel details: $e')),
        );
      }
    }
  }

  Future<void> _fetchUploadsPlaylistId() async {
    try {
      final url = Uri.parse(
        'https://www.googleapis.com/youtube/v3/channels?part=contentDetails&id=${widget.channelId}&key=${_apiManager.currentApiKey}',
      );

      final data = await _apiManager.makeApiRequest(url);

      if (data['items']?.isNotEmpty ?? false) {
        setState(() {
          _uploadsPlaylistId = data['items'][0]['contentDetails']['relatedPlaylists']['uploads'];
        });
      } else {
        throw Exception('Uploads playlist not found.');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error fetching uploads playlist: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching uploads playlist: $e')),
        );
      }
    }
  }

  Future<void> _fetchChannelVideos({String? pageToken}) async {
    if (_isLoadingMore || !_hasMoreVideos || _uploadsPlaylistId == null) return;

    setState(() {
      if (pageToken == null) {
        _isLoading = true;
      } else {
        _isLoadingMore = true;
      }
    });

    try {
      final url = Uri.parse(
        'https://www.googleapis.com/youtube/v3/playlistItems?part=snippet&playlistId=$_uploadsPlaylistId&maxResults=50${pageToken != null ? '&pageToken=$pageToken' : ''}&key=${_apiManager.currentApiKey}',
      );

      final data = await _apiManager.makeApiRequest(url);

      setState(() {
        final newVideos = data['items'] ?? [];
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
        _isLoading = false;
        _isLoadingMore = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching channel videos: $e')),
        );
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        _hasMoreVideos &&
        !_isLoadingMore) {
      _fetchChannelVideos(pageToken: _nextPageToken);
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

  Future<void> _checkSubscriptionStatus() async {
    try {
      _accessToken = await _authService.getAccessToken();
      if (_accessToken == null) return;

      final url = Uri.parse(
        'https://www.googleapis.com/youtube/v3/subscriptions?part=snippet&mine=true&forChannelId=${widget.channelId}&key=${_apiManager.currentApiKey}',
      );

      final data = await _apiManager.makeApiRequest(
        url,
        headers: {'Authorization': 'Bearer $_accessToken'},
      );

      setState(() {
        _isSubscribed = (data['items'] ?? []).isNotEmpty;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error checking subscription status: $e')),
        );
      }
    }
  }

  Future<void> _toggleSubscription() async {
    try {
      _accessToken = await _authService.getAccessToken();
      if (_accessToken == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please sign in again to manage subscriptions')),
          );
        }
        return;
      }

      final url = _isSubscribed
          ? Uri.parse('https://www.googleapis.com/youtube/v3/subscriptions?part=snippet&forChannelId=${widget.channelId}&key=${_apiManager.currentApiKey}')
          : Uri.parse('https://www.googleapis.com/youtube/v3/subscriptions?part=snippet');
      final method = _isSubscribed ? 'DELETE' : 'POST';
      final body = _isSubscribed
          ? null
          : json.encode({
              'snippet': {
                'resourceId': {
                  'kind': 'youtube#channel',
                  'channelId': widget.channelId,
                },
              },
            });

      final response = await (method == 'POST'
          ? http.post(
              url,
              headers: {
                'Authorization': 'Bearer $_accessToken',
                'Content-Type': 'application/json',
              },
              body: body,
            )
          : http.delete(
              url,
              headers: {'Authorization': 'Bearer $_accessToken'},
            ));

      if (response.statusCode == 200 || response.statusCode == 204) {
        setState(() {
          _isSubscribed = !_isSubscribed;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_isSubscribed ? 'Subscribed successfully' : 'Unsubscribed successfully')),
          );
        }
      } else {
        final errorData = json.decode(response.body);
        final errorMessage = errorData['error']?['message'] ?? 'Unknown error';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to toggle subscription: $errorMessage')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error toggling subscription: $e')),
        );
      }
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            expandedHeight: 300.0,
            floating: false,
            pinned: true,
            backgroundColor: const Color(0xFF1A1A2E),
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back,
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
                  widget.channelTitle,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    shadows: [
                      Shadow(
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
                  _isLoading
                      ? Container(color: const Color(0xFFE0E0E0))
                      : CachedNetworkImage(
                          imageUrl: _channelDetails?['brandingSettings']?['image']?['bannerExternalUrl'] ??
                              'https://via.placeholder.com/1500x500',
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(color: const Color(0xFFE0E0E0)),
                          errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.white, size: 40),
                        ),
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
                  Positioned(
                    bottom: 70,
                    left: 20,
                    child: ElasticIn(
                      duration: const Duration(milliseconds: 800),
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.white,
                        child: ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: _channelDetails?['snippet']?['thumbnails']?['high']?['url'] ??
                                'https://via.placeholder.com/100',
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(color: const Color(0xFFE0E0E0)),
                            errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.redAccent),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF6200EA),
                      strokeWidth: 4,
                    ),
                  )
                : _errorMessage != null
                    ? Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FadeInUp(
                              duration: const Duration(milliseconds: 600),
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 16,
                                  color: Color(0xFFF44336),
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 20),
                            FadeInUp(
                              delay: const Duration(milliseconds: 200),
                              child: ElevatedButton(
                                onPressed: _initializeData,
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
                                child: const Text(
                                  'Retry',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                        child: FadeInUp(
                          duration: const Duration(milliseconds: 600),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _channelDetails?['snippet']?['title'] ?? widget.channelTitle,
                                          style: const TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 22,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0A0A23),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '${_formatNumber(_channelDetails?['statistics']?['subscriberCount'] ?? '0')} subscribers • '
                                          '${_formatNumber(_channelDetails?['statistics']?['videoCount'] ?? '0')} videos',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 14,
                                            color: Colors.grey[600],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ElasticIn(
                                    duration: const Duration(milliseconds: 800),
                                    child: GestureDetector(
                                      onTap: _toggleSubscription,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: _isSubscribed
                                                ? [Colors.grey[500]!, Colors.grey[700]!]
                                                : [const Color(0xFF6200EA), const Color(0xFF8B00FF)],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.circular(30),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.2),
                                              blurRadius: 10,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          _isSubscribed ? 'Subscribed' : 'Subscribe',
                                          style: const TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              FadeInUp(
                                delay: const Duration(milliseconds: 100),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 15,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: ExpansionTile(
                                    title: const Text(
                                      'Description',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF0A0A23),
                                      ),
                                    ),
                                    iconColor: const Color(0xFF6200EA),
                                    collapsedIconColor: const Color(0xFF6200EA),
                                    backgroundColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Text(
                                          _channelDetails?['snippet']?['description'] ?? 'No description available.',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 14,
                                            color: Colors.grey[700],
                                            height: 1.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              FadeInUp(
                                delay: const Duration(milliseconds: 200),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _searchController,
                                        style: const TextStyle(
                                          fontFamily: 'Poppins',
                                          color: Color(0xFF0A0A23), // Dark text for visibility
                                        ),
                                        decoration: InputDecoration(
                                          hintText: 'Search videos...',
                                          hintStyle: TextStyle(
                                            fontFamily: 'Poppins',
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
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              FadeInUp(
                                delay: const Duration(milliseconds: 200),
                                child: const Text(
                                  'Videos',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0A0A23),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),
          ),
          _filteredVideos.isEmpty && !_isLoading
              ? SliverToBoxAdapter(
                  child: FadeInUp(
                    duration: const Duration(milliseconds: 600),
                    child: Center(
                      child: Text(
                        _searchQuery.isEmpty ? 'No videos available.' : 'No videos match your search.',
                        style: TextStyle(
                          fontFamily: 'Poppins',
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
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 20,
                      mainAxisSpacing: 20,
                      childAspectRatio: 0.7,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final video = _filteredVideos[index];
                        final videoId = video['snippet']['resourceId']['videoId'];
                        final thumbnail = video['snippet']['thumbnails']['high']['url'];
                        final title = video['snippet']['title'];

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
                                          errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.redAccent),
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
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Text(
                                      title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF0A0A23),
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

  String _formatNumber(String number) {
    try {
      final numValue = int.parse(number);
      if (numValue >= 1000000) {
        return '${(numValue / 1000000).toStringAsFixed(1)}M';
      } else if (numValue >= 1000) {
        return '${(numValue / 1000).toStringAsFixed(1)}K';
      }
      return number;
    } catch (e) {
      return number;
    }
  }
}