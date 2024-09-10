import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'dart:async';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Upload Video in Chunks',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: UploadPage(),
    );
  }
}

class UploadPage extends StatefulWidget {
  @override
  _UploadPageState createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  String? _uploadUrl; // L'URL présignée pour l'upload
  File? _file; // Le fichier sélectionné
  bool _isUploading = false;
  double _progress = 0.0;

  // Fonction pour obtenir l'URL présignée depuis votre API Django
  Future<void> _getPresignedUrl() async {
    final url =
        'https://api.dev.minfo.com/api/apputils/upload_file_test'; // Remplacez par votre API
    final response = await http.post(Uri.parse(url), body: {
      'filename': 'video.mp4',
      'folder': 'test_video',
      'type': 'video/mp4'
    });

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      print("lien de téléchargement ${data["public_url"]}");
      setState(() {
        _uploadUrl = data["pre_signed_url"];
      });
    } else {
      throw Exception('Failed to get presigned URL');
    }
  }

  // Fonction pour sélectionner le fichier vidéo avec file_picker
  Future<void> _selectFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);

    if (result != null) {
      setState(() {
        _file = File(result.files.single.path!);
      });
    }
  }

  // Fonction pour uploader le fichier par morceaux
  Future<void> _uploadFileInChunks() async {
    if (_file == null || _uploadUrl == null) return;

    setState(() {
      _isUploading = true;
      _progress = 0.0;
    });

    final totalSize = _file!.lengthSync();
    const int chunkSize = 50 * 1024 * 1024; // 50 Mo
    const int minChunkSize = 300 * 1024; // 300 Ko
    final int totalChunks = (totalSize / chunkSize).ceil();

    final file = _file!;
    int startByte = 0;
    int chunkIndex = 0;

    // Cas 1 : Fichier de moins de 50 Mo, envoyer en une seule partie
    if (totalSize <= chunkSize) {
      final chunk = await file.openRead(0, totalSize).toList();
      final byteChunk = chunk.expand((element) => element).toList();
      final contentRange = 'bytes 0-${totalSize - 1}/$totalSize';

      final response = await http.put(
        Uri.parse(_uploadUrl!),
        headers: {
          'Content-Range': contentRange,
          'Content-Type': 'video/mp4',
        },
        body: byteChunk,
      );

      if (response.statusCode == 200 || response.statusCode == 308) {
        setState(() {
          _progress = 1.0;
          _isUploading = false;
        });
      } else {
        print(
            "Error uploading the file: ${response.statusCode} - ${response.body}");
        setState(() {
          _isUploading = false;
        });
      }
      return;
    }

    // Cas 2 : Fichier de plus de 50 Mo
    while (startByte < totalSize) {
      final endByte = (startByte + chunkSize < totalSize)
          ? startByte + chunkSize - 1
          : totalSize - 1;
      final chunk = await file.openRead(startByte, endByte + 1).toList();
      final byteChunk = chunk.expand((element) => element).toList();

      // Si nous sommes dans les deux derniers morceaux
      final isLastChunk = endByte >= totalSize - 1;
      final remainingSize = totalSize - endByte - 1;

      if (remainingSize > 0 && remainingSize < chunkSize && isLastChunk) {
        // Calculer les tailles des deux dernières parties
        final lastTwoPartsSize = endByte - startByte + 1 + remainingSize;
        final partSize = lastTwoPartsSize ~/ 2;

        // Lire et envoyer la première des deux dernières parties
        final firstPart =
            await file.openRead(startByte, startByte + partSize).toList();
        final byteFirstPart = firstPart.expand((element) => element).toList();
        final contentRangeFirst =
            'bytes $startByte-${startByte + partSize - 1}/$totalSize';

        final responseFirst = await http.put(
          Uri.parse(_uploadUrl!),
          headers: {
            'Content-Range': contentRangeFirst,
            'Content-Type': 'video/mp4',
          },
          body: byteFirstPart,
        );

        if (responseFirst.statusCode != 200 &&
            responseFirst.statusCode != 308) {
          print(
              "Error uploading first half of last chunks: ${responseFirst.statusCode} - ${responseFirst.body}");
          return;
        }

        // Lire et envoyer la deuxième partie
        final secondPart =
            await file.openRead(startByte + partSize, totalSize).toList();
        final byteSecondPart = secondPart.expand((element) => element).toList();
        final contentRangeSecond =
            'bytes ${startByte + partSize}-${totalSize - 1}/$totalSize';

        final responseSecond = await http.put(
          Uri.parse(_uploadUrl!),
          headers: {
            'Content-Range': contentRangeSecond,
            'Content-Type': 'video/mp4',
          },
          body: byteSecondPart,
        );

        if (responseSecond.statusCode != 200 &&
            responseSecond.statusCode != 308) {
          print(
              "Error uploading second half of last chunks: ${responseSecond.statusCode} - ${responseSecond.body}");
          return;
        }

        // Sortir après avoir envoyé les deux derniers morceaux
        setState(() {
          _progress = 1.0;
          _isUploading = false;
        });
        return;
      }

      // Envoyer les morceaux normaux
      final contentRange = 'bytes $startByte-$endByte/$totalSize';
      final response = await http.put(
        Uri.parse(_uploadUrl!),
        headers: {
          'Content-Range': contentRange,
          'Content-Type': 'video/mp4',
        },
        body: byteChunk,
      );

      if (response.statusCode == 200 || response.statusCode == 308) {
        setState(() {
          _progress = (chunkIndex + 1) / totalChunks;
        });
        chunkIndex++;
        startByte += chunkSize;
      } else {
        print(
            "Error uploading chunk: ${response.statusCode} - ${response.body}");
        setState(() {
          _isUploading = false;
        });
        return;
      }
    }

    setState(() {
      _isUploading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Upload Video in Chunks'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _selectFile,
              child: Text('Select Video File'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _getPresignedUrl,
              child: Text('Get Presigned URL'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _uploadFileInChunks,
              child: _isUploading ? Text('Uploading...') : Text('Upload Video'),
            ),
            SizedBox(height: 20),
            LinearProgressIndicator(value: _progress),
            if (_file != null) Text('Selected file: ${_file!.path}'),
          ],
        ),
      ),
    );
  }
}
