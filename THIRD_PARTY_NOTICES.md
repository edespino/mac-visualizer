# Third-Party Notices

This file contains the full attribution and license texts for third-party
material that was ported into or adapted by mac-visualizer. See the NOTICE
file for credits covering projects that inspired (but did not contribute code
to) this app.

## Polartone (polar waveform technique)

- Original author: Matt DesLauriers
- License: MIT
- Source: https://github.com/mattdesl/Polartone
- Note: This project contains an independent Swift reimplementation of the
  polar waveform technique. No original code was copied, so no license
  obligation applies; attribution is provided as a courtesy.

## OctaveMeatballs (metaball octaves shader)

- Original author: Justas Dabrila
- License: Creative Commons Attribution 4.0 International (CC BY 4.0)
  https://creativecommons.org/licenses/by/4.0/
- Source: "Metaball octaves", https://www.shadertoy.com/view/WlXSzn
- Note: Ported to Metal Shading Language; modified for this app. Changes were
  made: GLSL translated to MSL; made audio-reactive; recoloured through the
  app palette; the derivative (fwidth) term replaced with an analytic radial
  approximation; octave count reduced for real-time performance.

## Star Nest (volumetric fractal starfield shader)

- Original author: Pablo Roman Andrioli
- License: MIT
- Copyright: Copyright (c) 2013 Pablo Roman Andrioli
- Source: "Star Nest", https://www.shadertoy.com/view/XlfGRj
- Note: Ported to Metal Shading Language and modified to be audio-reactive.

MIT License notice for Star Nest:

    Copyright (c) 2013 Pablo Roman Andrioli

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

## Outrun the Rain (procedural rain shader)

- Original author: Ian Reichert-Watts
- License: MIT
- Copyright: Copyright (c) 2018 Ian Reichert-Watts
- Source: https://github.com/AlexVestin/musicvid.org/blob/master/src/editor/animation/shaders/OutrunTheRain.js
- Note: Single-pass MSL reimplementation; changes were made.

MIT License notice for Outrun the Rain:

    Copyright (c) 2018 Ian Reichert-Watts

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
