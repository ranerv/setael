import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";

const canvas = document.querySelector("#flower-canvas");
const sceneElement = document.querySelector("#scene");
const loading = document.querySelector("#loading");
const webglError = document.querySelector("#webgl-error");
const replayButton = document.querySelector("#replay-button");
const messageWidget = document.querySelector("#message-widget");
const folderToggle = document.querySelector("#folder-toggle");
const messageCard = document.querySelector("#message-card");
const messageClose = document.querySelector("#message-close");
const customMessage = document.querySelector("#custom-message");

const duration = 14;
const messageDelay = 900;
const parts = [];
const flowerAnimations = [];
const clock = new THREE.Clock();
let elapsed = 0;
let playing = true;
let messageRevealTimer;
let messageCloseTimer;

const clamp01 = (value) => THREE.MathUtils.clamp(value, 0, 1);
const ease = (value) => {
  const t = clamp01(value);
  return t * t * (3 - 2 * t);
};
const smooth = (start, end, value) => ease((value - start) / Math.max(0.001, end - start));

fetch("./message/custom-message.txt", { cache: "no-store" })
  .then((response) => {
    if (!response.ok) throw new Error(`Message file returned HTTP ${response.status}`);
    return response.text();
  })
  .then((message) => {
    customMessage.textContent = message.trim() || "Add your custom message to message/custom-message.txt.";
  })
  .catch((error) => {
    customMessage.textContent = "Add your custom message to message/custom-message.txt.";
    console.error("Could not load the custom message:", error);
  });

const scene = new THREE.Scene();
scene.background = new THREE.Color("#090d0a");
scene.fog = new THREE.FogExp2("#090d0a", 0.035);

const camera = new THREE.PerspectiveCamera(42, 1, 0.1, 100);
camera.position.set(0, 0.72, 5.85);

let renderer;
try {
  renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: "high-performance" });
} catch (error) {
  loading.hidden = true;
  webglError.hidden = false;
  console.error("Could not initialize the lily WebGL renderer:", error);
  throw error;
}
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
renderer.setSize(sceneElement.clientWidth, sceneElement.clientHeight, false);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.15;

const controls = new OrbitControls(camera, canvas);
controls.target.set(0, 0.3, 0.15);
controls.enableDamping = true;
controls.dampingFactor = 0.055;
controls.minDistance = 2.4;
controls.maxDistance = 8;
controls.minPolarAngle = 0.12;
controls.maxPolarAngle = Math.PI - 0.12;
controls.autoRotate = true;
controls.autoRotateSpeed = 0.7;
controls.update();

scene.add(new THREE.HemisphereLight("#e6edce", "#273323", 1.65));
scene.add(new THREE.AmbientLight("#829078", 0.38));
const keyLight = new THREE.DirectionalLight("#fff1d2", 3.2);
keyLight.position.set(3.2, 5, 4);
scene.add(keyLight);
const rimLight = new THREE.DirectionalLight("#92c8a4", 2);
rimLight.position.set(-4, 1.5, -3);
scene.add(rimLight);
const fillLight = new THREE.PointLight("#ed95cf", 18, 8, 2);
fillLight.position.set(-1.3, 1.4, 3.3);
scene.add(fillLight);

function cubicPoint(points, t) {
  const oneMinusT = 1 - t;
  return points[0].clone().multiplyScalar(oneMinusT ** 3)
    .addScaledVector(points[1], 3 * oneMinusT ** 2 * t)
    .addScaledVector(points[2], 3 * oneMinusT * t ** 2)
    .addScaledVector(points[3], t ** 3);
}

function cubicTangent(points, t) {
  const oneMinusT = 1 - t;
  return points[1].clone().sub(points[0]).multiplyScalar(3 * oneMinusT ** 2)
    .addScaledVector(points[2].clone().sub(points[1]), 6 * oneMinusT * t)
    .addScaledVector(points[3].clone().sub(points[2]), 3 * t ** 2)
    .normalize();
}

