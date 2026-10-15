"use client";

import { useEffect, useRef } from "react";

/**
 * The holographic finish on the chip's die, drawn by a fragment shader.
 *
 * The CSS version of this was a white band on a timer sliding over a fixed
 * rainbow, and it read as exactly that. Foil does not slide: the colour at a
 * point changes because the angle you see it from changes, so the bands have
 * to bend and separate rather than travel. That is a per-pixel calculation,
 * which is what a shader is for.
 *
 * WebGL1, no dependencies, one triangle. The canvas is around a hundred
 * pixels square, so the cost is the context, not the pixels.
 */
const VERTEX = `
attribute vec2 a_position;
void main() {
  gl_Position = vec4(a_position, 0.0, 1.0);
}
`;

const FRAGMENT = `
precision mediump float;
uniform vec2 u_resolution;
uniform float u_time;

// Hue to RGB, the usual six-segment version.
vec3 hue(float h) {
  vec3 k = mod(vec3(5.0, 3.0, 1.0) + h * 6.0, 6.0);
  return clamp(min(k, 4.0 - k), 0.0, 1.0);
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  // Origin off the top-left corner, because the light everywhere else on
  // this page comes from up there.
  vec2 p = uv - vec2(-0.05, 1.08);
  float t = u_time * 0.1;
  float d = length(p * vec2(1.0, 0.95));

  // The diffraction. Few, wide bands, bent by a slow wave: a dense rainbow
  // is a screensaver, and the mark has to stay readable on top of this.
  float warp = 0.05 * sin(uv.x * 2.6 + t * 1.2) + 0.04 * cos(uv.y * 3.1 - t * 0.9);
  float bands = d * 0.85 + warp + t * 0.22;
  vec3 foil = hue(fract(bands)) * 0.7 + hue(fract(bands * 1.3 + 0.45)) * 0.3;

  // Pulled towards its own luminance, then laid over a near-black substrate
  // that keeps most of it. Full-strength hues read as plastic.
  float lum = dot(foil, vec3(0.299, 0.587, 0.114));
  foil = mix(vec3(lum), foil, 0.62);
  float sheen = smoothstep(1.8, 0.1, d);
  vec3 colour = mix(vec3(0.045, 0.045, 0.06), foil, 0.18 + 0.4 * sheen);

  // The highlight, raked across the grain and soft at both edges: a hard
  // edge is the thing that reads as a rectangle sliding over a picture.
  float sweep = fract(t * 0.38);
  float along = uv.x * 0.7 + uv.y * 0.7;
  float streak = smoothstep(0.26, 0.0, abs(along - (sweep * 2.2 - 0.6)));
  colour += pow(streak, 1.9) * 0.55;

  // Corner falloff, then a fine grain so the flat areas are not perfect.
  colour *= 0.92 + 0.22 * (1.0 - uv.x * 0.5 - (1.0 - uv.y) * 0.5);
  float grain = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453);
  colour += (grain - 0.5) * 0.03;

  gl_FragColor = vec4(colour, 1.0);
}
`;

export function HoloFoil({ className = "" }: { className?: string }) {
  const ref = useRef<HTMLCanvasElement | null>(null);

  useEffect(() => {
    const canvas = ref.current;
    if (!canvas) return;

    const gl = canvas.getContext("webgl", { antialias: false, alpha: false });
    // No context means the CSS foil underneath stays visible, which is why
    // this element is transparent until it has something to draw.
    if (!gl) return;

    const compile = (type: number, source: string) => {
      const shader = gl.createShader(type);
      if (!shader) return null;
      gl.shaderSource(shader, source);
      gl.compileShader(shader);
      return shader;
    };

    const program = gl.createProgram();
    const vertex = compile(gl.VERTEX_SHADER, VERTEX);
    const fragment = compile(gl.FRAGMENT_SHADER, FRAGMENT);
    if (!program || !vertex || !fragment) return;
    gl.attachShader(program, vertex);
    gl.attachShader(program, fragment);
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) return;
    gl.useProgram(program);

    // One triangle that covers the clip space, rather than two for a quad:
    // fewer vertices and no seam down the diagonal.
    const buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    const position = gl.getAttribLocation(program, "a_position");
    gl.enableVertexAttribArray(position);
    gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);

    const resolution = gl.getUniformLocation(program, "u_resolution");
    const time = gl.getUniformLocation(program, "u_time");

    const resize = () => {
      // Capped at 2: the die is small and a 3x buffer is three times the
      // fragments for a difference nobody can see at this size.
      const ratio = Math.min(window.devicePixelRatio || 1, 2);
      const width = Math.max(1, Math.round(canvas.clientWidth * ratio));
      const height = Math.max(1, Math.round(canvas.clientHeight * ratio));
      if (canvas.width === width && canvas.height === height) return;
      canvas.width = width;
      canvas.height = height;
      gl.viewport(0, 0, width, height);
      gl.uniform2f(resolution, width, height);
    };

    canvas.style.opacity = "1";

    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
    let frame = 0;
    let visible = true;
    const start = performance.now();

    const draw = (now: number) => {
      resize();
      // Frozen rather than blank under Reduce Motion: the foil is what the
      // die looks like, the movement is the part that is optional.
      gl.uniform1f(time, reduced.matches ? 6 : (now - start) / 1000);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      frame = reduced.matches || !visible ? 0 : requestAnimationFrame(draw);
    };

    // Once, synchronously. `requestAnimationFrame` never fires in a hidden
    // tab, so without this the die is blank in every screenshot taken of a
    // background window and on the first paint after a restore.
    draw(performance.now());
    if (frame === 0 && !reduced.matches) frame = requestAnimationFrame(draw);

    // Off-screen it stops entirely. This sits near the bottom of a long page
    // and has no business holding a frame loop open while nobody is there.
    const observer = new IntersectionObserver(([entry]) => {
      visible = entry?.isIntersecting ?? false;
      if (visible && frame === 0) frame = requestAnimationFrame(draw);
    });
    observer.observe(canvas);

    return () => {
      observer.disconnect();
      if (frame !== 0) cancelAnimationFrame(frame);
      gl.deleteProgram(program);
      gl.deleteShader(vertex);
      gl.deleteShader(fragment);
      gl.deleteBuffer(buffer);
    };
  }, []);

  return (
    <canvas
      ref={ref}
      aria-hidden
      className={`absolute inset-0 h-full w-full opacity-0 transition-opacity duration-500 ${className}`}
    />
  );
}
