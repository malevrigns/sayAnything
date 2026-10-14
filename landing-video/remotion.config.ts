import { Config } from '@remotion/cli/config';

// Entry point so `remotion render HeroLoop out/...` works without repeating it.
Config.setEntryPoint('src/index.ts');

// OpenGL backend for headless Chromium. 'angle' is the default choice; if a
// machine cannot render with it, switch to 'swiftshader' (pure software) —
// or pass `--gl swiftshader` on the command line, which overrides this file.
Config.setChromiumOpenGlRenderer('angle');

// JPEG frames are much faster to capture/encode than PNG; the clip has no alpha.
Config.setVideoImageFormat('jpeg');

Config.setOverwriteOutput(true);
