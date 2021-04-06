import 'dart:convert';
import 'dart:io';

import 'package:caracal_steg/dwt_codec.dart';
import 'package:caracal_steg/hadamard_codec.dart';
import 'package:caracal_steg/repetition_codecs.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image_lib;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(MyApp());
}

class StaticData {
  static Map<String, Widget Function(BuildContext)> routeMap = {
    'Encoding': (context) => EncodePage(title: 'Encoding'),
    'Decoding': (context) => DecodePage(title: 'Decoding')
  };

  static List<String> tabIndexToRoute = ['Encoding', 'Decoding'];

  static void handleEncodeRequest(List<dynamic> input) async {
    String imagePath = input[0];
    int imageQuality = input[1];
    String message = input[2];
    String tempFilePath = input[3];
    var inputImage = image_lib.decodeImage(File(imagePath).readAsBytesSync())!;
    if (inputImage.width % 8 != 0 || inputImage.height % 8 != 0) {
      var shrunkWidth = inputImage.width - inputImage.width % 8;
      var shrunkHeight = inputImage.height - inputImage.height % 8;
      inputImage = image_lib.copyResize(inputImage,
          width: shrunkWidth, height: shrunkHeight);
    }
    var messageLength = message.length;
    var repetitions = (inputImage.length * 3) ~/ (messageLength * 256 * 64);
    var coder = DWTStegnanography.withECC(
        inputImage,
        ValuePluralityRepetitionCorrection(
            HadamardErrorCorrection(), repetitions));

    image_lib.Image newImage = coder.encodeMessage(message);
    File(tempFilePath)
        .writeAsBytesSync(image_lib.encodeJpg(newImage, quality: imageQuality));
  }

  static String handleDecodeRequest(List<dynamic> input) {
    String imagePath = input[0];
    int messageLength = input[1];
    var inputImage = image_lib.decodeImage(File(imagePath).readAsBytesSync())!;
    var repetitions = (inputImage.length * 3) ~/ (messageLength * 256 * 64);
    var coder = DWTStegnanography.withECC(
        inputImage,
        ValuePluralityRepetitionCorrection(HadamardErrorCorrection(), repetitions,
                (value) {
              return ((value >= 32) && (value <= 126));
            }));
    return coder.decodeMessage(messageLength);
    //BitMajorityRepetitionCorrection(HadamardErrorCorrection(), repetitions),);
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Caracal Steg',
      theme: ThemeData(primarySwatch: Colors.green),
      routes: StaticData.routeMap,
      initialRoute: 'Encoding',
    );
  }
}

class EncodePage extends StatefulWidget {
  EncodePage({Key? key, this.title}) : super(key: key);
  final String? title;

  @override
  _EncodePageState createState() => _EncodePageState();
}

class _EncodePageState extends State<EncodePage> {
  String? imagePath;
  int imageQuality = 95;
  int selectedTab = 0;
  String message = '';

