"use client";

import { useEffect, useRef } from "react";
import * as THREE from "three";
import { RoomEnvironment } from "three/examples/jsm/environments/RoomEnvironment.js";
import { RoundedBoxGeometry } from "three/examples/jsm/geometries/RoundedBoxGeometry.js";
import { meter, SCENARIOS, type Scenario } from "@/lib/scenarios";
import { FACE, PALETTE, SUN, type Sprite } from "@/lib/sprites";

// The hero: a little MacBook starts a long job (a coding agent, an export, a
// render, a download: lib/scenarios.ts), the lid closes, the job keeps going
// (the floating HUD and the glow at the hinge say so), the lid opens on a
// finished job. One scenario per loop, Claude Code first. One loop, in seconds:
const LOOP = 10;
const TOAST_AT = 0.45; // the switch flips: "MAC STAYS AWAKE"
const TYPE = [0.3, 0.85] as const; // the command, typed
const RUN = [0.9, 6.3] as const; // the job, 0 to 100%
const CLOSE = [2.5, 3.35] as const;
const OPEN = [6.9, 7.85] as const;
const STILL = 5.2; // the frame shown when motion is reduced: lid shut, Claude Code running
const OPEN_ANGLE = 1.92; // about 110 degrees
const FOV = 24;

// The laptop, in scene units.
const W = 3.2;
const D = 2.2;
const BASE = 0.12;
const LID = 0.065;

const clamp = (x: number, lo = 0, hi = 1) => Math.min(hi, Math.max(lo, x));
const easeInOut = (x: number) => (x < 0.5 ? 4 * x * x * x : 1 - (-2 * x + 2) ** 3 / 2);
const easeOutBack = (x: number) => 1 + 2.2 * (x - 1) ** 3 + 1.2 * (x - 1) ** 2;
const crossed = (from: number, to: number, mark: number) =>
  from <= to ? from < mark && mark <= to : from < mark || mark <= to;

type ScreenState = { scenario: Scenario; step: "ready" | "run" | "done"; typed: number; p: number };