function gridGeometry(rows, columns, pointAt, colorAt) {
  const positions = [];
  const colors = [];
  const uvs = [];
  const indices = [];

  for (let row = 0; row <= rows; row += 1) {
    const u = row / rows;
    for (let column = 0; column <= columns; column += 1) {
      const v = column / columns;
      const point = pointAt(u, v);
      const color = colorAt(u, v);
      positions.push(point.x, point.y, point.z);
      colors.push(color.r, color.g, color.b);
      uvs.push(u, v);
    }
  }

  for (let row = 0; row < rows; row += 1) {
    for (let column = 0; column < columns; column += 1) {
      const a = row * (columns + 1) + column;
      const b = a + columns + 1;
      const c = b + 1;
      const d = a + 1;
      indices.push(a, b, c, a, c, d);
    }
  }

  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
  geometry.setAttribute("color", new THREE.Float32BufferAttribute(colors, 3));
  geometry.setAttribute("uv", new THREE.Float32BufferAttribute(uvs, 2));
  geometry.setIndex(indices);
  geometry.computeVertexNormals();
  return geometry;
}

function makePetalGeometry(isInner) {
  const maxWidth = isInner ? 0.42 : 0.34;
  const spine = [
    new THREE.Vector3(0, 0, 0),
    new THREE.Vector3(0.18, 0.45, 0),
    new THREE.Vector3(0.55, 0.78, 0),
    new THREE.Vector3(0.88, 0.5, 0),
  ];
  const throat = new THREE.Color("#c6d995");
  const magenta = new THREE.Color("#e62d72");
  const white = new THREE.Color("#fff3f6");
  const frames = [];
  const rows = 30;
  const columns = 18;

  for (let row = 0; row <= rows; row += 1) {
    const u = row / rows;
    const tangent = cubicTangent(spine, u);
    const reference = Math.abs(tangent.x) > 0.94
      ? new THREE.Vector3(0, 0, 1)
      : new THREE.Vector3(1, 0, 0);
    const side = tangent.clone().cross(reference).normalize();
    const normal = tangent.clone().cross(side).normalize();
    frames.push({ point: cubicPoint(spine, u), side, normal });
  }

  return gridGeometry(
    rows,
    columns,
    (u, v) => {
      const frame = frames[Math.round(u * rows)];
      const across = v * 2 - 1;
      const width = maxWidth * Math.max(0, Math.sin((u ** 0.75) * Math.PI)) * (1 - 0.22 * u);
      const furrow = 0.18 * across ** 2 * maxWidth * (1 - 0.4 * u);
      const wave = 0.04 * (u ** 1.2) * (1 - u * 0.3) * Math.sin(u * 18) * Math.abs(across) ** 1.5;
      return frame.point.clone()
        .addScaledVector(frame.side, across * width)
        .addScaledVector(frame.normal, furrow + wave);
    },
    (u, v) => {
      const across = Math.abs(v * 2 - 1);
      const throatFade = smooth(0, 0.25, u);
      const magentaBand = Math.exp(-((across * 2.4) ** 2))
        * smooth(0.08, 0.32, u)
        * (1 - smooth(0.78, 1, u));
      const color = throat.clone().lerp(white, throatFade);
      color.lerp(magenta, magentaBand * 0.92);
      return color;
    },
  );
}

function makeLeafGeometry(length, maxWidth) {
  const spine = [
    new THREE.Vector3(0, 0, 0),
    new THREE.Vector3(0.35 * length, 0.12 * length, 0),
    new THREE.Vector3(0.75 * length, 0.05 * length, 0),
    new THREE.Vector3(length, -0.22 * length, 0),
  ];
  const inner = new THREE.Color("#34843d");
  const edge = new THREE.Color("#65a94e");
  const columns = 12;

  return gridGeometry(
    28,
    columns,
    (u, v) => {
      const across = v * 2 - 1;
      const point = cubicPoint(spine, u);
      const tangent = cubicTangent(spine, u);
      const width = maxWidth * Math.max(0, Math.sin(u * Math.PI)) ** 0.7 * (1 - 0.25 * u);
      const normal = tangent.clone().cross(new THREE.Vector3(0, 0, 1)).normalize();
      return point
        .add(new THREE.Vector3(0, 0, across * width))
        .addScaledVector(normal, 0.25 * across ** 2 * maxWidth * (1 - u));
    },
    (_u, v) => inner.clone().lerp(edge, Math.abs(v * 2 - 1) * 0.3),
  );
}

