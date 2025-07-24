// download_manager_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';
import 'package:video_player/video_player.dart';
import 'package:path/path.dart' as path;
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';

class DownloadManagerScreen extends StatefulWidget {
  const DownloadManagerScreen({super.key});

  @override
  State<DownloadManagerScreen> createState() => _DownloadManagerScreenState();
}

class _DownloadManagerScreenState extends State<DownloadManagerScreen>
    with SingleTickerProviderStateMixin {
  List<FileSystemEntity> _mp3Files = [];
  List<FileSystemEntity> _mp4Files = [];
  List<FileSystemEntity> _filteredMp3Files = [];
  List<FileSystemEntity> _filteredMp4Files = [];
  Map<String, String?> _thumbnailPaths = {};
  bool _isLoading = true;
  late TabController _tabController;
  DateTimeRange? _selectedDateRange;
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentlyPlayingPath;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _requestPermissions().then((_) => _loadDownloadedFiles());
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.completed) {
        setState(() {
          _currentlyPlayingPath = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.storage,
      if (Platform.isAndroid && await Permission.storage.isDenied)
        Permission.manageExternalStorage,
    ].request();

    if (statuses[Permission.storage]!.isDenied ||
        (Platform.isAndroid &&
            statuses[Permission.manageExternalStorage]!.isDenied)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Storage permission denied. Cannot access files.',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _loadDownloadedFiles() async {
    try {
      final directory = await getExternalStorageDirectory();
      if (directory == null) {
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Could not access download directory',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      final files = await directory.list().toList();
      final mp4Files = files.where((file) => file.path.endsWith('.mp4')).toList();
      final thumbnailPaths = <String, String?>{};

      for (var file in mp4Files) {
        try {
          final thumbnailPath = await VideoThumbnail.thumbnailFile(
            video: file.path,
            imageFormat: ImageFormat.PNG,
            maxHeight: 64,
            quality: 75,
          );
          thumbnailPaths[file.path] = thumbnailPath;
        } catch (e) {
          thumbnailPaths[file.path] = null;
          print('Failed to generate thumbnail for ${file.path}: $e');
        }
      }

      setState(() {
        _mp3Files = files.where((file) => file.path.endsWith('.mp3')).toList()
          ..sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));
        _mp4Files = mp4Files
          ..sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));
        _filteredMp3Files = List.from(_mp3Files);
        _filteredMp4Files = List.from(_mp4Files);
        _thumbnailPaths = thumbnailPaths;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error loading files: $e',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _openFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'File does not exist',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
      final result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error opening file: ${result.message}',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error opening file: $e',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _playAudio(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Audio file does not exist',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      if (_currentlyPlayingPath == filePath) {
        await _audioPlayer.pause();
        setState(() {
          _currentlyPlayingPath = null;
        });
      } else {
        if (_currentlyPlayingPath != null) {
          await _audioPlayer.stop();
        }
        await _audioPlayer.play(DeviceFileSource(filePath));
        setState(() {
          _currentlyPlayingPath = filePath;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error playing audio: $e',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _deleteFile(String filePath, bool isMp3) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'File does not exist',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
      await file.delete();
      setState(() {
        if (isMp3) {
          _mp3Files.removeWhere((element) => element.path == filePath);
          _filteredMp3Files.removeWhere((element) => element.path == filePath);
        } else {
          _mp4Files.removeWhere((element) => element.path == filePath);
          _filteredMp4Files.removeWhere((element) => element.path == filePath);
          _thumbnailPaths.remove(filePath);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'File deleted successfully',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error deleting file: $e',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _renameFile(String filePath, bool isMp3, String currentName) async {
    String baseName = path.basenameWithoutExtension(currentName);
    String extension = path.extension(filePath).toLowerCase();
    TextEditingController _renameController = TextEditingController(text: baseName);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.transparent,
        content: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Rename File',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _renameController,
                style: GoogleFonts.poppins(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'New file name',
                  labelStyle: GoogleFonts.poppins(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.grey[800],
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[700]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.cyanAccent),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Extension: $extension',
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      String newName = _renameController.text.trim();
                      if (newName.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'File name cannot be empty',
                              style: GoogleFonts.poppins(color: Colors.white),
                            ),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return;
                      }

                      try {
                        final file = File(filePath);
                        final directory = file.parent;
                        final newFilePath = '${directory.path}/$newName$extension';
                        if (await File(newFilePath).exists()) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'File with this name already exists',
                                style: GoogleFonts.poppins(color: Colors.white),
                              ),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                          return;
                        }

                        await file.rename(newFilePath);
                        setState(() {
                          if (isMp3) {
                            final index = _mp3Files.indexWhere((element) => element.path == filePath);
                            if (index != -1) {
                              _mp3Files[index] = File(newFilePath);
                            }
                            final filteredIndex = _filteredMp3Files.indexWhere((element) => element.path == filePath);
                            if (filteredIndex != -1) {
                              _filteredMp3Files[filteredIndex] = File(newFilePath);
                            }
                            _mp3Files.sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));
                            _filteredMp3Files.sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));
                          } else {
                            final index = _mp4Files.indexWhere((element) => element.path == filePath);
                            if (index != -1) {
                              _mp4Files[index] = File(newFilePath);
                            }
                            final filteredIndex = _filteredMp4Files.indexWhere((element) => element.path == filePath);
                            if (filteredIndex != -1) {
                              _filteredMp4Files[filteredIndex] = File(newFilePath);
                            }
                            if (_thumbnailPaths.containsKey(filePath)) {
                              _thumbnailPaths[newFilePath] = _thumbnailPaths[filePath];
                              _thumbnailPaths.remove(filePath);
                            }
                            _mp4Files.sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));
                            _filteredMp4Files.sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));
                          }
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'File renamed successfully',
                              style: GoogleFonts.poppins(color: Colors.white),
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                        Navigator.pop(context);
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Error renaming file: $e',
                              style: GoogleFonts.poppins(color: Colors.white),
                            ),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Rename',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFileInfo(String filePath, String fileName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.cyanAccent, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'File Info',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Name: $fileName',
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Location: $filePath',
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Close',
                    style: GoogleFonts.poppins(
                      color: Colors.cyanAccent,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _filterFilesByDate() {
    setState(() {
      if (_selectedDateRange == null) {
        _filteredMp3Files = List.from(_mp3Files);
        _filteredMp4Files = List.from(_mp4Files);
      } else {
        _filteredMp3Files = _mp3Files.where((file) {
          final fileStat = (file as File).statSync();
          final fileDate = fileStat.modified;
          return fileDate.isAfter(_selectedDateRange!.start.subtract(const Duration(days: 1))) &&
              fileDate.isBefore(_selectedDateRange!.end.add(const Duration(days: 1)));
        }).toList()
          ..sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));
        _filteredMp4Files = _mp4Files.where((file) {
          final fileStat = (file as File).statSync();
          final fileDate = fileStat.modified;
          return fileDate.isAfter(_selectedDateRange!.start.subtract(const Duration(days: 1))) &&
              fileDate.isBefore(_selectedDateRange!.end.add(const Duration(days: 1)));
        }).toList()
          ..sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));
      }
    });
  }

  void _showDateRangePicker() {
    showDialog(
      context: context,
      builder: (context) {
        DateTimeRange? tempDateRange = _selectedDateRange;
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Colors.grey[900],
          insetPadding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Container(
            padding: const EdgeInsets.all(24),
            width: MediaQuery.of(context).size.width * 0.9,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today,
                      color: Colors.cyanAccent,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Select Date Range',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (tempDateRange != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${DateFormat('MMM dd, yyyy').format(tempDateRange.start)} - '
                      '${DateFormat('MMM dd, yyyy').format(tempDateRange.end)}',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: SfDateRangePicker(
                      onSelectionChanged: (DateRangePickerSelectionChangedArgs args) {
                        if (args.value is PickerDateRange) {
                          final PickerDateRange range = args.value;
                          if (range.startDate != null && range.endDate != null) {
                            tempDateRange = DateTimeRange(
                              start: range.startDate!,
                              end: range.endDate!,
                            );
                          }
                        }
                      },
                      selectionMode: DateRangePickerSelectionMode.range,
                      initialSelectedRange: _selectedDateRange != null
                          ? PickerDateRange(
                              _selectedDateRange!.start,
                              _selectedDateRange!.end,
                            )
                          : null,
                      startRangeSelectionColor: Colors.cyanAccent,
                      endRangeSelectionColor: Colors.cyanAccent,
                      rangeSelectionColor: Colors.cyanAccent.withOpacity(0.3),
                      headerStyle: DateRangePickerHeaderStyle(
                        textStyle: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        backgroundColor: Colors.grey[850],
                      ),
                      monthCellStyle: DateRangePickerMonthCellStyle(
                        textStyle: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                        todayTextStyle: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.cyanAccent,
                        ),
                        disabledDatesTextStyle: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                        weekendTextStyle: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                      yearCellStyle: DateRangePickerYearCellStyle(
                        textStyle: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                        todayTextStyle: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.cyanAccent,
                          fontWeight: FontWeight.w600,
                        ),
                        disabledDatesTextStyle: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      minDate: DateTime(2000),
                      maxDate: DateTime.now(),
                      view: DateRangePickerView.month,
                      enablePastDates: true,
                      showNavigationArrow: true,
                      navigationDirection: DateRangePickerNavigationDirection.horizontal,
                      backgroundColor: Colors.grey[900],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _selectedDateRange = null;
                          _filterFilesByDate();
                        });
                        Navigator.pop(context);
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.redAccent.withOpacity(0.3)),
                        ),
                      ),
                      child: Text(
                        'Clear Filter',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        if (tempDateRange != null) {
                          setState(() {
                            _selectedDateRange = tempDateRange;
                            _filterFilesByDate();
                          });
                        }
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: Text(
                        'Apply',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showVideoPreview(String filePath, String fileName) {
    showDialog(
      context: context,
      builder: (context) {
        return VideoPreviewDialog(filePath: filePath, fileName: fileName);
      },
    );
  }

  Widget _buildFileList(List<FileSystemEntity> files, bool isMp3) {
    if (files.isEmpty) {
      return Center(
        child: Text(
          isMp3 ? 'No audio files found' : 'No video files found',
          style: GoogleFonts.poppins(
            fontSize: 16,
            color: Colors.white70,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final fileName = file.path.split('/').last;
        final fileStat = (file as File).statSync();
        final fileDate = DateFormat('MMM dd, yyyy').format(fileStat.modified);
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: Colors.grey[900],
          child: InkWell(
            onTap: () => isMp3 ? _playAudio(file.path) : _openFile(file.path),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                      ),
                      child: isMp3
                          ? Icon(
                              _currentlyPlayingPath == file.path
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              color: Colors.cyanAccent,
                              size: 32,
                            )
                          : _thumbnailPaths[file.path] != null
                              ? Image.file(
                                  File(_thumbnailPaths[file.path]!),
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => Icon(
                                    Icons.videocam,
                                    color: Colors.cyanAccent,
                                    size: 32,
                                  ),
                                )
                              : Icon(
                                  Icons.videocam,
                                  color: Colors.cyanAccent,
                                  size: 32,
                                ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          fileName,
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          file.path,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Modified: $fileDate',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildDropdownMenu(file.path, fileName, isMp3),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDropdownMenu(String filePath, String fileName, bool isMp3) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        color: Colors.white70,
        size: 24,
      ),
      color: Colors.grey[850],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      offset: const Offset(0, 40),
      elevation: 4,
      itemBuilder: (context) => [
        if (!isMp3)
          PopupMenuItem(
            value: 'preview',
            child: _buildMenuItem(
              icon: Icons.preview,
              label: 'Preview',
              color: Colors.blueAccent,
            ),
          ),
        PopupMenuItem(
          value: isMp3 ? 'play_external' : 'play',
          child: _buildMenuItem(
            icon: Icons.play_arrow,
            label: isMp3 ? 'Play in External App' : 'Play',
            color: Colors.cyanAccent,
          ),
        ),
        PopupMenuItem(
          value: 'info',
          child: _buildMenuItem(
            icon: Icons.info_outline,
            label: 'Info',
            color: Colors.greenAccent,
          ),
        ),
        PopupMenuItem(
          value: 'rename',
          child: _buildMenuItem(
            icon: Icons.edit,
            label: 'Rename',
            color: Colors.amberAccent,
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: _buildMenuItem(
            icon: Icons.delete,
            label: 'Delete',
            color: Colors.redAccent,
          ),
        ),
      ],
      onSelected: (value) {
        switch (value) {
          case 'preview':
            _showVideoPreview(filePath, fileName);
            break;
          case 'play':
            _openFile(filePath);
            break;
          case 'play_external':
            _openFile(filePath);
            break;
          case 'info':
            _showFileInfo(filePath, fileName);
            break;
          case 'rename':
            _renameFile(filePath, isMp3, fileName);
            break;
          case 'delete':
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: Colors.grey[900],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Delete File',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Are you sure you want to delete $fileName?',
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.poppins(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            _deleteFile(filePath, isMp3);
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Delete',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
            break;
        }
      },
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        elevation: 0,
        title: Text(
          'Download Manager',
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.cyanAccent),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(
              Icons.filter_list,
              color: Colors.cyanAccent,
              size: 24,
            ),
            color: Colors.grey[850],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            offset: const Offset(0, 40),
            elevation: 4,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'filter',
                child: _buildMenuItem(
                  icon: Icons.calendar_today,
                  label: 'Filter by Date',
                  color: Colors.cyanAccent,
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'filter') {
                _showDateRangePicker();
              }
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.cyanAccent,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.cyanAccent,
          indicatorWeight: 3,
          labelStyle: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
          tabs: const [
            Tab(text: 'Audio'),
            Tab(text: 'Video'),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    color: Colors.cyanAccent,
                    backgroundColor: Colors.white.withOpacity(0.2),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildFileList(_filteredMp3Files, true),
                    _buildFileList(_filteredMp4Files, false),
                  ],
                ),
        ),
      ),
    );
  }
}

class VideoPreviewDialog extends StatefulWidget {
  final String filePath;
  final String fileName;

  const VideoPreviewDialog({super.key, required this.filePath, required this.fileName});

  @override
  _VideoPreviewDialogState createState() => _VideoPreviewDialogState();
}

class _VideoPreviewDialogState extends State<VideoPreviewDialog> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.filePath))
      ..initialize().then((_) {
        setState(() {
          _isInitialized = true;
        });
        _controller.setLooping(false);
        _controller.play();
      }).catchError((error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error loading video preview: $error',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[900],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Video Preview: ${widget.fileName}',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.redAccent),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _isInitialized
                ? AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        VideoPlayer(_controller),
                        if (!_controller.value.isPlaying)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.play_arrow,
                              color: Colors.cyanAccent,
                              size: 40,
                            ),
                          ),
                      ],
                    ),
                  )
                : Center(
                    child: CircularProgressIndicator(
                      color: Colors.cyanAccent,
                    ),
                  ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildActionButton(
                  icon: _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.cyanAccent,
                  onPressed: () {
                    if (_isInitialized) {
                      setState(() {
                        _controller.value.isPlaying ? _controller.pause() : _controller.play();
                      });
                    }
                  },
                  tooltip: _controller.value.isPlaying ? 'Pause' : 'Play',
                ),
                const SizedBox(width: 16),
                _buildActionButton(
                  icon: Icons.close,
                  color: Colors.redAccent,
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Close',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}