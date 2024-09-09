import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

const UPLOAD_CHUNK_SIZE = 1; // 1 MB chunk size
bool _isUploading = false;

class UploadTest extends StatefulWidget {
  @override
  _UploadTestState createState() => _UploadTestState();
}

class _UploadTestState extends State<UploadTest> {
  String _fileName = '';
  String _uploadStatus = '';
  File? _file;

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      setState(() {
        _fileName = result.files.single.name;
        _file = File(result.files.single.path!);
      });
    }
  }

  Future<void> _getUploadUrlAndUpload() async {
    if (_fileName.isEmpty || _file == null) {
      setState(() {
        _uploadStatus = 'Veuillez sélectionner un fichier d\'abord.';
      });
      return;
    }

    final url =
        Uri.parse('https://api.dev.minfo.com/api/apputils/upload_file_test');
    final response = await http.post(
      url,
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(<String, String>{
        'filename': _fileName,
        'folder': 'test_folder',
        'type': 'video/mp4',
      }),
    );

    if (response.statusCode == 200) {
      final responseData = jsonDecode(response.body);
      final String resumableUrl = responseData['pre_signed_url'];

      try {
        await uploadFileInChunks(resumableUrl, _file!.path);
        setState(() {
          _uploadStatus = 'Fichier uploadé avec succès.\n'
              'URL publique: ${responseData['public_url']}';
        });
      } catch (e) {
        setState(() {
          _uploadStatus = 'Erreur lors de l\'upload: $e';
        });
      }
    } else {
      setState(() {
        _uploadStatus =
            'Erreur lors de l\'obtention de l\'URL: ${response.statusCode}\n${response.body}';
      });
    }
  }

  Future<void> uploadFileInChunks(String presignedUrl, String filePath) async {
    if (_isUploading) return;
    _isUploading = true;

    final file = File(filePath);
    final chunkSize = UPLOAD_CHUNK_SIZE * 1024 * 1024; // 1 MB chunk size
    final totalSize = file.lengthSync();
    final numberOfChunks = (totalSize / chunkSize).ceil();
    int currentChunk = 0;

    for (int i = 0; i < numberOfChunks; i++) {
      final start = i == 0 ? 0 : i * chunkSize + 1;
      final end = start + chunkSize > totalSize ? totalSize : start + chunkSize;
      var chunk = file.openRead(start, end);
      HttpClient httpClient = HttpClient();
      final request = httpClient.putUrl(Uri.parse(presignedUrl));
      await request.asStream();
      var res = await http.put(
        Uri.parse(presignedUrl),
        headers: {
          'Content-Range': "bytes $start-$end/$totalSize",
          // 'X-UPD-Session': hiveTasks.downloadSessionIds[currentLocalfileIndex]
        },
        body: chunk,
      );
      print("Response data ${res.statusCode}-- ${res.body}");

/*
      final formData = FormData.fromMap({
        'file': MultipartFile.fromStream(() => chunk, end - start,
            filename: '$i\_${filePath.split("/").last}'),
        'post_id': '123', // Replace with your actual post ID
        'chunk_number': currentChunk,
      });

      try {
        final response = await Dio().post(
          presignedUrl,
          data: formData,
          options: Options(
            headers: {
              'Content-Range': "bytes $start-$end/$totalSize",
              // 'X-UPD-Session': hiveTasks.downloadSessionIds[currentLocalfileIndex]
            },
          ),
          onSendProgress: (int chunkSent, int chunkTotal) {
            final chunkProgress =
                ((chunkSent / chunkSize) * 100) / numberOfChunks;
            final overallProgress =
                ((i * chunkSize + chunkSent) / totalSize) * 100;
            print(
                'Chunk progress: $chunkProgress%, Overall progress: $overallProgress%');
          },
        );

        if (response.statusCode.toString().startsWith('2')) {
          currentChunk++;
          if (currentChunk == numberOfChunks) {
            print('File uploaded successfully!');
            _isUploading = false;
          }
        } else {
          print(
              'Failed to upload chunk: ${response.statusCode} - ${response.data}');
          _isUploading = false;
        }
      } on DioException catch (e) {
        _isUploading = false;
        if (e.response != null) {
          print(
              'Error uploading chunk: ${e.response?.statusCode} - ${e.response?.data}');
          rethrow;
        } else {
          print('Error with Dio: ${e.message}');
          rethrow;
        }
       
      } */
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Test Upload API'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ElevatedButton(
              onPressed: _pickFile,
              child: Text('Sélectionner un fichier'),
            ),
            SizedBox(height: 16),
            Text('Fichier sélectionné: $_fileName'),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _getUploadUrlAndUpload,
              child: Text('Uploader le fichier'),
            ),
            SizedBox(height: 16),
            Text('Statut: $_uploadStatus'),
          ],
        ),
      ),
    );
  }
}
