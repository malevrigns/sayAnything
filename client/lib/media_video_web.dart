import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

ImageProvider<Object> localImageProvider(XFile file) => NetworkImage(file.path);

VideoPlayerController localVideoController(XFile file) =>
    VideoPlayerController.networkUrl(Uri.parse(file.path));
