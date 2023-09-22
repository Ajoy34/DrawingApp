import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: DrawingPage(),
    );
  }
}

class DrawingPage extends StatefulWidget {
  @override
  _DrawingPageState createState() => _DrawingPageState();
}

class _DrawingPageState extends State<DrawingPage> {
  Color selectedColor = Colors.black;
  Color backgroundColor = Colors.white;
  double strokeWidth = 5.0;
  List<Offset> erasedStrokes = [];
  List<Offset> drawingStrokes = [];
  bool isErasing = false;
  Uint8List? _imageData;
  List<Uint8List> _savedImages = [];
  String albumName = 'MyDrawingAlbum'; // Change the album name here

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Drawing App'),
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.format_color_text),
            onPressed: () {
              _pickColor(context, false);
            },
          ),
          IconButton(
            icon: Icon(Icons.format_color_fill),
            onPressed: () {
              _pickColor(context, true);
            },
          ),
          _buildClearButton(),
          IconButton(
            icon: Icon(Icons.camera_alt),
            onPressed: () async {
              await _takeScreenshot(context);
            },
          ),
        ],
      ),
      body: Center(
        child: RepaintBoundary(
          key: _globalKey,
          child: DrawingCanvas(
            selectedColor: selectedColor,
            backgroundColor: backgroundColor,
            strokeWidth: strokeWidth,
            erasedStrokes: erasedStrokes,
            drawingStrokes: drawingStrokes,
            isErasing: isErasing,
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomAppBar(),
    );
  }

  final GlobalKey _globalKey = GlobalKey();

  void _pickColor(BuildContext context, bool isPickingBackgroundColor) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(isPickingBackgroundColor ? 'Pick Background Color' : 'Pick Color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: isPickingBackgroundColor ? backgroundColor : selectedColor,
              onColorChanged: (color) {
                setState(() {
                  if (isPickingBackgroundColor) {
                    backgroundColor = color;
                  } else {
                    selectedColor = color;
                  }
                });
              },
              showLabel: true,
              pickerAreaHeightPercent: 0.8,
            ),
          ),
          actions: <Widget>[
            ElevatedButton(
              child: Text('Select'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _takeScreenshot(BuildContext context) async {
    setState(() {
      erasedStrokes.clear();
      drawingStrokes.clear();
    });

    RenderRepaintBoundary boundary =
        _globalKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ImageByteFormat.png);
    _imageData = byteData!.buffer.asUint8List();

    // Save the image to the gallery with a specific album name (Android only)
    await _saveImage(context, albumName);
  }

  Future<void> _saveImage(BuildContext context, String albumName) async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();

      final folderDir = Directory('${appDocDir.path}/$albumName');
      await folderDir.create(recursive: true);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '$timestamp.png';

      final filePath = '${folderDir.path}/$fileName';

      await File(filePath).writeAsBytes(_imageData!);

      // Save the image to the gallery
      final result = await ImageGallerySaver.saveFile(filePath);
      print(result);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Image saved to gallery in album: $albumName'),
      ));

      // Keep track of saved images
      _savedImages.add(_imageData!);
    } catch (e) {
      print('Error saving image: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to save image'),
      ));
    }
  }

  Widget _buildBottomAppBar() {
    return BottomAppBar(
      color: Colors.blue,
      child: Row(
        children: <Widget>[
          IconButton(
            icon: Icon(Icons.remove),
            onPressed: () {
              setState(() {
                strokeWidth = strokeWidth > 1.0 ? strokeWidth - 1.0 : strokeWidth;
              });
            },
          ),
          Text('Stroke Width'),
          IconButton(
            icon: Icon(Icons.add),
            onPressed: () {
              setState(() {
                strokeWidth += 1.0;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildClearButton() {
    return IconButton(
      icon: Icon(Icons.clear),
      onPressed: () {
        setState(() {
          erasedStrokes.clear();
          drawingStrokes.clear();
        });
      },
    );
  }
}

class DrawingCanvas extends StatefulWidget {
  final Color selectedColor;
  final Color backgroundColor;
  final double strokeWidth;
  final List<Offset> erasedStrokes;
  final List<Offset> drawingStrokes;
  final bool isErasing;

  DrawingCanvas({
    required this.selectedColor,
    required this.backgroundColor,
    required this.strokeWidth,
    required this.erasedStrokes,
    required this.drawingStrokes,
    required this.isErasing,
  });

  @override
  _DrawingCanvasState createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  Offset? lastPoint;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) {
        RenderBox renderBox = context.findRenderObject() as RenderBox;
        Offset localPosition = renderBox.globalToLocal(details.globalPosition);
        if (lastPoint != null) {
          setState(() {
            if (!widget.isErasing) {
              widget.drawingStrokes.add(lastPoint!);
              widget.drawingStrokes.add(localPosition);
            } else {
              widget.erasedStrokes.add(localPosition);
            }
            lastPoint = localPosition;
          });
        } else {
          lastPoint = localPosition;
        }
      },
      onPanEnd: (details) {
        if (widget.isErasing) {
          widget.erasedStrokes.add(Offset(-1, -1));
        }
        setState(() {
          lastPoint = null;
        });
      },
      child: CustomPaint(
        size: Size.infinite,
        painter: MyPainter(
          drawingStrokes: widget.drawingStrokes,
          color: widget.isErasing ? widget.backgroundColor : widget.selectedColor,
          backgroundColor: widget.backgroundColor,
          strokeWidth: widget.strokeWidth,
          erasedStrokes: widget.erasedStrokes,
        ),
      ),
    );
  }
}

class MyPainter extends CustomPainter {
  final List<Offset> drawingStrokes;
  final Color color;
  final Color backgroundColor;
  final double strokeWidth;
  final List<Offset> erasedStrokes;

  MyPainter({
    required this.drawingStrokes,
    required this.color,
    required this.backgroundColor,
    required this.strokeWidth,
    required this.erasedStrokes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromPoints(Offset.zero, size.bottomRight(Offset.zero)),
        Paint()..color = backgroundColor);

    final Paint paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    for (int i = 0; i < drawingStrokes.length - 1; i += 2) {
      if (drawingStrokes[i] != Offset(-1, -1) && drawingStrokes[i + 1] != Offset(-1, -1)) {
        canvas.drawLine(drawingStrokes[i], drawingStrokes[i + 1], paint);
      }
    }

    final Paint erasePaint = Paint()
      ..color = backgroundColor
      ..blendMode = BlendMode.clear
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    for (int i = 0; i < erasedStrokes.length - 1; i += 2) {
      if (erasedStrokes[i] != Offset(-1, -1) && erasedStrokes[i + 1] != Offset(-1, -1)) {
        canvas.drawLine(erasedStrokes[i], erasedStrokes[i + 1], erasePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
