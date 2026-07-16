import 'package:flutter/material.dart';
import 'image_receiver.dart';

class EncryptProgressDialog extends StatefulWidget {
  final String imagePath;
  final String publicKeyPath;

  EncryptProgressDialog({required this.imagePath, required this.publicKeyPath});

  @override
  _EncryptProgressDialogState createState() => _EncryptProgressDialogState();
}

class _EncryptProgressDialogState extends State<EncryptProgressDialog> {
  double progress = 0.0;

  @override
  void initState() {
    super.initState();

    ImageReceiver.receiveImage(widget.imagePath, widget.publicKeyPath, (p) {
      setState(() {
        progress = p;
      });
    }).then((resultPath) {
      Navigator.pop(context); // أغلق الـ Dialog
      if (resultPath != null) {
      } else {
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Encrypting Image"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: progress),
          SizedBox(height: 10),
          Text("${(progress*100).toStringAsFixed(0)}%"),
        ],
      ),
    );
  }
}