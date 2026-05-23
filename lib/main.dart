import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
/*
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyRemoteApp());
}
*/
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyBHQrH8Fb6lkvco3mFkl43eEdhUmvBxUb8",
      authDomain: "karaoke-app-7bdb6.firebaseapp.com",
      projectId: "karaoke-app-7bdb6",
      storageBucket: "karaoke-app-7bdb6.firebasestorage.app",
      messagingSenderId: "132139308690",
      appId: "1:132139308690:web:65209ea2900980b53a384b",
    ),
  );

  runApp(const MyRemoteApp());
}
class MyRemoteApp extends StatelessWidget {
  const MyRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Remote Secure',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.amber, brightness: Brightness.dark),
      home: const PhoneRemoteScreen(),
    );
  }
}

class PhoneRemoteScreen extends StatefulWidget {
  const PhoneRemoteScreen({super.key});

  @override
  State<PhoneRemoteScreen> createState() => _PhoneRemoteScreenState();
}

class _PhoneRemoteScreenState extends State<PhoneRemoteScreen> {
  String? _activeRoomId;
  bool _isLocked = true;
  bool _isCheckingMemory = true;

  final TextEditingController _pinInputController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _searchResults = [];
  bool _isLoading = false;

  bool _isKaraokeOnly = true;
  List<QueryDocumentSnapshot> _currentQueueDocs = [];

  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _voiceHintText = 'Nhập tên bài hát hoặc bấm Micro để nói...';

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _checkSavedPin();
  }

  Future<void> _checkSavedPin() async {
    final prefs = await SharedPreferences.getInstance();
    final String? savedPin = prefs.getString('saved_master_pin');

    if (savedPin != null && savedPin.isNotEmpty) {
      setState(() {
        _activeRoomId = 'room_$savedPin';
        _isLocked = false;
        _isCheckingMemory = false;
      });
      _initQueueListener();
    } else {
      setState(() { _isCheckingMemory = false; });
    }
  }

  void _initQueueListener() {
    if (_activeRoomId == null) return;
    FirebaseFirestore.instance
        .collection('secure_karaoke')
        .doc(_activeRoomId)
        .collection('queue')
        .orderBy('timestamp')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _currentQueueDocs = snapshot.docs;
        });
      }
    });

    _loadSuggestedSongs();
  }

  void _loadSuggestedSongs() {
    String defaultKeyword = _isKaraokeOnly ? 'karaoke hot nhất hiện nay' : 'nhạc trẻ hot nhất hiện nay';
    _searchSongFromYoutube(defaultKeyword, isSuggestion: true);
  }

  void _unlockAndSaveRemote() async {
    String input = _pinInputController.text.trim().toUpperCase();

    if (input.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_master_pin', input);

      setState(() {
        _activeRoomId = 'room_$input';
        _isLocked = false;
      });
      _initQueueListener();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập mã phòng hiển thị trên TV!')),
      );
    }
  }

  void _logoutAndClearPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_master_pin');
    setState(() {
      _activeRoomId = null;
      _isLocked = true;
      _pinInputController.clear();
      _searchResults.clear();
      _searchController.clear();
      _currentQueueDocs.clear();
    });
  }

  void _listenToVoice() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            setState(() { _isListening = false; _voiceHintText = 'Nhập tên bài hát hoặc bấm Micro để nói...'; });
          }
        },
        onError: (err) => setState(() { _isListening = false; }),
      );

      if (available) {
        setState(() { _isListening = true; _voiceHintText = '🎤 Đang lắng nghe...'; });
        _speech.listen(
          localeId: 'vi_VN',
          onResult: (result) {
            setState(() {
              _searchController.text = result.recognizedWords;
              if (result.finalResult) {
                _isListening = false;
                _voiceHintText = 'Nhập tên bài hát hoặc bấm Micro để nói...';
                _searchSongFromYoutube(_searchController.text);
              }
            });
          },
        );
      }
    } else {
      setState(() { _isListening = false; _voiceHintText = 'Nhập tên bài hát hoặc bấm Micro để nói...'; });
      _speech.stop();
    }
  }

  Future<void> _searchSongFromYoutube(String keyword, {bool isSuggestion = false}) async {
    if (keyword.trim().isEmpty) return;
    setState(() { _isLoading = true; _searchResults.clear(); });

    try {
      final ytClient = yt.YoutubeExplode();
      String searchQuery = isSuggestion ? keyword : (_isKaraokeOnly ? '$keyword karaoke' : keyword);
      final searchList = await ytClient.search.getVideos(searchQuery);

      List<Map<String, dynamic>> tempResults = [];
      for (var video in searchList) {
        final int durationSeconds = video.duration?.inSeconds ?? 240;
        tempResults.add({
          "title": video.title,
          "id": video.id.value,
          "thumbnail": video.thumbnails.mediumResUrl,
          "duration": durationSeconds,
        });
      }
      setState(() { _searchResults = tempResults; _isLoading = false; });
      ytClient.close();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingMemory) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.amber)));

    if (_isLocked) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text('Kết Nối Phòng Hát')),
        body: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.vpn_key, size: 60, color: Colors.amber),
              const SizedBox(height: 15),
              const Text('NHẬP MÃ PHÒNG ĐỂ ĐIỀU KHIỂN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text('Vui lòng nhập chính xác Mã hiển thị trên màn hình TV Box của phòng.', style: TextStyle(fontSize: 14, color: Colors.grey), textAlign: TextAlign.center),
              const SizedBox(height: 25),
              TextField(
                controller: _pinInputController,
                textCapitalization: TextCapitalization.characters,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 5, color: Colors.amber),
                decoration: const InputDecoration(hintText: 'NHẬP MÃ TRÊN TV', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 25),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade700, minimumSize: const Size(double.infinity, 50)),
                onPressed: _unlockAndSaveRemote,
                child: const Text('KẾT NỐI VÀO PHÒNG', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        ),
      );
    }

    return OrientationBuilder(
      builder: (context, orientation) {
        bool isLandscape = orientation == Orientation.landscape;

        return Scaffold(
          appBar: AppBar(
            title: Text('Phòng: ${_activeRoomId?.replaceAll("room_", "")}'),
            actions: [
              // Chỉ hiện nút hàng đợi danh sách khi màn hình dọc (Màn hình ngang đã hiện sẵn rồi)
              if (!isLandscape)
                IconButton(icon: const Icon(Icons.playlist_play, color: Colors.amber, size: 30), onPressed: _showQueueBottomSheet),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.redAccent),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Rời khỏi phòng?'),
                      content: const Text('Bạn có chắc muốn ngắt kết nối với thiết bị TV hiện tại không?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
                        TextButton(onPressed: () { Navigator.pop(context); _logoutAndClearPin(); }, child: const Text('Đồng ý')),
                      ],
                    ),
                  );
                },
              )
            ],
          ),
          body: isLandscape
              ? Row( // CHIA ĐÔI MÀN HÌNH KHI XOAY NGANG
            children: [
              // Bên trái: Vùng tìm kiếm và chọn bài (Chiếm 55% chiều ngang)
              Expanded(
                flex: 55,
                child: _buildSearchSection(),
              ),
              // Thanh chia dọc tinh tế giữa 2 phần màn hình
              VerticalDivider(color: Colors.grey.shade800, width: 1, thickness: 1),
              // Bên phải: Vùng hiển thị trực tiếp Hàng đợi đang chờ (Chiếm 45% chiều ngang)
              Expanded(
                flex: 45,
                child: Container(
                  color: Colors.grey.shade900,
                  child: _buildSideQueueSection(),
                ),
              ),
            ],
          )
              : _buildSearchSection(), // GIỮ NGUYÊN TOÀN MÀN HÌNH KHI XOAY DỌC
        );
      },
    );
  }

  // Khối giao diện Tìm kiếm và Kết quả (được tách ra để dùng chung cho cả dọc và ngang)
  Widget _buildSearchSection() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: _voiceHintText,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
                      color: _isListening ? Colors.red : Colors.amber,
                      onPressed: _listenToVoice,
                    ),
                  ),
                  onSubmitted: (value) => _searchSongFromYoutube(value),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.all(15)),
                onPressed: () => _searchSongFromYoutube(_searchController.text),
                child: const Icon(Icons.search),
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: _isKaraokeOnly,
                  activeColor: Colors.amber,
                  onChanged: (bool? value) {
                    setState(() {
                      _isKaraokeOnly = value ?? true;
                    });
                    if (_searchController.text.trim().isEmpty) {
                      _loadSuggestedSongs();
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              const Text('Chỉ tìm bài hát Karaoke', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const Spacer(),
              if (_searchController.text.trim().isEmpty && _searchResults.isNotEmpty)
                const Text('🔥 Gợi ý hôm nay', style: TextStyle(fontSize: 12, color: Colors.amber, fontStyle: FontStyle.italic)),
            ],
          ),
        ),
        const SizedBox(height: 5),

        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
            itemCount: _searchResults.length,
            itemBuilder: (context, index) {
              final song = _searchResults[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  leading: Image.network(song["thumbnail"]!, width: 70, height: 50, fit: BoxFit.cover, errorBuilder: (_,__,___)=> const Icon(Icons.music_video)),
                  title: Text(song["title"]!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  trailing: Wrap(
                    spacing: 6,
                    alignment: WrapAlignment.end,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade800,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          minimumSize: Size.zero,
                        ),
                        child: const Text('Chọn bài', style: TextStyle(color: Colors.white, fontSize: 11)),
                        onPressed: () {
                          FirebaseFirestore.instance.collection('secure_karaoke').doc(_activeRoomId).collection('queue').add({
                            'title': song["title"],
                            'youtube_id': song["id"],
                            'duration': song["duration"],
                            'timestamp': FieldValue.serverTimestamp(),
                            'priority': false,
                          });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã thêm: ${song["title"]}')));
                          }
                        },
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade700,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          minimumSize: Size.zero,
                        ),
                        child: const Text('Ưu tiên', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                       /* onPressed: () async {
                          dynamic targetTimestamp;

                          if (_currentQueueDocs.isNotEmpty) {
                            final firstDoc = _currentQueueDocs.first.data() as Map<String, dynamic>;
                            final Timestamp? firstTimestamp = firstDoc['timestamp'] as Timestamp?;

                            if (firstTimestamp != null) {
                              targetTimestamp = Timestamp(
                                firstTimestamp.seconds,
                                firstTimestamp.nanoseconds + 1000000,
                              );
                            } else {
                              targetTimestamp = FieldValue.serverTimestamp();
                            }
                          } else {
                            targetTimestamp = FieldValue.serverTimestamp();
                          }

                          await FirebaseFirestore.instance.collection('secure_karaoke').doc(_activeRoomId).collection('queue').add({
                            'title': song["title"],
                            'youtube_id': song["id"],
                            'duration': song["duration"],
                            'timestamp': targetTimestamp,
                            'priority': true,
                          });

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⭐ Đã ưu tiên bài: ${song["title"]} lên kế tiếp!')));
                          }
                        },*/
                        onPressed: () async {
                          dynamic targetTimestamp;

                          if (_currentQueueDocs.length >= 2) {
                            // Lấy dữ liệu của bài thứ 1 (đang phát) và bài thứ 2 trong hàng đợi
                            final firstDoc = _currentQueueDocs[0].data() as Map<String, dynamic>;
                            final secondDoc = _currentQueueDocs[1].data() as Map<String, dynamic>;

                            final Timestamp? firstTimestamp = firstDoc['timestamp'] as Timestamp?;
                            final Timestamp? secondTimestamp = secondDoc['timestamp'] as Timestamp?;

                            if (firstTimestamp != null && secondTimestamp != null) {
                              // Chuyển sang miligiây để tính toán chính xác
                              int firstMillis = firstTimestamp.millisecondsSinceEpoch;
                              int secondMillis = secondTimestamp.millisecondsSinceEpoch;

                              // Tính mốc thời gian nằm chính giữa bài thứ 1 và bài thứ 2
                              int midMillis = firstMillis + ((secondMillis - firstMillis) ~/ 2);

                              targetTimestamp = Timestamp.fromMillisecondsSinceEpoch(midMillis);
                            } else {
                              targetTimestamp = FieldValue.serverTimestamp();
                            }
                          } else if (_currentQueueDocs.length == 1) {
                            // Nếu chỉ có đúng 1 bài đang phát, bài ưu tiên tiếp theo chỉ cần muộn hơn 1 chút
                            final firstDoc = _currentQueueDocs[0].data() as Map<String, dynamic>;
                            final Timestamp? firstTimestamp = firstDoc['timestamp'] as Timestamp?;

                            if (firstTimestamp != null) {
                              // Cộng thêm 2-3 giây (2000-3000ms) để chắc chắn lớn hơn bài đang phát
                              targetTimestamp = Timestamp.fromMillisecondsSinceEpoch(
                                firstTimestamp.millisecondsSinceEpoch + 2000,
                              );
                            } else {
                              targetTimestamp = FieldValue.serverTimestamp();
                            }
                          } else {
                            // Hàng đợi trống rỗng
                            targetTimestamp = FieldValue.serverTimestamp();
                          }

                          // Tiến hành thêm vào Firestore
                          await FirebaseFirestore.instance
                              .collection('secure_karaoke')
                              .doc(_activeRoomId)
                              .collection('queue')
                              .add({
                            'title': song["title"],
                            'youtube_id': song["id"],
                            'duration': song["duration"],
                            'timestamp': targetTimestamp,
                            'priority': true,
                          });

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('⭐ Đã ưu tiên bài: ${song["title"]} lên kế tiếp!')),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Khối giao diện hiển thị danh sách bài hát bên phải khi màn hình xoay ngang
  Widget _buildSideQueueSection() {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.queue_music, color: Colors.amber, size: 20),
              SizedBox(width: 8),
              Text('HÀNG ĐỢI PHÁT (TV)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.amber, letterSpacing: 0.5)),
            ],
          ),
        ),
        Divider(color: Colors.grey.shade900, height: 1),
        Expanded(
          child: _currentQueueDocs.isEmpty
              ? const Center(child: Text('Chưa có bài hát nào trong hàng đợi', style: TextStyle(color: Colors.grey, fontSize: 13)))
              : ListView.builder(
            itemCount: _currentQueueDocs.length,
            itemBuilder: (context, index) {
              final data = _currentQueueDocs[index].data() as Map<String, dynamic>;
              final isPriority = data['priority'] == true;
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: isPriority ? Colors.amber : Colors.grey.shade800,
                  child: Text('${index + 1}', style: TextStyle(color: isPriority ? Colors.black : Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                title: Text(
                  data['title'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isPriority ? FontWeight.bold : FontWeight.normal,
                    color: isPriority ? Colors.amber : Colors.white,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
                  onPressed: () => FirebaseFirestore.instance.collection('secure_karaoke').doc(_activeRoomId).collection('queue').doc(_currentQueueDocs[index].id).delete(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Giữ nguyên BottomSheet khi người dùng dùng màn hình dọc
  void _showQueueBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      builder: (context) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('secure_karaoke').doc(_activeRoomId).collection('queue').orderBy('timestamp').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snapshot.data!.docs;
            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(15.0),
                  child: Text('DANH SÁCH BÀI ĐANG CHỜ PHÁT', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.amber)),
                ),
                Expanded(
                  child: docs.isEmpty
                      ? const Center(child: Text('Chưa chọn bài nào'))
                      : ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      final isPriority = data['priority'] == true;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isPriority ? Colors.amber : Colors.grey,
                          child: Text('${index + 1}', style: TextStyle(color: isPriority ? Colors.black : Colors.white)),
                        ),
                        title: Text(
                          data['title'] ?? '',
                          style: TextStyle(fontWeight: isPriority ? FontWeight.bold : FontWeight.normal, color: isPriority ? Colors.amber : Colors.white),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                          onPressed: () => FirebaseFirestore.instance.collection('secure_karaoke').doc(_activeRoomId).collection('queue').doc(docs[index].id).delete(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}