export default function MacScene({ onToast }: { onToast: () => void }) {
  const host = useRef<HTMLDivElement>(null);
  const glow = useRef<HTMLDivElement>(null);
  const hud = useRef<HTMLDivElement>(null);
  const fill = useRef<HTMLDivElement>(null);
  const percent = useRef<HTMLSpanElement>(null);
  const label = useRef<HTMLSpanElement>(null);
  const caption = useRef<HTMLDivElement>(null);
  const toast = useRef(onToast);

  useEffect(() => {
    toast.current = onToast;
  }, [onToast]);

  useEffect(() => {
    const container = host.current;
    if (!container) return;
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    let renderer: THREE.WebGLRenderer;
    try {
      renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, powerPreference: "low-power" });
    } catch {
      return; // No WebGL: the page reads fine without the laptop.
    }
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    renderer.setClearColor(0x000000, 0);
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.toneMapping = THREE.NeutralToneMapping;
    const canvas = renderer.domElement;
    canvas.className = "absolute inset-0 h-full w-full";
    canvas.setAttribute("aria-hidden", "true");
    container.prepend(canvas);

    const scene = new THREE.Scene();
    const pmrem = new THREE.PMREMGenerator(renderer);
    const room = new RoomEnvironment();
    const environment = pmrem.fromScene(room, 0.04).texture;
    room.dispose();
    pmrem.dispose();
    scene.environment = environment;

    // Framed a little low, so the toast and the HUD float above the laptop.
    const camera = new THREE.PerspectiveCamera(FOV, 1, 0.5, 40);
    camera.position.set(0, 3.5, 9.6);
    camera.lookAt(0, 1, 0);

    const key = new THREE.DirectionalLight(0xffffff, 1.6);
    key.position.set(3, 6, 5);
    scene.add(key, new THREE.AmbientLight(0xffffff, 0.35));

    const font = getComputedStyle(document.documentElement).getPropertyValue("--font-silkscreen").trim() || "monospace";

    // Materials and textures.
    const aluminium = new THREE.MeshStandardMaterial({ color: 0xd3d6de, metalness: 0.55, roughness: 0.34 });
    const keysCanvas = drawKeyboard();
    const keysTexture = texture(keysCanvas);
    const keys = new THREE.MeshStandardMaterial({ map: keysTexture, roughness: 0.75, metalness: 0.1 });
    const pad = new THREE.MeshStandardMaterial({ color: 0xc4c7cf, metalness: 0.45, roughness: 0.42 });
    const hinge = new THREE.MeshStandardMaterial({ color: 0x3b3742, metalness: 0.4, roughness: 0.5 });
    const bezel = new THREE.MeshBasicMaterial({ color: 0x0b090e });
    const screenCanvas = document.createElement("canvas");
    screenCanvas.width = 640;
    screenCanvas.height = 400;
    const screenTexture = texture(screenCanvas);
    const screen = new THREE.MeshBasicMaterial({ map: screenTexture, toneMapped: false });
    const emblemTexture = texture(spriteCanvas(SUN, "#ff7ad9"), true);
    const emblem = new THREE.MeshBasicMaterial({ map: emblemTexture, transparent: true, toneMapped: false, depthWrite: false });
    const glowTexture = texture(radialCanvas("255,122,217"));
    const hingeGlow = new THREE.SpriteMaterial({ map: glowTexture, transparent: true, depthWrite: false, toneMapped: false });
    const shadowTexture = texture(radialCanvas("26,11,23"));
    const shadow = new THREE.MeshBasicMaterial({ map: shadowTexture, transparent: true, depthWrite: false, opacity: 0.28 });

    // The laptop. The base sits on y = 0; the lid turns around the back edge.
    const laptop = new THREE.Group();
    scene.add(laptop);
    const body = new THREE.Group();
    laptop.add(body);

    const base = new THREE.Mesh(new RoundedBoxGeometry(W, BASE, D, 4, 0.05), aluminium);
    base.position.y = BASE / 2;
    body.add(base);

    const keyboard = new THREE.Mesh(roundedPlane(W * 0.82, D * 0.42, 0.05), keys);
    keyboard.rotation.x = -Math.PI / 2;
    keyboard.position.set(0, BASE + 0.002, -D * 0.13);
    body.add(keyboard);

    const trackpad = new THREE.Mesh(roundedPlane(W * 0.34, D * 0.3, 0.05), pad);
    trackpad.rotation.x = -Math.PI / 2;
    trackpad.position.set(0, BASE + 0.002, D * 0.29);
    body.add(trackpad);

    const barrel = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.06, W * 0.78, 16), hinge);
    barrel.rotation.z = Math.PI / 2;
    barrel.position.set(0, BASE + 0.01, -D / 2 + 0.02);
    body.add(barrel);

    const lidPivot = new THREE.Group();
    lidPivot.position.set(0, BASE + 0.012, -D / 2);
    body.add(lidPivot);

    const lid = new THREE.Mesh(new RoundedBoxGeometry(W, LID, D, 4, 0.03), aluminium);
    lid.position.set(0, LID / 2, D / 2);
    lidPivot.add(lid);

    const bezelPlane = new THREE.Mesh(roundedPlane(W - 0.08, D - 0.08, 0.06), bezel);
    bezelPlane.rotation.x = Math.PI / 2;
    bezelPlane.position.set(0, -0.004, D / 2);
    lidPivot.add(bezelPlane);

    const screenPlane = new THREE.Mesh(new THREE.PlaneGeometry(W - 0.34, (W - 0.34) * 0.625), screen);
    screenPlane.rotation.x = Math.PI / 2;
    screenPlane.position.set(0, -0.008, D / 2 + 0.04);
    lidPivot.add(screenPlane);

    // A pixel sun on the back of the lid: it breathes while the lid is shut.
    const emblemPlane = new THREE.Mesh(new THREE.PlaneGeometry(0.62, 0.62), emblem);
    emblemPlane.rotation.x = -Math.PI / 2;
    emblemPlane.position.set(0, LID + 0.004, D / 2);
    lidPivot.add(emblemPlane);

    const glowSprite = new THREE.Sprite(hingeGlow);
    glowSprite.position.set(0, BASE + 0.1, -D / 2 - 0.05);
    glowSprite.scale.set(W * 1.1, 0.8, 1);
    body.add(glowSprite);

    const floor = new THREE.Mesh(new THREE.PlaneGeometry(W * 1.3, D * 1.35), shadow);
    floor.rotation.x = -Math.PI / 2;
    floor.position.y = -0.002;
    laptop.add(floor);

    laptop.rotation.y = -0.38;

    // The screen, redrawn only when what it shows changes.
    let shown = "";
    function drawScreen(state: ScreenState) {
      const id = `${state.scenario.id}:${state.step}:${state.typed}:${meter(state.scenario, state.p)}`;
      if (id === shown) return;
      shown = id;
      paintScreen(screenCanvas, state, font);
      screenTexture.needsUpdate = true;
    }
    void document.fonts?.load(`24px ${font}`).then(() => {
      shown = "";
      if (!running) render(clock);
    });

    // The HUD floating over the shut laptop.
    let hudShown = false;
    let hudText = "";
    function setHud(visible: boolean, p: number, { id, hud: words }: Scenario) {
      const root = hud.current;
      if (!root) return;
      if (visible !== hudShown) {
        hudShown = visible;
        root.dataset.show = visible ? "true" : "false";
      }
      const pct = Math.round(p * 100);
      const text = `${id}:${pct}`;
      if (text === hudText) return;
      hudText = text;
      if (percent.current) percent.current.replaceChildren(...cells(`${pct}%`).map(cellNode));
      if (fill.current) fill.current.style.width = `${Math.floor(p * 10) * 10}%`;
      if (label.current) label.current.textContent = pct >= 100 ? words.done : words.title;
      if (caption.current) caption.current.textContent = words.caption;
    }

    function resize() {
      const width = container!.clientWidth;
      const height = container!.clientHeight;
      if (!width || !height) return;
      renderer.setSize(width, height, false);
      camera.aspect = width / height;
      // Keep the whole laptop in frame on narrow screens.
      camera.fov = camera.aspect < 1.05 ? FOV * (1.05 / camera.aspect) ** 0.85 : FOV;
      camera.updateProjectionMatrix();
    }

    let clock = reduced ? STILL : 0;
    let previous = clock;

    function render(time: number) {
      const t = time % LOOP;
      const scenario = SCENARIOS[Math.floor(time / LOOP) % SCENARIOS.length];

      let angle = OPEN_ANGLE;
      if (t >= CLOSE[0] && t < CLOSE[1]) angle = OPEN_ANGLE * (1 - easeInOut((t - CLOSE[0]) / (CLOSE[1] - CLOSE[0])));
      else if (t >= CLOSE[1] && t < OPEN[0]) angle = 0;
      else if (t >= OPEN[0] && t < OPEN[1]) angle = OPEN_ANGLE * easeOutBack((t - OPEN[0]) / (OPEN[1] - OPEN[0]));
      lidPivot.rotation.x = -angle;
      const shut = 1 - clamp(angle / 0.6);

      // A small bump when the lid lands, then a gentle float.
      const land = t >= CLOSE[1] && t < CLOSE[1] + 0.3 ? Math.sin(((t - CLOSE[1]) / 0.3) * Math.PI) : 0;
      body.scale.set(1 + land * 0.012, 1 - land * 0.05, 1 + land * 0.012);
      laptop.position.y = reduced ? 0 : Math.sin(time * 1.4) * 0.04;
      laptop.rotation.y = -0.38 + (reduced ? 0 : Math.sin(time * 0.45) * 0.06);

      const breath = 0.62 + 0.38 * Math.sin(time * 2.6);
      hingeGlow.opacity = shut * breath * 0.9;
      emblem.opacity = 0.35 + shut * breath * 0.65;
      if (glow.current) glow.current.style.opacity = `${0.25 + shut * breath * 0.75}`;

      const p = clamp((t - RUN[0]) / (RUN[1] - RUN[0]));
      const typed = Math.floor(clamp((t - TYPE[0]) / (TYPE[1] - TYPE[0])) * scenario.command.length);
      drawScreen({ scenario, step: t < RUN[0] ? "ready" : t < OPEN[0] ? "run" : "done", typed, p });
      // The HUD leaves just before the lid lifts, so it never covers the screen.
      setHud(t >= CLOSE[1] - 0.05 && t < OPEN[0] - 0.12, p, scenario);

      renderer.render(scene, camera);
    }

    // Runs only while the hero is on screen and the tab is visible.
    let running = false;
    let frame = 0;
    let last = 0;
    let visible = false;
    function tick(now: number) {
      const dt = last ? Math.min((now - last) / 1000, 0.1) : 0;
      last = now;
      previous = clock;
      clock += dt;
      if (crossed(previous % LOOP, clock % LOOP, TOAST_AT)) toast.current();
      render(clock);
      frame = requestAnimationFrame(tick);
    }
    function update() {
      const should = visible && !document.hidden && !reduced;
      if (should === running) return;
      running = should;
      if (running) {
        last = 0;
        frame = requestAnimationFrame(tick);
      } else {
        cancelAnimationFrame(frame);
      }
    }

    const sizes = new ResizeObserver(() => {
      resize();
      if (!running) render(clock);
    });
    sizes.observe(container);
    const seen = new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
      update();
    });
    seen.observe(container);
    document.addEventListener("visibilitychange", update);
    resize();
    render(clock);

    return () => {
      running = false;
      cancelAnimationFrame(frame);
      sizes.disconnect();
      seen.disconnect();
      document.removeEventListener("visibilitychange", update);
      scene.traverse((object) => {
        if (object instanceof THREE.Mesh || object instanceof THREE.Sprite) object.geometry.dispose();
      });
      for (const material of [aluminium, keys, pad, hinge, bezel, screen, emblem, hingeGlow, shadow]) material.dispose();
      for (const map of [keysTexture, screenTexture, emblemTexture, glowTexture, shadowTexture, environment]) map.dispose();
      renderer.dispose();
      canvas.remove();
    };
  }, []);

  return (
    <div ref={host} className="absolute inset-0">
      <div
        ref={glow}
        aria-hidden="true"
        className="pointer-events-none absolute left-1/2 top-[46%] h-[46%] w-[78%] -translate-x-1/2 rounded-full bg-[radial-gradient(closest-side,rgba(255,122,217,0.55),rgba(111,211,255,0.18)_60%,transparent)] opacity-25 blur-xl"
      />
      <div
        ref={hud}
        data-show="false"
        aria-hidden="true"
        className="hud pointer-events-none absolute left-1/2 top-[21%] flex w-58 -translate-x-1/2 flex-col gap-3 rounded-2xl bg-pill p-4 text-white ring-[0.5px] ring-white/15"
      >
        <div className="flex items-center justify-between font-pixel text-pixel pixel-even">
          <span ref={label}>{SCENARIOS[0].hud.title}</span>
          <span ref={percent}>
            {cells("0%").map(({ char, digit }, i) => (
              <span key={i} className={digit ? "pixel-digit" : undefined}>
                {char}
              </span>
            ))}
          </span>
        </div>
        <div className="pixel-bar h-3 w-full">
          <div ref={fill} className="pixel-bar-fill h-full w-0" />
        </div>
        <div ref={caption} className="text-micro font-bold text-white/60">
          {SCENARIOS[0].hud.caption}
        </div>
      </div>
    </div>
  );
}

