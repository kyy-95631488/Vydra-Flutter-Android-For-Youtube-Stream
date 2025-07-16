// video_player_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vydra/Auth/Service/auth_service.dart';
import 'package:vydra/Auth/Api/api_manager.dart';
import 'package:vydra/Home/ChannelDetail/channel_details_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:share_plus/share_plus.dart';

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
  String? _accessToken;
  final AuthService _authService = AuthService();
  final ApiManager _apiManager = ApiManager();
  String _selectedAudioQuality = '128';
  String _selectedVideoQuality = '144';
  final List<String> _audioQualityOptions = ['128', '192', '256', '320'];
  final List<String> _videoQualityOptions = ['144', '240', '360', '480', '720', '1080', '1440', '2160', '4320'];
  double _downloadProgress = 0.0;
  bool _isDownloadingAudio = false;
  bool _isDownloadingVideo = false;

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
        enableCaption: false,
      ),
    )..addListener(() {
        if (mounted) setState(() {});
      });

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    _initializeData();
  }

  Future<void> _initializeData() async {
    try {
      _accessToken = await _authService.getAccessToken();
      await Future.wait([
        _fetchVideoDetails(),
        _fetchComments(),
      ]);
      if (_videoDetails != null) {
        await Future.wait([
          _checkSubscriptionStatus(),
          _checkVideoRating(),
        ]);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error initializing data: $e';
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error initializing data: $e')),
        );
      }
    }
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
          _isLoading = false;
        });
        await _fetchChannelDetails(_videoDetails!['snippet']['channelId']);
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
      } else {
        throw Exception('Channel details not found.');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error fetching channel details: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching channel details: $e')),
        );
      }
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
        _errorMessage = 'Error fetching comments: $e';
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
      if (channelId == null || _accessToken == null) return;

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

  Future<String?> _getSubscriptionId(String channelId) async {
    try {
      final url = Uri.parse(
        'https://www.googleapis.com/youtube/v3/subscriptions?part=id&mine=true&forChannelId=$channelId&key=${_apiManager.currentApiKey}',
      );

      final data = await _apiManager.makeApiRequest(
        url,
        headers: {'Authorization': 'Bearer $_accessToken'},
      );

      return data['items']?.isNotEmpty ?? false ? data['items'][0]['id'] : null;
    } catch (e) {
      return null;
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

      if (_accessToken == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please sign in again to manage subscriptions')),
          );
        }
        return;
      }

      if (_isSubscribed) {
        final subscriptionId = await _getSubscriptionId(channelId);
        if (subscriptionId == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Subscription ID not found')),
            );
          }
          return;
        }

        final url = Uri.parse(
          'https://www.googleapis.com/youtube/v3/subscriptions?id=$subscriptionId&key=${_apiManager.currentApiKey}',
        );

        final response = await http.delete(
          url,
          headers: {'Authorization': 'Bearer $_accessToken'},
        );

        if (response.statusCode == 204) {
          setState(() {
            _isSubscribed = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Unsubscribed successfully')),
            );
          }
        } else {
          final errorData = json.decode(response.body);
          final errorMessage = errorData['error']?['message'] ?? 'Unknown error';
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to unsubscribe: $errorMessage')),
            );
          }
        }
      } else {
        final url = Uri.parse('https://www.googleapis.com/youtube/v3/subscriptions?part=snippet');
        final body = json.encode({
          'snippet': {
            'resourceId': {
              'kind': 'youtube#channel',
              'channelId': channelId,
            },
          },
        });

        final response = await http.post(
          url,
          headers: {
            'Authorization': 'Bearer $_accessToken',
            'Content-Type': 'application/json',
          },
          body: body,
        );

        if (response.statusCode == 200) {
          setState(() {
            _isSubscribed = true;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Subscribed successfully')),
            );
          }
        } else {
          final errorData = json.decode(response.body);
          final errorMessage = errorData['error']?['message'] ?? 'Unknown error';
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to subscribe: $errorMessage')),
            );
          }
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
      } else {
        throw Exception('Failed to fetch video rating');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error checking video rating: $e')),
        );
      }
    }
  }

  Future<void> _rateVideo(String rating) async {
    try {
      if (_accessToken == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please sign in to like/dislike videos')),
          );
        }
        return;
      }

      final url = Uri.parse(
        'https://www.googleapis.com/youtube/v3/videos/rate?id=${widget.videoId}&rating=$rating&key=${_apiManager.currentApiKey}',
      );
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

  Future<void> _downloadAudio() async {
    try {
      setState(() {
        _isDownloadingAudio = true;
        _downloadProgress = 0.0;
      });

      final url = Uri.parse('https://nextmusicplayerapi.up.railway.app/api/download?id=${widget.videoId}&quality=$_selectedAudioQuality');
      final client = http.Client();
      final request = http.Request('GET', url);
      final response = await client.send(request);

      if (response.statusCode == 200) {
        final totalBytes = response.contentLength ?? -1;
        int receivedBytes = 0;
        final List<int> bytes = [];

        final directory = await getExternalStorageDirectory();
        if (directory == null) {
          throw Exception('Could not access download directory');
        }
        final filePath = '${directory.path}/audio_${widget.videoId}_${_selectedAudioQuality}kbps.mp3';

        final file = File(filePath);
        final sink = file.openWrite();

        response.stream.listen(
          (chunk) {
            bytes.addAll(chunk);
            receivedBytes += chunk.length;
            if (totalBytes > 0) {
              setState(() {
                _downloadProgress = receivedBytes / totalBytes;
              });
            } else {
              setState(() {
                _downloadProgress = receivedBytes / (receivedBytes + 1000000);
              });
            }
            sink.add(chunk);
          },
          onDone: () async {
            await sink.close();
            setState(() {
              _isDownloadingAudio = false;
              _downloadProgress = 1.0;
            });
            if (mounted) {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Download Completed', style: TextStyle(color: Colors.black)),
                  content: Text('File saved to: $filePath', style: const TextStyle(color: Colors.black)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK', style: TextStyle(color: Colors.black)),
                    ),
                  ],
                  backgroundColor: Colors.white,
                ),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Audio download completed for ${_selectedAudioQuality}kbps')),
              );
            }
            client.close();
          },
          onError: (e) async {
            await sink.close();
            setState(() {
              _isDownloadingAudio = false;
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error during audio download: $e')),
              );
            }
            client.close();
          },
          cancelOnError: true,
        );
      } else {
        throw Exception('Failed to start audio download: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isDownloadingAudio = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting audio download: $e')),
        );
      }
    }
  }

  Future<void> _downloadVideo() async {
    try {
      setState(() {
        _isDownloadingVideo = true;
        _downloadProgress = 0.0;
      });

      final url = Uri.parse('https://nextmusicplayerapi.up.railway.app/api/download-mp4?id=${widget.videoId}&quality=$_selectedVideoQuality');
      final client = http.Client();
      final request = http.Request('GET', url);
      final response = await client.send(request);

      if (response.statusCode == 200) {
        final totalBytes = response.contentLength ?? -1;
        int receivedBytes = 0;
        final List<int> bytes = [];

        final directory = await getExternalStorageDirectory();
        if (directory == null) {
          throw Exception('Could not access download directory');
        }
        final filePath = '${directory.path}/video_${widget.videoId}_${_selectedVideoQuality}p.mp4';

        final file = File(filePath);
        final sink = file.openWrite();

        response.stream.listen(
          (chunk) {
            bytes.addAll(chunk);
            receivedBytes += chunk.length;
            if (totalBytes > 0) {
              setState(() {
                _downloadProgress = receivedBytes / totalBytes;
              });
            } else {
              setState(() {
                _downloadProgress = receivedBytes / (receivedBytes + 1000000);
              });
            }
            sink.add(chunk);
          },
          onDone: () async {
            await sink.close();
            setState(() {
              _isDownloadingVideo = false;
              _downloadProgress = 1.0;
            });
            if (mounted) {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Download Completed', style: TextStyle(color: Colors.black)),
                  content: Text('File saved to: $filePath', style: const TextStyle(color: Colors.black)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK', style: TextStyle(color: Colors.black)),
                    ),
                  ],
                  backgroundColor: Colors.white,
                ),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Video download completed for ${_selectedVideoQuality}p')),
              );
            }
            client.close();
          },
          onError: (e) async {
            await sink.close();
            setState(() {
              _isDownloadingVideo = false;
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error during video download: $e')),
              );
            }
            client.close();
          },
          cancelOnError: true,
        );
      } else {
        throw Exception('Failed to start video download: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isDownloadingVideo = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting video download: $e')),
        );
      }
    }
  }

  Future<void> _shareVideo() async {
    try {
      final url = 'https://www.youtube.com/watch?v=${widget.videoId}';
      final title = _videoDetails?['snippet']?['title'] ?? 'Check out this video';
      await Share.share(
        '$title: $url',
        subject: title,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video shared successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing video: $e')),
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
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

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
          backgroundColor: const Color(0xFF0A0A0A),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF1A1A1A).withOpacity(0.9),
                    const Color(0xFF0A0A0A).withOpacity(0.9),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 24),
              onPressed: () => Navigator.pop(context),
              tooltip: 'Back',
            ),
            title: Text(
              _videoDetails?['snippet']?['title'] ?? 'Video Player',
              style: GoogleFonts.inter(
                fontSize: screenWidth * 0.045,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share, color: Colors.white70, size: 24),
                onPressed: _shareVideo,
                tooltip: 'Share',
              ),
            ],
          ),
          body: _isLoading
              ? Center(
                  child: Shimmer.fromColors(
                    baseColor: Colors.grey[900]!,
                    highlightColor: Colors.grey[700]!,
                    child: Container(
                      width: screenWidth * 0.3,
                      height: screenWidth * 0.3,
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
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
                              color: Colors.white60,
                              fontSize: screenWidth * 0.04,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          GestureDetector(
                            onTap: _initializeData,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: screenWidth * 0.06,
                                vertical: screenHeight * 0.015,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFF007A), Color(0xFF00DDEB)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(25),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFF007A).withOpacity(0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Text(
                                'Retry',
                                style: GoogleFonts.inter(
                                  fontSize: screenWidth * 0.04,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: AnimatedBuilder(
                            animation: _animationController,
                            builder: (context, child) {
                              return FadeTransition(
                                opacity: _fadeAnimation,
                                child: SlideTransition(
                                  position: _slideAnimation,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.5),
                                              blurRadius: 10,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: AspectRatio(
                                          aspectRatio: 16 / 9,
                                          child: player,
                                        ),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.all(screenWidth * 0.04),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _videoDetails?['snippet']?['title'] ?? '',
                                              style: GoogleFonts.inter(
                                                fontSize: screenWidth * 0.05,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white,
                                                height: 1.3,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              '${_formatNumber(_videoDetails?['statistics']?['viewCount'] ?? '0')} views • ${_formatDate(_videoDetails?['snippet']?['publishedAt'])}',
                                              style: GoogleFonts.inter(
                                                fontSize: screenWidth * 0.035,
                                                color: Colors.white60,
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                _buildActionButton(
                                                  icon: _userRating == 'like'
                                                      ? Icons.thumb_up
                                                      : Icons.thumb_up_outlined,
                                                  label: _formatNumber(_videoDetails?['statistics']?['likeCount'] ?? '0'),
                                                  onTap: () => _rateVideo(_userRating == 'like' ? 'none' : 'like'),
                                                  isActive: _userRating == 'like',
                                                  tooltip: _userRating == 'like' ? 'Unlike' : 'Like',
                                                ),
                                                _buildActionButton(
                                                  icon: _userRating == 'dislike'
                                                      ? Icons.thumb_down
                                                      : Icons.thumb_down_outlined,
                                                  label: 'Dislike',
                                                  onTap: () => _rateVideo(_userRating == 'dislike' ? 'none' : 'dislike'),
                                                  isActive: _userRating == 'dislike',
                                                  tooltip: _userRating == 'dislike' ? 'Undislike' : 'Dislike',
                                                ),
                                                _buildActionButton(
                                                  icon: Icons.audiotrack,
                                                  label: _isDownloadingAudio ? 'Downloading...' : 'Audio',
                                                  onTap: _isDownloadingAudio ? null : _downloadAudio,
                                                  isActive: _isDownloadingAudio,
                                                  tooltip: 'Download Audio',
                                                ),
                                                _buildActionButton(
                                                  icon: Icons.videocam,
                                                  label: _isDownloadingVideo ? 'Downloading...' : 'Video',
                                                  onTap: _isDownloadingVideo ? null : _downloadVideo,
                                                  isActive: _isDownloadingVideo,
                                                  tooltip: 'Download Video',
                                                ),
                                              ],
                                            ),
                                            if (_isDownloadingAudio || _isDownloadingVideo)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 12),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      _isDownloadingAudio ? 'Audio Download Progress' : 'Video Download Progress',
                                                      style: GoogleFonts.inter(
                                                        fontSize: screenWidth * 0.035,
                                                        color: Colors.white70,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    LinearProgressIndicator(
                                                      value: _downloadProgress,
                                                      backgroundColor: Colors.white10,
                                                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00DDEB)),
                                                      minHeight: 6,
                                                      borderRadius: BorderRadius.circular(10),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            const SizedBox(height: 16),
                                            _buildChannelSection(),
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
                                                        padding: EdgeInsets.all(screenWidth * 0.04),
                                                        child: Text(
                                                          'No comments available.',
                                                          style: GoogleFonts.inter(
                                                            color: Colors.white60,
                                                            fontSize: screenWidth * 0.035,
                                                          ),
                                                        ),
                                                      ),
                                                    ]
                                                  : _comments.map((comment) {
                                                      final commentSnippet = comment['snippet']['topLevelComment']['snippet'];
                                                      return Padding(
                                                        padding: EdgeInsets.symmetric(
                                                          horizontal: screenWidth * 0.04,
                                                          vertical: screenHeight * 0.015,
                                                        ),
                                                        child: Row(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            CircleAvatar(
                                                              radius: screenWidth * 0.045,
                                                              backgroundImage: CachedNetworkImageProvider(
                                                                commentSnippet['authorProfileImageUrl'] ?? '',
                                                              ),
                                                              backgroundColor: Colors.grey[800],
                                                            ),
                                                            const SizedBox(width: 12),
                                                            Expanded(
                                                              child: Column(
                                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                                children: [
                                                                  Text(
                                                                    commentSnippet['authorDisplayName'] ?? '',
                                                                    style: GoogleFonts.inter(
                                                                      fontSize: screenWidth * 0.035,
                                                                      fontWeight: FontWeight.w600,
                                                                      color: Colors.white,
                                                                    ),
                                                                  ),
                                                                  const SizedBox(height: 4),
                                                                  Text(
                                                                    commentSnippet['textDisplay'] ?? '',
                                                                    style: GoogleFonts.inter(
                                                                      fontSize: screenWidth * 0.035,
                                                                      color: Colors.white70,
                                                                      height: 1.4,
                                                                    ),
                                                                  ),
                                                                  const SizedBox(height: 4),
                                                                  Text(
                                                                    _formatDate(commentSnippet['publishedAt']),
                                                                    style: GoogleFonts.inter(
                                                                      fontSize: screenWidth * 0.03,
                                                                      color: Colors.white60,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    }).toList(),
                                            ),
                                            const SizedBox(height: 12),
                                            _buildExpansionTile(
                                              title: 'Description',
                                              child: Padding(
                                                padding: EdgeInsets.all(screenWidth * 0.04),
                                                child: Text(
                                                  _videoDetails?['snippet']?['description'] ?? 'No description available.',
                                                  style: GoogleFonts.inter(
                                                    fontSize: screenWidth * 0.035,
                                                    color: Colors.white70,
                                                    height: 1.5,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            _buildExpansionTile(
                                              title: 'Audio Quality',
                                              child: Padding(
                                                padding: EdgeInsets.all(screenWidth * 0.04),
                                                child: DropdownButton<String>(
                                                  value: _selectedAudioQuality,
                                                  isExpanded: true,
                                                  dropdownColor: const Color(0xFF1A1A1A),
                                                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                                                  underline: Container(),
                                                  items: _audioQualityOptions.map((quality) {
                                                    return DropdownMenuItem<String>(
                                                      value: quality,
                                                      child: Text(
                                                        '${quality}kbps',
                                                        style: GoogleFonts.inter(
                                                          fontSize: screenWidth * 0.035,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    );
                                                  }).toList(),
                                                  onChanged: (value) {
                                                    if (value != null) {
                                                      setState(() {
                                                        _selectedAudioQuality = value;
                                                      });
                                                    }
                                                  },
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            _buildExpansionTile(
                                              title: 'Video Quality',
                                              child: Padding(
                                                padding: EdgeInsets.all(screenWidth * 0.04),
                                                child: DropdownButton<String>(
                                                  value: _selectedVideoQuality,
                                                  isExpanded: true,
                                                  dropdownColor: const Color(0xFF1A1A1A),
                                                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                                                  underline: Container(),
                                                  items: _videoQualityOptions.map((quality) {
                                                    return DropdownMenuItem<String>(
                                                      value: quality,
                                                      child: Text(
                                                        '${quality}p',
                                                        style: GoogleFonts.inter(
                                                          fontSize: screenWidth * 0.035,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    );
                                                  }).toList(),
                                                  onChanged: (value) {
                                                    if (value != null) {
                                                      setState(() {
                                                        _selectedVideoQuality = value;
                                                      });
                                                    }
                                                  },
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
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
    String? tooltip,
  }) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.scale(
          scale: isActive ? 1.05 : 1.0,
          child: Tooltip(
            message: tooltip ?? label,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.22,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF00DDEB).withOpacity(0.15) : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isActive ? const Color(0xFF00DDEB).withOpacity(0.5) : Colors.white.withOpacity(0.15),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isActive ? const Color(0xFF00DDEB).withOpacity(0.3) : Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      color: isActive ? const Color(0xFF00DDEB) : Colors.white70,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isActive ? const Color(0xFF00DDEB) : Colors.white70,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChannelSection() {
    return GestureDetector(
      onTap: () {
        if (_channelDetails != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChannelDetailsScreen(
                channelId: _videoDetails?['snippet']?['channelId'] ?? '',
                channelTitle: '',
              ),
            ),
          );
        }
      },
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Transform.scale(
            scale: _animationController.value,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.15)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundImage: CachedNetworkImageProvider(
                      _channelDetails?['snippet']?['thumbnails']?['default']?['url'] ?? '',
                    ),
                    backgroundColor: Colors.grey[800],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _channelDetails?['snippet']?['title'] ?? '',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_formatNumber(_channelDetails?['statistics']?['subscriberCount'] ?? '0')} subscribers',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _toggleSubscription,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _isSubscribed
                              ? [Colors.grey[700]!, Colors.grey[900]!]
                              : [const Color(0xFFFF007A), const Color(0xFF00DDEB)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: _isSubscribed
                                ? Colors.grey.withOpacity(0.3)
                                : const Color(0xFFFF007A).withOpacity(0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
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
          );
        },
      ),
    );
  }

  Widget _buildExpansionTile({
    required String title,
    Widget? child,
    Function(bool)? onExpansionChanged,
    List<Widget>? children,
  }) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, _) {
        return Transform.translate(
          offset: Offset(0, 15 * (1 - _animationController.value)),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
                splashColor: Colors.transparent,
              ),
              child: ExpansionTile(
                title: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 15,
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
          ),
        );
      },
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