function taperedTube(curve, startRadius, endRadius, colorStart, colorEnd, segments = 48, sides = 10) {
  const frames = curve.computeFrenetFrames(segments, false);
  const positions = [];
  const colors = [];
  const indices = [];
  const from = new THREE.Color(colorStart);
  const to = new THREE.Color(colorEnd);

  for (let row = 0; row <= segments; row += 1) {
    const u = row / segments;
    const point = curve.getPointAt(u);
    const radius = THREE.MathUtils.lerp(startRadius, endRadius, u);
    const color = from.clone().lerp(to, u);
    for (let column = 0; column <= sides; column += 1) {
      const angle = (column / sides) * Math.PI * 2;
      const normal = frames.normals[row].clone().multiplyScalar(Math.cos(angle))
        .addScaledVector(frames.binormals[row], Math.sin(angle));
      const vertex = point.clone().addScaledVector(normal, radius);
      positions.push(vertex.x, vertex.y, vertex.z);
      colors.push(color.r, color.g, color.b);
    }
  }

  for (let row = 0; row < segments; row += 1) {
    for (let column = 0; column < sides; column += 1) {
      const a = row * (sides + 1) + column;
      const b = a + sides + 1;
      indices.push(a, b, a + 1, b, b + 1, a + 1);
    }
  }

  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
  geometry.setAttribute("color", new THREE.Float32BufferAttribute(colors, 3));
  geometry.setIndex(indices);
  geometry.computeVertexNormals();
  return geometry;
}

function addPart(parent, geometry, timing, options = {}) {
  const growGroup = new THREE.Group();
  parent.add(growGroup);

  const hasVertexColors = Boolean(geometry.getAttribute("color"));
  const material = new THREE.MeshPhysicalMaterial({
    color: options.color || "#ffffff",
    vertexColors: hasVertexColors,
    roughness: options.roughness ?? 0.48,
    metalness: 0.01,
    clearcoat: options.clearcoat ?? 0.16,
    side: THREE.DoubleSide,
    transparent: true,
    opacity: 0,
    depthWrite: false,
  });
  const mesh = new THREE.Mesh(geometry, material);
  mesh.castShadow = false;
  mesh.receiveShadow = false;
  growGroup.add(mesh);

  const wireMaterial = new THREE.LineBasicMaterial({
    color: options.wireColor || "#ff9be8",
    transparent: true,
    opacity: 0,
    depthWrite: false,
  });
  const wire = new THREE.LineSegments(new THREE.WireframeGeometry(geometry), wireMaterial);
  wire.renderOrder = 2;
  growGroup.add(wire);

  const part = {
    growGroup,
    mesh,
    wire,
    timing,
    baseScale: new THREE.Vector3(1, 1, 1),
  };
  parts.push(part);
  return part;
}

const plant = new THREE.Group();
scene.add(plant);

const stemCurve = new THREE.CubicBezierCurve3(
  new THREE.Vector3(0, -1.8, 0),
  new THREE.Vector3(0.04, -0.6, 0.02),
  new THREE.Vector3(-0.05, 0.6, -0.03),
  new THREE.Vector3(0.02, 1.6, 0),
);
addPart(
  plant,
  taperedTube(stemCurve, 0.055, 0.032, "#356a32", "#5d9c48"),
  { wireStart: 0, wireEnd: 2.8, surfaceStart: 1, surfaceEnd: 3.5 },
  { wireColor: "#7ef59b", roughness: 0.68 },
);

const leafConfigs = [
  [-1.4, 20, 0.75, 0.16, 0.4],
  [-1.1, 150, 0.82, 0.17, 0.7],
  [-0.8, 270, 0.88, 0.18, 1.0],
  [-0.5, 60, 0.85, 0.17, 1.3],
  [-0.2, 190, 0.8, 0.16, 1.6],
  [0.1, 310, 0.76, 0.15, 1.9],
  [0.4, 90, 0.7, 0.14, 2.2],
  [0.7, 220, 0.65, 0.13, 2.5],
  [1, 340, 0.58, 0.12, 2.8],
];
const leafAxis = new THREE.Vector3(1, 0, 0);

leafConfigs.forEach(([height, angle, length, width, start], index) => {
  const radians = THREE.MathUtils.degToRad(angle);
  const direction = new THREE.Vector3(Math.cos(radians), 0.35, Math.sin(radians)).normalize();
  const leaf = new THREE.Group();
  leaf.position.set(0.04 * Math.cos(radians), height, 0.04 * Math.sin(radians));
  leaf.quaternion.setFromUnitVectors(leafAxis, direction);
  plant.add(leaf);

  const part = addPart(
    leaf,
    makeLeafGeometry(length, width),
    { wireStart: start, wireEnd: start + 1.6, surfaceStart: start + 0.8, surfaceEnd: start + 2.2 },
    { wireColor: "#7ef59b", roughness: 0.66 },
  );
  part.sway = { phase: index * 0.9, amount: 0.025 };
});