// Silkscreen has no tabular figures: its "1" is a pixel narrower than the
// other digits. Counters give every digit the same cell, so they never jitter.
function cells(text: string) {
  return [...text].map((char) => ({ char, digit: /\d/.test(char) }));
}

function cellNode({ char, digit }: { char: string; digit: boolean }) {
  const node = document.createElement("span");
  node.textContent = char;
  if (digit) node.className = "pixel-digit";
  return node;
}

function texture(canvas: HTMLCanvasElement, pixelated = false) {
  const map = new THREE.CanvasTexture(canvas);
  map.colorSpace = THREE.SRGBColorSpace;
  map.anisotropy = 4;
  if (pixelated) {
    map.magFilter = THREE.NearestFilter;
    map.minFilter = THREE.NearestFilter;
    map.generateMipmaps = false;
  }
  return map;
}

// A flat rounded rectangle facing +z, with UVs spanning 0 to 1.
function roundedPlane(width: number, height: number, radius: number) {
  const x = -width / 2;
  const y = -height / 2;
  const shape = new THREE.Shape();
  shape.moveTo(x + radius, y);
  shape.lineTo(x + width - radius, y);
  shape.quadraticCurveTo(x + width, y, x + width, y + radius);
  shape.lineTo(x + width, y + height - radius);
  shape.quadraticCurveTo(x + width, y + height, x + width - radius, y + height);
  shape.lineTo(x + radius, y + height);
  shape.quadraticCurveTo(x, y + height, x, y + height - radius);
  shape.lineTo(x, y + radius);
  shape.quadraticCurveTo(x, y, x + radius, y);
  const geometry = new THREE.ShapeGeometry(shape, 6);
  const position = geometry.attributes.position;
  const uv = geometry.attributes.uv;
  for (let i = 0; i < position.count; i++) {
    uv.setXY(i, (position.getX(i) - x) / width, (position.getY(i) - y) / height);
  }
  return geometry;
}

