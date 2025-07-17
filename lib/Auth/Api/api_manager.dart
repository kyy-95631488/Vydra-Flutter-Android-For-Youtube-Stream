// api_manager.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiManager {
  // List of API keys (replace with your actual API keys)
  static const List<String> _apiKeys = [
    'YOUR_API_KEY_HERE'
    // Add more API keys as needed
  ];

  int _currentApiKeyIndex = 0;
  static const String _cacheKeyPrefix = 'youtube_api_cache_';
  final Map<String, bool> _exhaustedKeys = {};

  // Get the current API key
  String get currentApiKey => _apiKeys[_currentApiKeyIndex];

  // Switch to the next available API key
  bool switchToNextApiKey() {
    if (_exhaustedKeys.length >= _apiKeys.length) {
      return false; // All keys are exhausted
    }

    int initialIndex = _currentApiKeyIndex;
    do {
      _currentApiKeyIndex = (_currentApiKeyIndex + 1) % _apiKeys.length;
      if (!_exhaustedKeys.containsKey(_apiKeys[_currentApiKeyIndex])) {
        print('Switched to API key: ${_apiKeys[_currentApiKeyIndex]}');
        return true; // Found a non-exhausted key
      }
    } while (_currentApiKeyIndex != initialIndex);

    return false; // No available keys
  }

  // Mark an API key as exhausted
  void markKeyExhausted(String apiKey) {
    _exhaustedKeys[apiKey] = true;
    print('API key marked as exhausted: $apiKey');
  }

  // Cache API response
  Future<void> cacheResponse(String url, dynamic response) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = '$_cacheKeyPrefix${url.hashCode}';
    final cacheData = {
      'data': response,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    await prefs.setString(cacheKey, json.encode(cacheData));
  }

  // Retrieve cached response
  Future<dynamic> getCachedResponse(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = '$_cacheKeyPrefix${url.hashCode}';
    final cachedData = prefs.getString(cacheKey);
    if (cachedData != null) {
      final decoded = json.decode(cachedData);
      final timestamp = decoded['timestamp'] as int;
      final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
      // Cache valid for 1 hour (3600000 ms)
      if (cacheAge < 3600000) {
        print('Returning cached response for $url');
        return decoded['data'];
      } else {
        await prefs.remove(cacheKey); // Clear expired cache
        print('Cleared expired cache for $url');
      }
    }
    return null;
  }

  // Make an API request with retry on quota exhaustion
  Future<dynamic> makeApiRequest(
    Uri url, {
    Map<String, String>? headers,
    int retries = 0,
  }) async {
    // Check cache first
    final cachedResponse = await getCachedResponse(url.toString());
    if (cachedResponse != null) {
      return cachedResponse;
    }

    // Replace placeholder API key in URL
    final modifiedUrl = Uri.parse(url.toString().replaceAll('API_KEY', _apiKeys[_currentApiKeyIndex]));
    print('Making API request to: $modifiedUrl');

    final response = await http.get(modifiedUrl, headers: headers);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      await cacheResponse(url.toString(), data); // Cache the response
      return data;
    } else {
      final errorData = json.decode(response.body);
      final errorMessage = errorData['error']?['message'] ?? 'Unknown error';
      print('API error: ${response.statusCode} - $errorMessage');

      if (response.statusCode == 403 && errorMessage.contains('quota')) {
        markKeyExhausted(_apiKeys[_currentApiKeyIndex]);
        if (retries < _apiKeys.length - 1 && switchToNextApiKey()) {
          print('Retrying with new API key: ${_apiKeys[_currentApiKeyIndex]}');
          return makeApiRequest(url, headers: headers, retries: retries + 1);
        } else {
          throw Exception('All API keys have exceeded quota');
        }
      } else {
        throw Exception('API error: ${response.statusCode} - $errorMessage');
      }
    }
  }
}