import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter/foundation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ĐÃ SỬA: Gom gọn lại duy nhất 1 lần check, không gọi trùng lặp lệnh khởi tạo
  if (kIsWeb) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyBHQrH8Fb6lkvco3mFkl43eEdhUmvBxUb8",
        authDomain: "karaoke-app-7bdb6.firebaseapp.com",
        projectId: "karaoke-app-7bdb6",
        storageBucket: "karaoke-app-7bdb6.firebasestorage.app",
        messagingSenderId: "132139308690",
        appId: "1:132139308690:web:65209ea2900980b53a384b",
        measurementId: "G-0SZKLYJXM3",
      ),
    );
  } else {
    // Dành cho điện thoại Android / iOS thực tế
    await Firebase.initializeApp();
  }

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
    } else {
      setState(() { _isCheckingMemory = false; });
    }
  }

  // Hàm kết nối linh hoạt độ dài mã (Do không chèn thêm số 0)
  void _unlockAndSaveRemote() async {
    String input = _pinInputController.text.trim().toUpperCase();

    if (input.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_master_pin', input);

      setState(() {
        _activeRoomId = 'room_$input';
        _isLocked = false;
      });
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

  Future<void> _searchSongFromYoutube(String keyword) async {
    if (keyword.trim().isEmpty) return;
    setState(() { _isLoading = true; _searchResults.clear(); });

    try {
      final ytClient = yt.YoutubeExplode();
      final searchList = await ytClient.search.getVideos('$keyword karaoke');
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

    return Scaffold(
      appBar: AppBar(
        title: Text('Phòng: ${_activeRoomId?.replaceAll("room_", "")}'),
        actions: [
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
      body: Column(
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
                    leading: Image.network(song["thumbnail"]!, width: 70, fit: BoxFit.cover, errorBuilder: (_,__,___)=> const Icon(Icons.music_video)),
                    title: Text(song["title"]!, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Chọn bài'),
                      onPressed: () {
                        FirebaseFirestore.instance.collection('secure_karaoke').doc(_activeRoomId).collection('queue').add({
                          'title': song["title"],
                          'youtube_id': song["id"],
                          'duration': song["duration"],
                          'timestamp': FieldValue.serverTimestamp(),
                        });
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã thêm: ${song["title"]}')));
                        }
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

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
                      return ListTile(
                        leading: CircleAvatar(child: Text('${index + 1}')),
                        title: Text(data['title'] ?? ''),
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