function drawKeyboard() {
  const canvas = document.createElement("canvas");
  canvas.width = 512;
  canvas.height = 256;
  const g = canvas.getContext("2d")!;
  g.fillStyle = "#2c2932";
  g.fillRect(0, 0, 512, 256);
  g.fillStyle = "#47434f";
  const rows = 6;
  const pad = 10;
  const gap = 6;
  const h = (256 - pad * 2 - gap * (rows - 1)) / rows;
  for (let r = 0; r < rows; r++) {
    const y = pad + r * (h + gap);
    if (r === rows - 1) {
      // The bottom row: small keys around a long space bar.
      const small = 42;
      let x = pad;
      for (let i = 0; i < 3; i++, x += small + gap) roundRect(g, x, y, small, h, 5);
      roundRect(g, x, y, 512 - pad * 2 - (small + gap) * 6, h, 5);
      x = 512 - pad - small;
      for (let i = 0; i < 3; i++, x -= small + gap) roundRect(g, x, y, small, h, 5);
      continue;
    }
    const count = 13;
    const w = (512 - pad * 2 - gap * (count - 1)) / count;
    for (let i = 0; i < count; i++) roundRect(g, pad + i * (w + gap), y, w, r === 0 ? h * 0.7 : h, 5);
  }
  return canvas;
}