function axisRotation(axis, degrees) {
  return new THREE.Quaternion().setFromAxisAngle(
    new THREE.Vector3(...axis).normalize(),
    THREE.MathUtils.degToRad(degrees),
  );
}

function addFlower(spec) {
  const flower = new THREE.Group();
  flower.position.set(...spec.center);
  flower.quaternion.copy(axisRotation(spec.axis, spec.tilt)).multiply(axisRotation([1, 0, 0], spec.roll));
  plant.add(flower);
  flowerAnimations.push({ group: flower, spec });

  for (let index = 0; index < 6; index += 1) {
    const start = spec.wireStart + index * 0.08;
    const petalRoot = new THREE.Group();
    flower.add(petalRoot);
    const part = addPart(
      petalRoot,
      makePetalGeometry(index % 2 === 0),
      {
        wireStart: start,
        wireEnd: spec.wireEnd + index * 0.08,
        surfaceStart: spec.surfaceStart + index * 0.08,
        surfaceEnd: spec.surfaceEnd + index * 0.08,
      },
      { wireColor: "#ff9be8", roughness: 0.36, clearcoat: 0.25 },
    );
    part.petal = { root: petalRoot, angle: index * 60, fold: 0.72, start: spec.wireStart };
  }

  const pistilCurve = new THREE.CubicBezierCurve3(
    new THREE.Vector3(0, 0, 0),
    new THREE.Vector3(0.02, 0.4, 0.02),
    new THREE.Vector3(0.06, 0.75, 0.08),
    new THREE.Vector3(0.08, 0.95, 0.12),
  );
  addPart(
    flower,
    taperedTube(pistilCurve, 0.016, 0.02, "#75a94b", "#9d6381", 24, 8),
    { wireStart: spec.wireStart + 0.6, wireEnd: spec.wireEnd + 0.6, surfaceStart: spec.surfaceStart + 0.6, surfaceEnd: spec.surfaceEnd + 0.6 },
    { wireColor: "#b5f292", roughness: 0.6 },
  );

  const stigma = addPart(
    flower,
    new THREE.SphereGeometry(0.044, 12, 10),
    {
      wireStart: spec.wireStart + 0.8,
      wireEnd: spec.wireEnd + 0.8,
      surfaceStart: spec.surfaceStart + 0.8,
      surfaceEnd: spec.surfaceEnd + 0.8,
    },
    { color: "#b87491", wireColor: "#f6b6d6", roughness: 0.48 },
  );
  stigma.growGroup.position.set(0.08, 0.94, 0.12);

  for (let index = 0; index < 6; index += 1) {
    const angle = index * (Math.PI / 3) + 0.52;
    const cos = Math.cos(angle);
    const sin = Math.sin(angle);
    const filament = new THREE.CubicBezierCurve3(
      new THREE.Vector3(0.02 * cos, 0.02, 0.02 * sin),
      new THREE.Vector3(0.08 * cos, 0.32, 0.08 * sin),
      new THREE.Vector3(0.18 * cos, 0.62, 0.18 * sin),
      new THREE.Vector3(0.38 * cos, 0.78, 0.38 * sin),
    );
    addPart(
      flower,
      taperedTube(filament, 0.012, 0.018, "#d4b264", "#e7c977", 20, 7),
      { wireStart: spec.wireStart + 0.6 + index * 0.08, wireEnd: spec.wireEnd + 0.6, surfaceStart: spec.surfaceStart + 0.6, surfaceEnd: spec.surfaceEnd + 0.6 },
      { wireColor: "#ffe7a0", roughness: 0.52 },
    );

    const anther = addPart(
      flower,
      new THREE.SphereGeometry(0.052, 12, 8),
      {
        wireStart: spec.wireStart + 1.2 + index * 0.08,
        wireEnd: spec.wireEnd + 1.2 + index * 0.08,
        surfaceStart: spec.surfaceStart + 1.2 + index * 0.08,
        surfaceEnd: spec.surfaceEnd + 1.2 + index * 0.08,
      },
      { color: "#d9a64e", wireColor: "#ffe7a0", roughness: 0.58 },
    );
    anther.growGroup.position.set(0.38 * cos, 0.78, 0.38 * sin);
    anther.baseScale.set(0.62, 1.8, 0.65);
  }
}

