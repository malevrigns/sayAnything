import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

ImageProvider<Object> localImageProvider(XFile file) =>
    FileImage(File(file.path));

VideoPlayerController localVideoController(XFile file) =>
    VideoPlayerController.file(File(file.path));