function roundRect(g: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  g.beginPath();
  g.roundRect(x, y, w, h, r);
  g.fill();
}

function radialCanvas(rgb: string) {
  const canvas = document.createElement("canvas");
  canvas.width = 256;
  canvas.height = 256;
  const g = canvas.getContext("2d")!;
  const gradient = g.createRadialGradient(128, 128, 0, 128, 128, 128);
  gradient.addColorStop(0, `rgba(${rgb},1)`);
  gradient.addColorStop(0.45, `rgba(${rgb},0.45)`);
  gradient.addColorStop(1, `rgba(${rgb},0)`);
  g.fillStyle = gradient;
  g.fillRect(0, 0, 256, 256);
  return canvas;
}

function spriteCanvas(rows: Sprite, color: string, cell = 4, margin = 0) {
  const canvas = document.createElement("canvas");
  canvas.width = rows[0].length * cell + margin * 2;
  canvas.height = rows.length * cell + margin * 2;
  drawSprite(canvas.getContext("2d")!, rows, color, margin, margin, cell);
  return canvas;
}

// "#" pixels in `color`, the others in their own (butter, pink).
function drawSprite(g: CanvasRenderingContext2D, rows: Sprite, color: string, left: number, top: number, cell: number) {
  rows.forEach((row, y) => {
    for (let x = 0; x < row.length; x++) {
      if (row[x] === ".") continue;
      g.fillStyle = row[x] === "#" ? color : PALETTE[row[x]];
      g.fillRect(left + x * cell, top + y * cell, cell, cell);
    }
  });
}