addFlower({
  center: [-0.38, 0.55, 0.25],
  axis: [0.3, 1, 0.2],
  tilt: -35,
  roll: 30,
  wireStart: 3.2,
  wireEnd: 5.8,
  surfaceStart: 6.5,
  surfaceEnd: 9.5,
  scale: 0.95,
});
addFlower({
  center: [0.35, 0.3, 0.18],
  axis: [-0.2, 1, 0.4],
  tilt: 45,
  roll: 25,
  wireStart: 3.8,
  wireEnd: 6.4,
  surfaceStart: 7,
  surfaceEnd: 10,
  scale: 0.9,
});
addFlower({
  center: [-0.05, -0.15, 0.4],
  axis: [0, 1, 0],
  tilt: 10,
  roll: 42,
  wireStart: 4.4,
  wireEnd: 7,
  surfaceStart: 7.6,
  surfaceEnd: 10.6,
  scale: 1.02,
});

function makeBudGeometry() {
  const geometry = new THREE.SphereGeometry(1, 18, 14);
  const positions = geometry.getAttribute("position");
  const colors = [];
  const green = new THREE.Color("#477c36");
  const pink = new THREE.Color("#dc7995");
  for (let index = 0; index < positions.count; index += 1) {
    const height = clamp01((positions.getY(index) + 0.25) / 1.25);
    const color = green.clone().lerp(pink, smooth(0.25, 1, height));
    colors.push(color.r, color.g, color.b);
  }
  geometry.setAttribute("color", new THREE.Float32BufferAttribute(colors, 3));
  geometry.scale(0.12, 0.31, 0.12);
  return geometry;
}

const budGeometry = makeBudGeometry();
[
  { center: [-0.12, 1.25, -0.05], axis: [0.3, 0.1, 1], angle: 20, wireStart: 2.2 },
  { center: [0.15, 1.45, 0.02], axis: [-0.4, 0.2, 1], angle: -25, wireStart: 2.5 },
].forEach((spec) => {
  const bud = new THREE.Group();
  bud.position.set(...spec.center);
  bud.quaternion.copy(axisRotation(spec.axis, spec.angle));
  plant.add(bud);
  addPart(
    bud,
    budGeometry.clone(),
    { wireStart: spec.wireStart, wireEnd: spec.wireStart + 1.8, surfaceStart: spec.wireStart + 1, surfaceEnd: spec.wireStart + 2.8 },
    { wireColor: "#8df2a5", roughness: 0.56 },
  );
});

const pollenPositions = [];
let seed = 42;
function random() {
  seed = (seed * 1664525 + 1013904223) >>> 0;
  return seed / 4294967296;
}
for (let index = 0; index < 120; index += 1) {
  pollenPositions.push(
    (random() * 2.4) - 1.2,
    (random() * 3.3) - 1.5,
    (random() * 2.2) - 1,
  );
}
const pollenGeometry = new THREE.BufferGeometry();
pollenGeometry.setAttribute("position", new THREE.Float32BufferAttribute(pollenPositions, 3));
const pollenCanvas = document.createElement("canvas");
pollenCanvas.width = 64;
pollenCanvas.height = 64;
const pollenContext = pollenCanvas.getContext("2d");
const pollenGlow = pollenContext.createRadialGradient(32, 32, 2, 32, 32, 31);
pollenGlow.addColorStop(0, "rgba(255,244,197,1)");
pollenGlow.addColorStop(0.22, "rgba(255,218,156,0.75)");
pollenGlow.addColorStop(1, "rgba(255,183,120,0)");
pollenContext.fillStyle = pollenGlow;
pollenContext.fillRect(0, 0, 64, 64);
const pollenTexture = new THREE.CanvasTexture(pollenCanvas);
const pollen = new THREE.Points(
  pollenGeometry,
  new THREE.PointsMaterial({
    color: "#ffd89a",
    size: 0.11,
    map: pollenTexture,
    transparent: true,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
    sizeAttenuation: true,
  }),
);
scene.add(pollen);

