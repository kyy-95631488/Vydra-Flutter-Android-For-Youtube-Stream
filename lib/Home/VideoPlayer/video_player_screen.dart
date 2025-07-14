// video_player_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vydra/Auth/Service/auth_service.dart';
import 'package:vydra/Auth/Api/api_manager.dart';
import 'package:vydra/Home/ChannelDetail/channel_details_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoId;

  const VideoPlayerScreen({super.key, required this.videoId});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> with SingleTickerProviderStateMixin {
  late YoutubePlayerController _controller;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  Map<String, dynamic>? _videoDetails;
  Map<String, dynamic>? _channelDetails;
  List<dynamic> _comments = [];
  bool _isSubscribed = false;
  bool _isLoading = true;
  bool _isCommentsExpanded = false;
  String? _errorMessage;
  String? _userRating;
  final AuthService _authService = AuthService();
  String? _accessToken;
  final ApiManager _apiManager = ApiManager();

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController(
      initialVideoId: widget.videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        isLive: false,
        forceHD: true,
      ),
    )..addListener(() {
        if (mounted) setState(() {});
      });

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..forward();

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutQuart),
    );

    _initializeData();
  }

  Future<void> _initializeData() async {
    await _fetchVideoDetails();
    if (_videoDetails != null) {
      await _checkSubscriptionStatus();
      await _checkVideoRating();
    }
    await _fetchComments();
  }

  Future<void> _fetchVideoDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (!RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(widget.videoId)) {
        throw Exception('Invalid video ID format');
      }

      final videoUrl = Uri.parse(
        'https://www.googleapis.com/youtube/v3/videos?part=snippet,statistics&id=${widget.videoId}&key=${_apiManager.currentApiKey}',
      );

      final data = await _apiManager.makeApiRequest(videoUrl);

      if (data['items']?.isNotEmpty ?? false) {
        setState(() {
          _videoDetails = data['items'][0];
        });
        await _fetchChannelDetails(_videoDetails!['snippet']['channelId']);
        setState(() {
          _isLoading = false;
        });
      } else {
        throw Exception('Video details not found.');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading video details: $e';
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading video details: $e')),
        );
      }
    }
  }

  Future<void> _fetchChannelDetails(String channelId) async {
    try {
      final url = Uri.parse(
        'https://www.googleapis.com/youtube/v3/channels?part=snippet,statistics&id=$channelId&key=${_apiManager.currentApiKey}',
      );

      final data = await _apiManager.makeApiRequest(url);

      if (data['items']?.isNotEmpty ?? false) {
        setState(() {
          _channelDetails = data['items'][0];
        });
      }
    } catch (e) {
      print('Error fetching channel details: $e');
    }
  }

  Future<void> _fetchComments() async {
    try {
      final url = Uri.parse(
        'https://www.googleapis.com/youtube/v3/commentThreads?part=snippet&videoId=${widget.videoId}&maxResults=20&key=${_apiManager.currentApiKey}',
      );

      final data = await _apiManager.makeApiRequest(url);

      setState(() {
        _comments = data['items'] ?? [];
      });
    } catch (e) {
      setState(() {
        _comments = [];
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching comments: $e')),
        );
      }
    }
  }

  Future<void> _checkSubscriptionStatus() async {
    try {
      final channelId = _videoDetails?['snippet']?['channelId'];
      if (channelId == null) return;

      _accessToken = await _authService.getAccessToken();
      if (_accessToken == null) return;

      final url = Uri.parse(
        'https://www.googleapis.com/youtube/v3/subscriptions?part=snippet&mine=true&forChannelId=$channelId&key=${_apiManager.currentApiKey}',
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
      final channelId = _videoDetails?['snippet']?['channelId'];
      if (channelId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to toggle subscription: Channel ID not found')),
          );
        }
        return;
      }

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
          ? Uri.parse('https://www.googleapis.com/youtube/v3/subscriptions?part=snippet&forChannelId=$channelId&key=${_apiManager.currentApiKey}')
          : Uri.parse('https://www.googleapis.com/youtube/v3/subscriptions?part=snippet');
      final method = _isSubscribed ? 'DELETE' : 'POST';
      final body = _isSubscribed
          ? null
          : json.encode({
              'snippet': {
                'resourceId': {
                  'kind': 'youtube#channel',
                  'channelId': channelId,
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

  Future<void> _checkVideoRating() async {
    try {
      _accessToken = await _authService.getAccessToken();
      if (_accessToken == null) return;

      final url = Uri.parse(
        'https://www.googleapis.com/youtube/v3/videos/getRating?id=${widget.videoId}&key=${_apiManager.currentApiKey}',
      );

      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $_accessToken'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _userRating = data['items']?[0]?['rating'] ?? 'none';
        });
      }
    } catch (e) {
      print('Error checking video rating: $e');
    }
  }

  Future<void> _rateVideo(String rating) async {
    try {
      _accessToken = await _authService.getAccessToken();
      if (_accessToken == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please sign in to like/dislike videos')),
          );
        }
        return;
      }

      final url = Uri.parse('https://www.googleapis.com/youtube/v3/videos/rate?id=${widget.videoId}&rating=$rating');
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 204) {
        setState(() {
          _userRating = rating;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(rating == 'like' ? 'Video liked!' : rating == 'dislike' ? 'Video disliked!' : 'Rating removed!')),
          );
        }
        await _fetchVideoDetails();
      } else {
        final errorData = json.decode(response.body);
        final errorMessage = errorData['error']?['message'] ?? 'Unknown error';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to rate video: $errorMessage')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error rating video: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayerBuilder(
      onEnterFullScreen: () {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      },
      onExitFullScreen: () {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
      },
      player: YoutubePlayer(
        controller: _controller,
        showVideoProgressIndicator: true,
        progressIndicatorColor: const Color(0xFF00DDEB),
        progressColors: const ProgressBarColors(
          playedColor: Color(0xFF00DDEB),
          handleColor: Color(0xFFFF007A),
        ),
        onEnded: (metaData) {
          _controller.pause();
        },
      ),
      builder: (context, player) {
        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF1A1A1A).withOpacity(0.95),
                    const Color(0xFF2A2A2A).withOpacity(0.95),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: const Border(
                  bottom: BorderSide(color: Color(0xFF00DDEB), width: 1),
                ),
              ),
            ),
            title: Text(
              _videoDetails?['snippet']?['title'] ?? 'Video Player',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                shadows: [
                  Shadow(
                    blurRadius: 4,
                    color: Colors.black.withOpacity(0.3),
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: _isLoading
              ? Center(
                  child: Shimmer.fromColors(
                    baseColor: Colors.grey[800]!,
                    highlightColor: Colors.grey[600]!,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                )
              : _errorMessage != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _errorMessage!,
                            style: GoogleFonts.inter(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _initializeData,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF007A),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              shadowColor: const Color(0xFFFF007A).withOpacity(0.5),
                              elevation: 8,
                            ),
                            child: Text(
                              'Retry',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          child: FadeTransition(
                            opacity: _fadeAnimation,
                            child: SlideTransition(
                              position: _slideAnimation,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: player,
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _videoDetails?['snippet']?['title'] ?? 'Untitled',
                                          style: GoogleFonts.inter(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        GestureDetector(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => ChannelDetailsScreen(
                                                  channelId: _videoDetails?['snippet']?['channelId'] ?? '',
                                                  channelTitle: _videoDetails?['snippet']?['channelTitle'] ?? 'Unknown Channel',
                                                ),
                                              ),
                                            );
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(16),
                                              border: Border.all(color: Colors.white.withOpacity(0.1)),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.2),
                                                  blurRadius: 10,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              children: [
                                                ClipOval(
                                                  child: CachedNetworkImage(
                                                    imageUrl: _channelDetails?['snippet']?['thumbnails']?['default']?['url'] ??
                                                        'https://via.placeholder.com/40',
                                                    width: 48,
                                                    height: 48,
                                                    placeholder: (context, url) => Shimmer.fromColors(
                                                      baseColor: Colors.grey[800]!,
                                                      highlightColor: Colors.grey[600]!,
                                                      child: Container(
                                                        width: 48,
                                                        height: 48,
                                                        color: Colors.grey[800],
                                                      ),
                                                    ),
                                                    errorWidget: (context, url, error) =>
                                                        const Icon(Icons.error, color: Colors.white),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        _videoDetails?['snippet']?['channelTitle'] ?? 'Unknown Channel',
                                                        style: GoogleFonts.inter(
                                                          fontSize: 16,
                                                          fontWeight: FontWeight.w700,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                      Text(
                                                        '${_formatNumber(_channelDetails?['statistics']?['subscriberCount'] ?? '0')} subscribers • ${_formatNumber(_videoDetails?['statistics']?['viewCount'] ?? '0')} views • ${_formatDate(_videoDetails?['snippet']?['publishedAt'])}',
                                                        style: GoogleFonts.inter(
                                                          fontSize: 12,
                                                          color: Colors.white70,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                GestureDetector(
                                                  onTap: _toggleSubscription,
                                                  child: AnimatedContainer(
                                                    duration: const Duration(milliseconds: 300),
                                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        colors: _isSubscribed
                                                            ? [Colors.grey[700]!, Colors.grey[800]!]
                                                            : [const Color(0xFFFF007A), const Color(0xFF00DDEB)],
                                                        begin: Alignment.topLeft,
                                                        end: Alignment.bottomRight,
                                                      ),
                                                      borderRadius: BorderRadius.circular(12),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: _isSubscribed
                                                              ? Colors.black.withOpacity(0.2)
                                                              : const Color(0xFFFF007A).withOpacity(0.5),
                                                          blurRadius: 8,
                                                          offset: const Offset(0, 4),
                                                        ),
                                                      ],
                                                    ),
                                                    child: Text(
                                                      _isSubscribed ? 'Subscribed' : 'Subscribe',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w700,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            _buildActionButton(
                                              icon: _userRating == 'like'
                                                  ? Icons.thumb_up
                                                  : Icons.thumb_up_outlined,
                                              label: _formatNumber(_videoDetails?['statistics']?['likeCount'] ?? '0'),
                                              onTap: () => _rateVideo(_userRating == 'like' ? 'none' : 'like'),
                                              isActive: _userRating == 'like',
                                            ),
                                            const SizedBox(width: 12),
                                            _buildActionButton(
                                              icon: _userRating == 'dislike'
                                                  ? Icons.thumb_down
                                                  : Icons.thumb_down_outlined,
                                              label: 'Dislike',
                                              onTap: () => _rateVideo(_userRating == 'dislike' ? 'none' : 'dislike'),
                                              isActive: _userRating == 'dislike',
                                            ),
                                            const SizedBox(width: 12),
                                            _buildActionButton(
                                              icon: Icons.visibility_outlined,
                                              label: _formatNumber(_videoDetails?['statistics']?['viewCount'] ?? '0'),
                                              onTap: null,
                                              isActive: false,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        _buildExpansionTile(
                                          title: 'Description',
                                          child: Padding(
                                            padding: const EdgeInsets.all(16.0),
                                            child: Text(
                                              _videoDetails?['snippet']?['description'] ?? 'No description available.',
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
                                                color: Colors.white70,
                                                height: 1.5,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        _buildExpansionTile(
                                          title: 'Comments (${_comments.length})',
                                          onExpansionChanged: (expanded) {
                                            setState(() {
                                              _isCommentsExpanded = expanded;
                                            });
                                          },
                                          children: _comments.isEmpty
                                              ? [
                                                  Padding(
                                                    padding: const EdgeInsets.all(16.0),
                                                    child: Text(
                                                      'No comments available or comments are disabled.',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 14,
                                                        color: Colors.white70,
                                                      ),
                                                    ),
                                                  ),
                                                ]
                                              : _comments.map<Widget>((comment) {
                                                  final snippet = comment['snippet']?['topLevelComment']?['snippet'];
                                                  return Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                                                    child: Container(
                                                      decoration: BoxDecoration(
                                                        color: Colors.white.withOpacity(0.05),
                                                        borderRadius: BorderRadius.circular(12),
                                                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                                                      ),
                                                      child: ListTile(
                                                        contentPadding: const EdgeInsets.all(12),
                                                        leading: ClipOval(
                                                          child: CachedNetworkImage(
                                                            imageUrl: snippet?['authorProfileImageUrl'] ?? 'https://via.placeholder.com/32',
                                                            width: 40,
                                                            height: 40,
                                                            placeholder: (context, url) => Shimmer.fromColors(
                                                              baseColor: Colors.grey[800]!,
                                                              highlightColor: Colors.grey[600]!,
                                                              child: Container(
                                                                width: 40,
                                                                height: 40,
                                                                color: Colors.grey[800],
                                                              ),
                                                            ),
                                                            errorWidget: (context, url, error) => const Icon(Icons.error),
                                                          ),
                                                        ),
                                                        title: Text(
                                                          snippet?['authorDisplayName'] ?? 'Unknown',
                                                          style: GoogleFonts.inter(
                                                            fontSize: 14,
                                                            fontWeight: FontWeight.w600,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                        subtitle: Text(
                                                          snippet?['textDisplay'] ?? '',
                                                          style: GoogleFonts.inter(
                                                            fontSize: 12,
                                                            color: Colors.white70,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        );
      },
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required bool isActive,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF00DDEB).withOpacity(0.2) : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isActive ? const Color(0xFF00DDEB) : Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isActive ? const Color(0xFF00DDEB) : Colors.white70,
              size: 20,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: isActive ? const Color(0xFF00DDEB) : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpansionTile({
    required String title,
    Widget? child,
    Function(bool)? onExpansionChanged,
    List<Widget>? children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          collapsedBackgroundColor: Colors.transparent,
          backgroundColor: Colors.transparent,
          iconColor: Colors.white70,
          collapsedIconColor: Colors.white70,
          onExpansionChanged: onExpansionChanged,
          children: children ?? [child ?? Container()],
        ),
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

  String _formatDate(String? date) {
    if (date == null) return 'Unknown date';
    try {
      final dateTime = DateTime.parse(date);
      final now = DateTime.now();
      final difference = now.difference(dateTime);
      if (difference.inDays > 365) {
        return '${(difference.inDays / 365).floor()} years ago';
      } else if (difference.inDays > 30) {
        return '${(difference.inDays / 30).floor()} months ago';
      } else if (difference.inDays > 0) {
        return '${difference.inDays} days ago';
      } else {
        return 'Today';
      }
    } catch (e) {
      return 'Unknown date';
    }
  }
}