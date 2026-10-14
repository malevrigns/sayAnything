import { Config } from '@remotion/cli/config';

Config.setEntryPoint('src/index.ts');

// Hardware OpenGL through ANGLE. If a machine cannot create a WebGL2 context
// with it, pass `--gl swiftshader` (software, much slower).
Config.setChromiumOpenGlRenderer('angle');

// Lossless PNG frames: the clip is mostly dark gradients, and JPEG frames
// would add blocking before H.264 compresses them again.
Config.setVideoImageFormat('png');

Config.setCodec('h264');
Config.setPixelFormat('yuv420p');
Config.setColorSpace('bt709');
Config.setCrf(20);
Config.setX264Preset('slow');
Config.setOverwriteOutput(true);