function updateParts(time) {
  for (const part of parts) {
    const { wireStart, wireEnd, surfaceStart, surfaceEnd } = part.timing;
    const wireAlpha = smooth(wireStart, wireEnd, time);
    const surfaceAlpha = smooth(surfaceStart, surfaceEnd, time);
    const reveal = smooth(wireStart, wireStart + 0.8, time);

    part.growGroup.visible = reveal > 0.001;
    part.growGroup.scale.copy(part.baseScale).multiplyScalar(0.025 + 0.975 * reveal);

    part.mesh.visible = surfaceAlpha > 0.001;
    part.mesh.material.opacity = surfaceAlpha;

    const wireOpacity = wireAlpha * (1 - 0.82 * surfaceAlpha);
    part.wire.visible = wireOpacity > 0.001;
    part.wire.material.opacity = wireOpacity;

    if (part.petal) {
      const opening = smooth(part.petal.start, part.petal.start + 5.8, time);
      const azimuth = new THREE.Quaternion().setFromAxisAngle(
        new THREE.Vector3(0, 1, 0),
        THREE.MathUtils.degToRad(part.petal.angle),
      );
      const fold = new THREE.Quaternion().setFromAxisAngle(
        new THREE.Vector3(0, 0, 1),
        part.petal.fold * (1 - opening),
      );
      part.petal.root.quaternion.copy(azimuth).multiply(fold);
    }

    if (part.sway) {
      part.growGroup.rotation.z = Math.sin(time * 1.35 + part.sway.phase) * part.sway.amount;
    }
  }

  for (const { group, spec } of flowerAnimations) {
    const bloom = smooth(spec.wireStart, spec.wireStart + 1.1, time);
    group.scale.setScalar(spec.scale * Math.max(0.001, bloom));
  }

  plant.position.y = 0.02 * Math.sin(time * 1.2);
  pollen.visible = time > 2;
  pollen.rotation.y = time * 0.035;
  pollen.position.y = Math.sin(time * 0.18) * 0.06;
}

function replayAnimation() {
  window.clearTimeout(messageRevealTimer);
  window.clearTimeout(messageCloseTimer);
  messageWidget.classList.remove("is-visible", "is-open");
  messageWidget.setAttribute("aria-hidden", "true");
  folderToggle.setAttribute("aria-expanded", "false");
  folderToggle.setAttribute("aria-label", "Open message folder");
  messageCard.hidden = true;
  elapsed = 0;
  playing = true;
  controls.reset();
  controls.autoRotate = true;
  updateParts(elapsed);
}

function openMessage() {
  window.clearTimeout(messageCloseTimer);
  messageCard.hidden = false;
  messageWidget.classList.add("is-open");
  folderToggle.setAttribute("aria-expanded", "true");
  folderToggle.setAttribute("aria-label", "Close message folder");
}

function closeMessage() {
  messageWidget.classList.remove("is-open");
  folderToggle.setAttribute("aria-expanded", "false");
  folderToggle.setAttribute("aria-label", "Open message folder");
  window.clearTimeout(messageCloseTimer);
  messageCloseTimer = window.setTimeout(() => {
    if (!messageWidget.classList.contains("is-open")) messageCard.hidden = true;
  }, 550);
}

folderToggle.addEventListener("click", () => {
  if (messageWidget.classList.contains("is-open")) closeMessage();
  else openMessage();
});
messageClose.addEventListener("click", closeMessage);

sceneElement.addEventListener("click", (event) => {
  if (
    messageWidget.classList.contains("is-open")
    && !messageCard.contains(event.target)
    && !folderToggle.contains(event.target)
    && event.target !== replayButton
  ) closeMessage();
});

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && messageWidget.classList.contains("is-open")) closeMessage();
});

replayButton.addEventListener("click", () => {
  replayAnimation();
  if (!document.fullscreenElement) {
    if (typeof sceneElement.requestFullscreen !== "function") {
      console.error("Fullscreen is unavailable in this browser.");
      return;
    }
    sceneElement.requestFullscreen().catch((error) => {
      console.error("Could not enter fullscreen:", error);
    });
  }
});

const resizeObserver = new ResizeObserver(() => {
  const width = Math.max(1, sceneElement.clientWidth);
  const height = Math.max(1, sceneElement.clientHeight);
  camera.aspect = width / height;
  camera.updateProjectionMatrix();
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.setSize(width, height, false);
});
resizeObserver.observe(sceneElement);

function animate() {
  requestAnimationFrame(animate);
  const delta = Math.min(clock.getDelta(), 0.05);
  if (playing) {
    elapsed = Math.min(duration, elapsed + delta);
    if (elapsed >= duration) {
      playing = false;
      messageRevealTimer = window.setTimeout(() => {
        messageWidget.classList.add("is-visible");
        messageWidget.setAttribute("aria-hidden", "false");
      }, messageDelay);
    }
  }
  updateParts(elapsed);
  controls.update(delta);
  renderer.render(scene, camera);
}

animate();
loading.hidden = true;
canvas.dataset.ready = "true";