function paintScreen(canvas: HTMLCanvasElement, { scenario, step, typed, p }: ScreenState, font: string) {
  const g = canvas.getContext("2d")!;
  const { width, height } = canvas;
  const background = g.createLinearGradient(0, 0, 0, height);
  background.addColorStop(0, "#1d1024");
  background.addColorStop(1, "#0f0a14");
  g.fillStyle = background;
  g.fillRect(0, 0, width, height);

  // Window dots, in candy.
  ["#ff7ad9", "#ffd36e", "#6fd3ff"].forEach((color, i) => {
    g.fillStyle = color;
    g.beginPath();
    g.arc(34 + i * 26, 30, 8, 0, Math.PI * 2);
    g.fill();
  });

  g.textBaseline = "alphabetic";
  // One line of Silkscreen at 24 px, shrunk only if a scenario's text would run
  // off the screen. Drawn a letter at a time, tracked like the page (one font
  // pixel, 3 px, off each letter), and every digit gets the same 5/8 em cell,
  // like the HUD's: the counters tick without jittering.
  const text = (words: string, x: number, y: number, color: string, room = width - 32 - x) => {
    const letters = cells(words.toUpperCase());
    g.font = `24px ${font}`;
    const advances = letters.map(({ char, digit }) => (digit ? 18 : g.measureText(char).width) - 3);
    const wide = advances.reduce((a, b) => a + b, 0);
    const size = wide > room ? Math.floor((24 * room) / wide) : 24;
    g.font = `${size}px ${font}`;
    g.fillStyle = color;
    let left = x;
    letters.forEach(({ char }, i) => {
      g.fillText(char, left, y);
      left += (advances[i] * size) / 24;
    });
  };
  const line = (words: string, y: number, color: string) => text(words, 32, y, color);
  line("$ wham on", 96, "#ffffff");
  line("on: your Mac stays awake", 132, "#ff7ad9");
  if (step === "ready") {
    line(`$ ${scenario.command.slice(0, typed)}_`, 186, "#ffffff");
    return;
  }
  line(`$ ${scenario.command}`, 186, "#ffffff");

  // A chunky progress bar, ten blocks, and the job's own counter beside it.
  const blocks = 10;
  const lit = Math.floor(p * blocks);
  const bw = 24;
  const gap = 6;
  const candy = g.createLinearGradient(32, 0, 32 + blocks * (bw + gap), 0);
  candy.addColorStop(0, "#ff7ad9");
  candy.addColorStop(0.5, "#ffd36e");
  candy.addColorStop(1, "#6fd3ff");
  for (let i = 0; i < blocks; i++) {
    g.fillStyle = i < lit ? candy : "rgba(255,255,255,0.12)";
    g.fillRect(32 + i * (bw + gap), 210, bw, 24);
  }
  text(meter(scenario, step === "done" ? 1 : p), 32 + blocks * (bw + gap) + 12, 233, "#ffffff");

  if (step === "done") {
    line(scenario.done, 290, "#ffd36e");
    // The app's icon, as on the Dock: the sun's ink would vanish on the dark screen.
    const tile = 75;
    const left = width - 32 - tile;
    const top = height - 32 - tile;
    const candy = g.createLinearGradient(left, top, left + tile, top + tile);
    candy.addColorStop(0, "#ff7ad9");
    candy.addColorStop(0.5, "#ffd36e");
    candy.addColorStop(1, "#6fd3ff");
    g.fillStyle = candy;
    g.beginPath();
    g.roundRect(left, top, tile, tile, 17);
    g.fill();
    drawSprite(g, FACE, "#1a0b17", left + 6, top + 6, 3);
  }
}