  void _selectImage() async {
    ImagePicker picker = ImagePicker();
    PickedFile? pickedFile = await picker.getImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        imagePath = pickedFile.path;
      });
    }
  }

  void _selectTab(int newSelectedTab) {
    setState(() => selectedTab = newSelectedTab);
    Navigator.popAndPushNamed(context, StaticData.tabIndexToRoute[newSelectedTab]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(widget.title!),
        ),
        bottomNavigationBar: BottomNavigationBar(items: [
          BottomNavigationBarItem(icon: Icon(Icons.lock), label: 'Encode'),
          BottomNavigationBarItem(icon: Icon(Icons.lock_open), label: 'Decode')
        ], onTap: _selectTab, currentIndex: selectedTab),
        body: SafeArea(
            child: Container(
          margin: const EdgeInsets.only(left: 8.0, right: 8.0),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                SizedBox(height: 8),
                imagePath == null
                    ? Expanded(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                            OutlinedButton(
                                onPressed: _selectImage,
                                child: Text('Select an image'))
                          ]))
                    : Expanded(
                        child: GestureDetector(
                            onTap: _selectImage,
                            child: Image.file(File(imagePath!)))),
                SizedBox(height: 8),
                TextField(
                  decoration: InputDecoration(
                      border: OutlineInputBorder(), labelText: 'Message'),
                  inputFormatters: [
                    TextInputFormatter.withFunction(
                      (oldValue, newValue) {
                        AsciiCodec codec = AsciiCodec(allowInvalid: true);
                        var newString = newValue.text;
                        var bytes = codec.encode(newString);
                        if (bytes.any((byte) => byte < 32 || byte > 126))
                          return oldValue;
                        else
                          return newValue;
                      },
                    )
                  ],
                  onChanged: (value) => setState(() {
                    message = value;
                  }),
                ),
                SizedBox(height: 8),
                InputDecorator(
                    decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'JPEG Quality'),
                    child: Row(children: [
                      Expanded(
                          child: Slider(
                              value: imageQuality.toDouble(),
                              onChanged: (value) => setState(() {
                                    imageQuality = value.round();
                                  }),
                              divisions: 101,
                              min: 0,
                              max: 100,
                              label: imageQuality.round().toString())),
                      Text(imageQuality.toString())
                    ])),
                ElevatedButton(
                    onPressed: () async {
                      var tempFilePath = path.join(
                          (await getTemporaryDirectory()).path,
                          '${DateTime.now().millisecondsSinceEpoch}.jpg');
                      var tempFile = File(tempFilePath);
                      if (tempFile.existsSync()) tempFile.delete();
                      await compute(StaticData.handleEncodeRequest,
                          [imagePath, imageQuality, message, tempFilePath]);
                      await showDialog(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                                title: Text('Result Image'),
                                content: Column(children: [
                                  Expanded(
                                      child: Image(
                                          image: FileImage(tempFile)..evict())),
                                  SizedBox(height: 8),
                                  Text(
                                      'Message was ${message.length} characters')
                                ]),
                                actions: [
                                  TextButton(
                                      onPressed: () {
                                        tempFile.delete();
                                        Navigator.of(context).pop();
                                      },
                                      child: Text('Discard')),
                                  TextButton(
                                      onPressed: () {
                                        var albumDirectory = Directory(
                                            '/storage/emulated/0/Pictures/CaracalSteg');
                                        albumDirectory.create(recursive: true);
                                        tempFile.copy(path.join(
                                            albumDirectory.path,
                                            path.basename(tempFilePath)));
                                        tempFile.delete();
                                        Navigator.of(context).pop();
                                      },
                                      child: Text('Save'))
                                ]);
                          });
                    },
                    child: Text('Encode')),
                ElevatedButton(
                    onPressed: () => setState(() => imagePath = null),
                    child: Text('Clear'))
              ]),
        )));
  }
}

class DecodePage extends StatefulWidget {
  DecodePage({Key? key, this.title}) : super(key: key);
  final String? title;

  @override
  _DecodePageState createState() => _DecodePageState();
}

class _DecodePageState extends State<DecodePage> {
  String? imagePath;
  int selectedTab = 1;
  int messageLength = 0;

  void _selectImage() async {
    ImagePicker picker = ImagePicker();
    PickedFile? pickedFile = await picker.getImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        imagePath = pickedFile.path;
      });
    }
  }

  void _selectTab(int newSelectedTab) {
    setState(() => selectedTab = newSelectedTab);
    Navigator.popAndPushNamed(context, StaticData.tabIndexToRoute[newSelectedTab]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(widget.title!),
        ),
        bottomNavigationBar: BottomNavigationBar(items: [
          BottomNavigationBarItem(icon: Icon(Icons.lock), label: 'Encode'),
          BottomNavigationBarItem(icon: Icon(Icons.lock_open), label: 'Decode')
        ], onTap: _selectTab, currentIndex: selectedTab),
        body: SafeArea(
            child: Container(
          margin: const EdgeInsets.only(left: 8.0, right: 8.0),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                SizedBox(height: 8),
                imagePath == null
                    ? Expanded(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                            OutlinedButton(
                                onPressed: _selectImage,
                                child: Text('Select an image'))
                          ]))
                    : Expanded(
                        child: GestureDetector(
                            onTap: _selectImage,
                            child: Image.file(File(imagePath!)))),
                SizedBox(height: 8),
                TextField(
                  decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Message Length'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'\d'))
                  ],
                  onChanged: (value) =>
                      setState(() => messageLength = int.parse(value)),
                ),
                SizedBox(height: 8),
                ElevatedButton(
                    onPressed: () async {
                      var message = await compute(
                          StaticData.handleDecodeRequest, [imagePath, messageLength]);
                      await showDialog(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                                title: Text('Result'),
                                content: Text(message),
                                actions: [
                                  TextButton(
                                      onPressed: () {
                                        Clipboard.setData(
                                            ClipboardData(text: message));
                                        Navigator.of(context).pop();
                                      },
                                      child: Text('Copy')),
                                  TextButton(
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                      },
                                      child: Text('Okay'))
                                ]);
                          });
                    },
                    child: Text('Decode')),
                ElevatedButton(
                    onPressed: () => setState(() => imagePath = null),
                    child: Text('Clear'))
              ]),
        )));
  }
}
