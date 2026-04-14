import * as THREE from "https://unpkg.com/three@0.160.0/build/three.module.js";

const HEARTBEAT_FRESH_MS = 5 * 60 * 1000;
const HEARTBEAT_SYNC_MS = 4000;
const MAX_AGENTS = 42;

const CORE_TEAM = new Set(["Marcos", "Raquel", "Thiago", "Jarvina"]);

const DEPARTMENTS = {
  tech: {
    id: "tech",
    label: "Produto e Tecnologia",
    color: 0x3a82c9,
    action: "arquitetura, codigo, QA e operacao tecnica"
  },
  design: {
    id: "design",
    label: "Design e Criacao",
    color: 0xa36bd8,
    action: "UX, visual, identidade e direcao criativa"
  },
  marketing: {
    id: "marketing",
    label: "Marketing e Midia",
    color: 0x4dbb84,
    action: "campanhas, social, SEO e performance"
  },
  comercial: {
    id: "comercial",
    label: "Comercial Regional",
    color: 0xd78a45,
    action: "clientes, operacao regional e expansao comercial"
  },
  voz: {
    id: "voz",
    label: "Voz e Conteudo",
    color: 0x49bfc4,
    action: "locucao, audio, trilha e experiencia de voz"
  },
  direcao: {
    id: "direcao",
    label: "Direcao e Operacoes",
    color: 0xd25f78,
    action: "estrategia, priorizacao e governanca"
  }
};

const ROW_DEPARTMENT_ORDER = ["tech", "design", "marketing", "comercial", "voz", "direcao"];

const DEPARTMENT_CHIEF_CANDIDATES = {
  tech: ["Marcos", "Ricardo", "Igor"],
  design: ["Raquel", "Bruno", "Julia"],
  marketing: ["Amanda", "Lucas", "Vinicius"],
  comercial: ["Roberto", "Patricia", "Sandra", "Luiz"],
  voz: ["Jarvina", "Sofia", "Carlos", "Pedro"],
  direcao: ["assistant", "Helena", "Renata", "Sanntiago"]
};

const KEYWORD_RULES = [
  { dept: "tech", keys: ["deploy", "backend", "api", "infra", "bug", "erro", "falha", "qa", "teste", "codigo", "sistema", "railway", "websocket", "ws", "performance tecnica"] },
  { dept: "design", keys: ["design", "ux", "ui", "layout", "identidade", "criativo", "criacao", "motion", "visual", "arte", "tipografia"] },
  { dept: "marketing", keys: ["campanha", "trafego", "seo", "social", "midia", "ads", "influencer", "marketing", "performance", "conteudo social"] },
  { dept: "comercial", keys: ["cliente", "comercial", "regional", "vendas", "contrato", "expansao", "negocio"] },
  { dept: "voz", keys: ["voz", "audio", "locucao", "narracao", "trilha", "musica", "sfx", "jarvina"] },
  { dept: "direcao", keys: ["estrategia", "prioridade", "roadmap", "pmo", "governanca", "lideranca", "ceo", "sanntiago"] }
];

const FALLBACK_AGENT_RECORDS = [
  { name: "Amanda", specialty: "Social Media Manager" },
  { name: "Ana", specialty: "Product Manager" },
  { name: "Antonio", specialty: "Executive Assistant" },
  { name: "assistant", specialty: "Coordinator" },
  { name: "Beatriz", specialty: "Legal Advisor" },
  { name: "bohr", specialty: "Quality" },
  { name: "Bruno", specialty: "Designer Criativo" },
  { name: "Camila", specialty: "Influencer Marketing" },
  { name: "Carla", specialty: "Media Planning" },
  { name: "Carlos", specialty: "Produtor Musical" },
  { name: "Daniela", specialty: "People Development" },
  { name: "Diego", specialty: "AI Specialist" },
  { name: "Eduardo", specialty: "Business Intelligence" },
  { name: "Felipe", specialty: "Talent Acquisition" },
  { name: "Fernando", specialty: "Full-Stack Developer" },
  { name: "Gustavo", specialty: "Growth Analyst" },
  { name: "halley", specialty: "Performance" },
  { name: "Helena", specialty: "PMO" },
  { name: "Igor", specialty: "Infrastructure Engineer" },
  { name: "Jarvina", specialty: "Voice Assistant Coordinator" },
  { name: "Julia", specialty: "Motion Designer" },
  { name: "Laura", specialty: "Copywriter" },
  { name: "Lucas", specialty: "SEO Specialist" },
  { name: "Luiz", specialty: "Regional Manager Sul" },
  { name: "Marcos", specialty: "Technical Validation Lead" },
  { name: "MarcosJr", specialty: "Front-end Developer" },
  { name: "Mariana", specialty: "Brand Strategy" },
  { name: "Natalia", specialty: "Innovation Manager" },
  { name: "Otavio", specialty: "QA Zoom Studio Hub" },
  { name: "Patricia", specialty: "Regional Manager RJ" },
  { name: "Pedro", specialty: "Editor de Audio" },
  { name: "Rafael", specialty: "Software Engineer" },
  { name: "Raquel", specialty: "Design Criativo" },
  { name: "Renata", specialty: "HR Manager" },
  { name: "Ricardo", specialty: "Full-Stack Developer" },
  { name: "Roberto", specialty: "Regional Manager SP" },
  { name: "Sandra", specialty: "Regional Manager Nordeste" },
  { name: "Sofia", specialty: "Locutora Profissional" },
  { name: "Thiago", specialty: "HR Analytics" },
  { name: "Valentina", specialty: "UX Researcher" },
  { name: "Vinicius", specialty: "Performance Marketing" },
  { name: "volta", specialty: "Strategy" }
];

const canvas = document.getElementById("scene");
const logEl = document.getElementById("eventLog");
const followSelect = document.getElementById("followAgent");
const btnLabels = document.getElementById("btnLabels");
const mtTotal = document.getElementById("mtTotal");
const mtActive = document.getElementById("mtActive");
const mtDesk = document.getElementById("mtDesk");
const mtMoving = document.getElementById("mtMoving");
const mtMeeting = document.getElementById("mtMeeting");
const cameraModeLabel = document.getElementById("cameraModeLabel");
const chatMessages = document.getElementById("chatMessages");
const chatInput = document.getElementById("chatInput");

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x071a2b);
scene.fog = new THREE.Fog(0x071a2b, 88, 260);

const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;

const camera = new THREE.PerspectiveCamera(60, window.innerWidth / window.innerHeight, 0.1, 900);
const world = new THREE.Group();
scene.add(world);

scene.add(new THREE.HemisphereLight(0x8ecaf8, 0x365648, 0.98));
const dir = new THREE.DirectionalLight(0xffffff, 0.9);
dir.position.set(40, 64, 26);
dir.castShadow = true;
dir.shadow.mapSize.set(2048, 2048);
dir.shadow.camera.left = -140;
dir.shadow.camera.right = 140;
dir.shadow.camera.top = 140;
dir.shadow.camera.bottom = -140;
scene.add(dir);
scene.add(new THREE.AmbientLight(0x82a4bf, 0.35));

const MAT_WALL = new THREE.MeshStandardMaterial({ color: 0x1a3850, roughness: 0.93, metalness: 0.05 });
const MAT_OPEN = new THREE.MeshStandardMaterial({ color: 0x113c52, transparent: true, opacity: 0.62 });
const MAT_MEETING = new THREE.MeshStandardMaterial({ color: 0x20455f, transparent: true, opacity: 0.66 });
const MAT_CEO = new THREE.MeshStandardMaterial({ color: 0x30366a, transparent: true, opacity: 0.58 });
const MAT_DOOR = new THREE.MeshStandardMaterial({ color: 0x7fe0ff, transparent: true, opacity: 0.2, roughness: 0.25, metalness: 0.18 });

const DOORS = {
  openMeetingIn: new THREE.Vector3(27.6, 0, 0),
  openMeetingOut: new THREE.Vector3(34.4, 0, 0),
  meetingCeoIn: new THREE.Vector3(60, 0, 24),
  meetingCeoOut: new THREE.Vector3(60, 0, 31)
};

const agents = [];
const agentBySlug = new Map();
const agentByName = new Map();
const departmentLeaders = new Map();
const departmentSigns = new Map();
const departmentSlotIndices = new Map();
const deskSlots = [];
const deskStations = [];

const chatQueue = [];
let chatQueueRunning = false;

let heartbeatHealthy = true;
let heartbeatTimer = null;
let firstHeartbeatSync = true;
let manualMeetingActive = false;
let labelsVisible = true;
let topClockSecond = -1;

const chatActorMap = new Map();

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function slugify(value) {
  return String(value || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function parseIsoMs(value) {
  const ms = Date.parse(String(value || ""));
  return Number.isFinite(ms) ? ms : null;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function hashColor(name) {
  let h = 0;
  for (let i = 0; i < name.length; i += 1) h = (h * 31 + name.charCodeAt(i)) >>> 0;
  return h % 360;
}

function uniqueBySlug(records) {
  const seen = new Set();
  const out = [];
  for (const record of records) {
    const slug = slugify(record.name);
    if (!slug || seen.has(slug)) continue;
    seen.add(slug);
    out.push(record);
  }
  return out;
}

function createTextTexture(
  text,
  {
    width = 512,
    height = 128,
    bg = "rgba(5,15,24,0.72)",
    border = "rgba(134,194,233,0.75)",
    color = "#ffffff",
    font = "bold 46px Segoe UI"
  } = {}
) {
  const cvs = document.createElement("canvas");
  cvs.width = width;
  cvs.height = height;
  const ctx = cvs.getContext("2d");
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, width, height);
  ctx.strokeStyle = border;
  ctx.lineWidth = 6;
  ctx.strokeRect(4, 4, width - 8, height - 8);
  ctx.fillStyle = color;
  ctx.font = font;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText(text, width / 2, height / 2 + 1);
  const texture = new THREE.CanvasTexture(cvs);
  texture.needsUpdate = true;
  return texture;
}

function makeTextSprite(text, options = {}, scale = [14, 3.5]) {
  const texture = createTextTexture(text, options);
  const material = new THREE.SpriteMaterial({ map: texture, transparent: true });
  const sprite = new THREE.Sprite(material);
  sprite.scale.set(scale[0], scale[1], 1);
  return sprite;
}

function updateSpriteText(sprite, text, options = {}) {
  const oldMap = sprite.material.map;
  const newMap = createTextTexture(text, options);
  sprite.material.map = newMap;
  sprite.material.needsUpdate = true;
  if (oldMap) oldMap.dispose();
}

function addEvent(message) {
  const node = document.createElement("article");
  node.className = "evt";
  const t = document.createElement("div");
  t.className = "t";
  t.textContent = new Date().toLocaleTimeString("pt-BR", { hour12: false });
  const m = document.createElement("div");
  m.className = "m";
  m.textContent = message;
  node.append(t, m);
  logEl.prepend(node);
  while (logEl.children.length > 120) logEl.removeChild(logEl.lastElementChild);
}

function addChatMessage(kind, from, text) {
  const node = document.createElement("article");
  node.className = `msg ${kind}`;
  const meta = document.createElement("div");
  meta.className = "meta";
  meta.textContent = `${new Date().toLocaleTimeString("pt-BR", { hour12: false })} | ${from}`;
  const body = document.createElement("div");
  body.textContent = text;
  node.append(meta, body);
  chatMessages.prepend(node);
  while (chatMessages.children.length > 150) {
    chatMessages.removeChild(chatMessages.lastElementChild);
  }
}

function addZoneFloor(w, h, x, z, mat) {
  const p = new THREE.Mesh(new THREE.PlaneGeometry(w, h), mat);
  p.rotation.x = -Math.PI / 2;
  p.position.set(x, 0.02, z);
  p.receiveShadow = true;
  world.add(p);
}

function addWall(x, z, w, h, d) {
  const wall = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), MAT_WALL);
  wall.position.set(x, h / 2, z);
  wall.castShadow = true;
  wall.receiveShadow = true;
  world.add(wall);
  return wall;
}

function addDoorFrame(position, orientation = "x", label = "PORTA", width = 4.8) {
  const frame = new THREE.Group();
  const post = new THREE.Mesh(
    new THREE.BoxGeometry(0.34, 4.2, 0.34),
    new THREE.MeshStandardMaterial({ color: 0x5bc7f0, roughness: 0.42, metalness: 0.35 })
  );
  const top = new THREE.Mesh(
    new THREE.BoxGeometry(orientation === "x" ? 0.34 : width + 0.68, 0.34, orientation === "x" ? width + 0.68 : 0.34),
    new THREE.MeshStandardMaterial({ color: 0x5bc7f0, roughness: 0.42, metalness: 0.35 })
  );
  const glass = new THREE.Mesh(
    new THREE.BoxGeometry(orientation === "x" ? 0.08 : width, 3.5, orientation === "x" ? width : 0.08),
    MAT_DOOR
  );

  const p1 = post.clone();
  const p2 = post.clone();
  if (orientation === "x") {
    p1.position.set(0, 2.1, -width / 2);
    p2.position.set(0, 2.1, width / 2);
    top.position.set(0, 4.08, 0);
  } else {
    p1.position.set(-width / 2, 2.1, 0);
    p2.position.set(width / 2, 2.1, 0);
    top.position.set(0, 4.08, 0);
  }
  glass.position.set(0, 1.8, 0);
  frame.add(p1, p2, top, glass);
  frame.position.copy(position);
  world.add(frame);

  const sign = makeTextSprite(label, { font: "bold 38px Segoe UI", color: "#cbf2ff" }, [5.3, 1.55]);
  sign.position.set(position.x + (orientation === "x" ? 0.9 : 0), 5.15, position.z + (orientation === "z" ? 0.9 : 0));
  world.add(sign);
}

function addPlant(x, z, scale = 1) {
  const g = new THREE.Group();
  g.position.set(x, 0, z);
  g.scale.setScalar(scale);

  const pot = new THREE.Mesh(
    new THREE.CylinderGeometry(0.9, 1.1, 1.1, 14),
    new THREE.MeshStandardMaterial({ color: 0x6f4f36, roughness: 0.82 })
  );
  pot.position.y = 0.55;
  pot.castShadow = true;
  pot.receiveShadow = true;

  const stem = new THREE.Mesh(
    new THREE.CylinderGeometry(0.14, 0.2, 1.9, 8),
    new THREE.MeshStandardMaterial({ color: 0x3f7f4a, roughness: 0.7 })
  );
  stem.position.y = 1.8;
  stem.castShadow = true;

  const leafMat = new THREE.MeshStandardMaterial({ color: 0x4aa85f, roughness: 0.6 });
  const leaf1 = new THREE.Mesh(new THREE.SphereGeometry(0.6, 10, 10), leafMat);
  leaf1.position.set(-0.42, 2.65, 0.08);
  leaf1.castShadow = true;
  const leaf2 = new THREE.Mesh(new THREE.SphereGeometry(0.62, 10, 10), leafMat);
  leaf2.position.set(0.4, 2.45, -0.15);
  leaf2.castShadow = true;
  const leaf3 = new THREE.Mesh(new THREE.SphereGeometry(0.52, 10, 10), leafMat);
  leaf3.position.set(0.05, 3.0, 0.12);
  leaf3.castShadow = true;

  g.add(pot, stem, leaf1, leaf2, leaf3);
  world.add(g);
}

function buildWorldBase() {
  const ground = new THREE.Mesh(
    new THREE.PlaneGeometry(240, 150),
    new THREE.MeshStandardMaterial({ color: 0x0d2d3f, roughness: 0.95, metalness: 0.05 })
  );
  ground.rotation.x = -Math.PI / 2;
  ground.position.y = -0.02;
  ground.receiveShadow = true;
  world.add(ground);
  world.add(new THREE.GridHelper(220, 44, 0x2a6388, 0x184c67));

  addZoneFloor(120, 78, -34, 0, MAT_OPEN);
  addZoneFloor(58, 42, 60, 0, MAT_MEETING);
  addZoneFloor(58, 30, 60, 45, MAT_CEO);

  // Bordas externas
  addWall(-95, 0, 2, 8, 90);
  addWall(95, 0, 2, 8, 90);
  addWall(0, -45, 190, 8, 2);
  addWall(0, 60, 190, 8, 2);

  // Sala de reuniao com porta para Open Space (x = 31, z = 0)
  addWall(31, -12.5, 2, 8, 17);
  addWall(31, 12.5, 2, 8, 17);
  addWall(89, 0, 2, 8, 42);
  addWall(60, -21, 58, 8, 2);
  addWall(60, 21, 58, 8, 2);
  addDoorFrame(new THREE.Vector3(31, 0, 0), "x", "PORTA OPEN", 7.8);

  // Sala do CEO com porta para corredor/reuniao (z = 30, x = 60)
  addWall(31, 45, 2, 8, 30);
  addWall(89, 45, 2, 8, 30);
  addWall(60, 60, 58, 8, 2);
  addWall(43, 30, 24, 8, 2);
  addWall(77, 30, 24, 8, 2);
  addDoorFrame(new THREE.Vector3(60, 0, 30), "z", "PORTA CEO", 9.6);

  const sign1 = makeTextSprite("OPEN SPACE", { color: "#c9f0ff" });
  sign1.position.set(-34, 5.5, 36);
  world.add(sign1);
  const sign2 = makeTextSprite("SALA DE REUNIAO", { color: "#c9f0ff" });
  sign2.position.set(60, 5.5, 18);
  world.add(sign2);
  const sign3 = makeTextSprite("CEO SANNTIAGO", { color: "#c9f0ff" });
  sign3.position.set(60, 5.5, 58);
  world.add(sign3);

  // Plantas decorativas
  addPlant(-90, -35, 1.08);
  addPlant(-90, 35, 1.08);
  addPlant(24, -35, 1.08);
  addPlant(24, 35, 1.08);
  addPlant(34, -16, 0.9);
  addPlant(86, -16, 0.9);
  addPlant(34, 16, 0.9);
  addPlant(86, 16, 0.9);
  addPlant(34, 34, 0.82);
  addPlant(86, 34, 0.82);
  addPlant(34, 56, 0.82);
  addPlant(86, 56, 0.82);
}

function addDepartmentStripe(row, deptId, z) {
  const color = DEPARTMENTS[deptId].color;
  const stripe = new THREE.Mesh(
    new THREE.PlaneGeometry(88, 8.2),
    new THREE.MeshStandardMaterial({ color, transparent: true, opacity: 0.12 })
  );
  stripe.rotation.x = -Math.PI / 2;
  stripe.position.set(-34, 0.021, z);
  stripe.receiveShadow = true;
  world.add(stripe);

  const title = makeTextSprite(DEPARTMENTS[deptId].label, { font: "bold 34px Segoe UI", color: "#d7f2ff" }, [9.8, 1.8]);
  title.position.set(-86, 3.8, z);
  world.add(title);
  departmentSigns.set(deptId, { sprite: title, z });
}

function addDeskStation(slot) {
  const deptColor = DEPARTMENTS[slot.deptId].color;
  const g = new THREE.Group();
  g.position.set(slot.x, 0, slot.z);

  const desk = new THREE.Mesh(
    new THREE.BoxGeometry(5.6, 1.1, 2.6),
    new THREE.MeshStandardMaterial({ color: deptColor, roughness: 0.86, metalness: 0.08 })
  );
  desk.position.set(0, 0.62, 0);
  desk.castShadow = true;
  desk.receiveShadow = true;
  g.add(desk);

  const chair = new THREE.Mesh(
    new THREE.BoxGeometry(1.2, 1.2, 1.2),
    new THREE.MeshStandardMaterial({ color: 0x1a2a36, roughness: 0.9 })
  );
  chair.position.set(0, 0.6, 2.2);
  chair.castShadow = true;
  g.add(chair);

  const monitor = new THREE.Mesh(
    new THREE.BoxGeometry(1.2, 0.9, 0.15),
    new THREE.MeshStandardMaterial({ color: 0x8acbf4, roughness: 0.38, metalness: 0.22 })
  );
  monitor.position.set(0, 1.43, -0.7);
  monitor.castShadow = true;
  g.add(monitor);
  world.add(g);

  return { group: g, desk, chair, monitor, slot };
}

function buildDeskArea() {
  let idx = 0;
  for (let r = 0; r < 6; r += 1) {
    const deptId = ROW_DEPARTMENT_ORDER[r];
    const zRow = -28 + r * 9.0;
    addDepartmentStripe(r, deptId, zRow);
    if (!departmentSlotIndices.has(deptId)) departmentSlotIndices.set(deptId, []);

    for (let c = 0; c < 7; c += 1) {
      const x = -74 + c * 12.1;
      const z = zRow;
      const slot = { index: idx, row: r, col: c, x, z, deptId };
      deskSlots.push(slot);
      departmentSlotIndices.get(deptId).push(idx);
      deskStations.push(addDeskStation(slot));
      idx += 1;
    }
  }
}

const MEETING_CENTER = new THREE.Vector3(60, 0, 0);
const meetingSlots = [];
const ceoDeskPos = new THREE.Vector3(60, 0, 47.5);
const ceoMeetingPos = new THREE.Vector3(60, 0, -15.5);

function addMeetingChair(pos, rotY, host = false) {
  const seat = new THREE.Mesh(
    new THREE.BoxGeometry(1.35, 1.2, 1.35),
    new THREE.MeshStandardMaterial({ color: host ? 0x675ec5 : 0x303e49, roughness: 0.9 })
  );
  seat.position.set(pos.x, 0.62, pos.z);
  seat.rotation.y = rotY;
  seat.castShadow = true;
  world.add(seat);
}

function buildMeetingAndCeoFurniture() {
  const meetingTable = new THREE.Mesh(
    new THREE.CylinderGeometry(10.8, 11.3, 1.4, 28),
    new THREE.MeshStandardMaterial({ color: 0x2f5f79, roughness: 0.84 })
  );
  meetingTable.position.copy(MEETING_CENTER);
  meetingTable.position.y = 0.75;
  meetingTable.castShadow = true;
  meetingTable.receiveShadow = true;
  world.add(meetingTable);

  addMeetingChair(ceoMeetingPos, Math.PI, true);
  for (let i = 0; i < MAX_AGENTS; i += 1) {
    const t = (i / MAX_AGENTS) * Math.PI * 2;
    const x = MEETING_CENTER.x + Math.cos(t) * 16;
    const z = MEETING_CENTER.z + Math.sin(t) * 11;
    const rot = Math.atan2(MEETING_CENTER.x - x, MEETING_CENTER.z - z);
    const pos = new THREE.Vector3(x, 0, z);
    meetingSlots.push(pos);
    addMeetingChair(pos, rot);
  }

  const ceoDesk = new THREE.Mesh(
    new THREE.BoxGeometry(8.2, 1.2, 4.1),
    new THREE.MeshStandardMaterial({ color: 0x4f487c, roughness: 0.84 })
  );
  ceoDesk.position.set(60, 0.65, 45);
  ceoDesk.castShadow = true;
  world.add(ceoDesk);

  const ceoChair = new THREE.Mesh(
    new THREE.BoxGeometry(1.6, 1.6, 1.6),
    new THREE.MeshStandardMaterial({ color: 0x2f264f, roughness: 0.9 })
  );
  ceoChair.position.set(60, 0.8, 48.4);
  ceoChair.castShadow = true;
  world.add(ceoChair);
}

function classifyDepartment(record) {
  const override = String(record?.departmentOverride || "").toLowerCase().trim();
  if (override && DEPARTMENTS[override]) return override;

  const name = String(record.name || "").toLowerCase();
  const specialty = String(record.specialty || "").toLowerCase();
  const text = `${name} ${specialty}`;

  if (/jarvina|locutora|voz|audio|musical|trilha|sfx|narr/.test(text)) return "voz";
  if (/regional|comercial|vendas|cliente/.test(text)) return "comercial";
  if (/marketing|social|seo|influencer|performance|growth/.test(text)) return "marketing";
  if (/designer|design|motion|ux|criativ/.test(text)) return "design";
  if (/qa|developer|infra|ai|full-stack|validation|tech|backend|front-end/.test(text)) return "tech";
  if (/hr|people|talent|pmo|manager|assistant|strategy|govern/.test(text)) return "direcao";
  return "direcao";
}

function updateDepartmentSignLeader(deptId, leaderName) {
  const sign = departmentSigns.get(deptId);
  if (!sign) return;
  updateSpriteText(
    sign.sprite,
    `${DEPARTMENTS[deptId].label} | Lider: ${leaderName || "a definir"}`,
    { font: "bold 31px Segoe UI", color: "#d7f2ff" }
  );
}

function reorderMembersByChief(deptId, members) {
  const candidates = DEPARTMENT_CHIEF_CANDIDATES[deptId] || [];
  let chief = null;
  for (const candidate of candidates) {
    const candSlug = slugify(candidate);
    const found = members.find((m) => slugify(m.name) === candSlug);
    if (found) {
      chief = found;
      break;
    }
  }
  if (!chief && members.length > 0) chief = members[0];
  if (!chief) return { ordered: [], chiefName: "" };

  const ordered = [chief, ...members.filter((m) => slugify(m.name) !== slugify(chief.name))];
  return { ordered, chiefName: chief.name };
}

function assignAgents(records) {
  const grouped = new Map();
  for (const deptId of Object.keys(DEPARTMENTS)) grouped.set(deptId, []);
  for (const record of records) {
    const deptId = classifyDepartment(record);
    grouped.get(deptId).push(record);
  }
  for (const list of grouped.values()) {
    list.sort((a, b) => String(a.name).localeCompare(String(b.name), "pt-BR"));
  }

  const assignments = [];
  const usedSlotIndices = new Set();
  const overflow = [];

  for (const deptId of ROW_DEPARTMENT_ORDER) {
    const members = grouped.get(deptId) || [];
    const slots = departmentSlotIndices.get(deptId) || [];
    const { ordered, chiefName } = reorderMembersByChief(deptId, members);
    departmentLeaders.set(deptId, chiefName || "Sanntiago");
    updateDepartmentSignLeader(deptId, chiefName || "Sanntiago");

    for (let i = 0; i < ordered.length; i += 1) {
      const record = ordered[i];
      if (i < slots.length) {
        const slotIndex = slots[i];
        assignments.push({
          record,
          deptId,
          slotIndex,
          isChief: slugify(record.name) === slugify(chiefName)
        });
        usedSlotIndices.add(slotIndex);
      } else {
        overflow.push({ record, deptId, isChief: false });
      }
    }
  }

  const freeSlots = deskSlots.filter((s) => !usedSlotIndices.has(s.index));
  for (let i = 0; i < overflow.length && i < freeSlots.length; i += 1) {
    assignments.push({
      record: overflow[i].record,
      deptId: overflow[i].deptId,
      slotIndex: freeSlots[i].index,
      isChief: false
    });
    usedSlotIndices.add(freeSlots[i].index);
  }

  assignments.sort((a, b) => a.slotIndex - b.slotIndex);
  return assignments.slice(0, MAX_AGENTS);
}

function makeChiefRing(color = 0xffe894) {
  const ring = new THREE.Mesh(
    new THREE.TorusGeometry(0.85, 0.08, 10, 28),
    new THREE.MeshStandardMaterial({ color, roughness: 0.35, metalness: 0.6, emissive: 0x4f3c00, emissiveIntensity: 0.45 })
  );
  ring.rotation.x = Math.PI / 2;
  ring.position.y = 0.09;
  return ring;
}

function createAgent(assignment, index) {
  const slot = deskSlots[assignment.slotIndex];
  const station = deskStations[assignment.slotIndex];
  const hue = hashColor(assignment.record.name);

  const mesh = new THREE.Group();
  const body = new THREE.Mesh(
    new THREE.CapsuleGeometry(0.62, 1.5, 4, 10),
    new THREE.MeshStandardMaterial({
      color: new THREE.Color(`hsl(${hue} 65% 56%)`),
      roughness: 0.48,
      metalness: 0.08,
      emissive: assignment.isChief ? new THREE.Color(0x1b2340) : new THREE.Color(0x000000),
      emissiveIntensity: assignment.isChief ? 0.35 : 0
    })
  );
  body.position.y = 1.55;
  body.castShadow = true;
  mesh.add(body);

  const head = new THREE.Mesh(
    new THREE.SphereGeometry(0.52, 14, 12),
    new THREE.MeshStandardMaterial({ color: new THREE.Color(`hsl(${hue} 45% 84%)`), roughness: 0.6 })
  );
  head.position.y = 2.9;
  head.castShadow = true;
  mesh.add(head);

  if (assignment.isChief) {
    mesh.add(makeChiefRing());
    station.monitor.material.color.setHex(0xffdf86);
  }

  const label = makeTextSprite(
    assignment.isChief ? `${assignment.record.name} (Lider)` : assignment.record.name,
    { font: "bold 36px Segoe UI", bg: "rgba(3,16,27,.66)" },
    [9.2, 2.0]
  );
  label.position.y = 4.25;
  mesh.add(label);

  const deskPos = new THREE.Vector3(slot.x, 0, slot.z + 2.2);
  const meetingPos = meetingSlots[index % meetingSlots.length].clone();
  mesh.position.copy(deskPos);
  mesh.rotation.y = Math.PI;
  world.add(mesh);

  const agent = {
    type: "agent",
    name: assignment.record.name,
    slug: slugify(assignment.record.name),
    specialty: assignment.record.specialty || "",
    departmentId: assignment.deptId,
    isChief: assignment.isChief,
    mesh,
    label,
    deskPos,
    meetingPos,
    speechY: 5.4,
    state: "at_desk",
    speed: 8.8 + (index % 5) * 0.55,
    path: [],
    pathIndex: 0,
    liveActive: false,
    liveTaskId: "",
    bubble: null,
    bubbleTimer: null
  };
  return agent;
}

let ceoActor = null;

function createCeoActor() {
  const mesh = new THREE.Group();

  const body = new THREE.Mesh(
    new THREE.CapsuleGeometry(0.84, 2.0, 4, 12),
    new THREE.MeshStandardMaterial({ color: 0xe2d87b, roughness: 0.5, metalness: 0.08, emissive: 0x201d09, emissiveIntensity: 0.2 })
  );
  body.position.y = 2.1;
  body.castShadow = true;

  const head = new THREE.Mesh(
    new THREE.SphereGeometry(0.56, 14, 12),
    new THREE.MeshStandardMaterial({ color: 0xf2e5b9, roughness: 0.6 })
  );
  head.position.y = 3.6;
  head.castShadow = true;

  const halo = makeChiefRing(0xfff2a6);
  halo.scale.set(1.12, 1.12, 1.12);

  const label = makeTextSprite("Sanntiago (CEO)", { font: "bold 36px Segoe UI" }, [9.8, 2.0]);
  label.position.y = 5.25;

  mesh.add(body, head, halo, label);
  mesh.position.copy(ceoDeskPos);
  mesh.rotation.y = Math.PI;
  world.add(mesh);

  ceoActor = {
    type: "ceo",
    name: "Sanntiago",
    slug: "sanntiago",
    specialty: "CEO",
    departmentId: "direcao",
    isChief: true,
    mesh,
    label,
    speechY: 6.2,
    deskPos: ceoDeskPos.clone(),
    meetingPos: ceoMeetingPos.clone(),
    state: "in_office",
    speed: 9.2,
    path: [],
    pathIndex: 0,
    bubble: null,
    bubbleTimer: null
  };

  chatActorMap.set(ceoActor.slug, ceoActor);
}

const wallClock = {
  canvas: null,
  ctx: null,
  texture: null,
  mesh: null
};

function buildWallClock() {
  wallClock.canvas = document.createElement("canvas");
  wallClock.canvas.width = 512;
  wallClock.canvas.height = 160;
  wallClock.ctx = wallClock.canvas.getContext("2d");
  wallClock.texture = new THREE.CanvasTexture(wallClock.canvas);

  wallClock.mesh = new THREE.Mesh(
    new THREE.PlaneGeometry(9.2, 3.0),
    new THREE.MeshBasicMaterial({ map: wallClock.texture, transparent: true })
  );
  wallClock.mesh.position.set(60, 5.45, -19.95);
  world.add(wallClock.mesh);

  updateWallClock(true);
}

function updateWallClock(force = false) {
  if (!wallClock.ctx) return;
  const now = new Date();
  const sec = Math.floor(now.getTime() / 1000);
  if (!force && sec === topClockSecond) return;
  topClockSecond = sec;

  const time = now.toLocaleTimeString("pt-BR", { hour12: false, timeZone: "America/Sao_Paulo" });
  const date = now.toLocaleDateString("pt-BR", { timeZone: "America/Sao_Paulo" });

  const ctx = wallClock.ctx;
  ctx.clearRect(0, 0, wallClock.canvas.width, wallClock.canvas.height);
  ctx.fillStyle = "rgba(5,17,29,0.85)";
  ctx.fillRect(0, 0, wallClock.canvas.width, wallClock.canvas.height);
  ctx.strokeStyle = "rgba(126,205,237,0.8)";
  ctx.lineWidth = 6;
  ctx.strokeRect(4, 4, wallClock.canvas.width - 8, wallClock.canvas.height - 8);

  ctx.fillStyle = "#cbf2ff";
  ctx.font = "bold 58px Segoe UI";
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText(time, wallClock.canvas.width / 2, 70);

  ctx.fillStyle = "#93c5dc";
  ctx.font = "bold 30px Segoe UI";
  ctx.fillText(`${date} | BRT`, wallClock.canvas.width / 2, 122);

  wallClock.texture.needsUpdate = true;
}

function showSpeechBubble(actor, text) {
  const short = text.length > 68 ? `${text.slice(0, 65)}...` : text;
  if (actor.bubble) {
    actor.mesh.remove(actor.bubble);
    if (actor.bubble.material?.map) actor.bubble.material.map.dispose();
    actor.bubble.material.dispose();
    actor.bubble = null;
  }

  const bubble = makeTextSprite(short, { font: "bold 30px Segoe UI", bg: "rgba(3,16,27,.88)" }, [9.8, 2.2]);
  bubble.position.set(0, actor.speechY, 0);
  actor.mesh.add(bubble);
  actor.bubble = bubble;

  if (actor.bubbleTimer) clearTimeout(actor.bubbleTimer);
  actor.bubbleTimer = setTimeout(() => {
    if (!actor.bubble) return;
    actor.mesh.remove(actor.bubble);
    if (actor.bubble.material?.map) actor.bubble.material.map.dispose();
    actor.bubble.material.dispose();
    actor.bubble = null;
    actor.bubbleTimer = null;
  }, 2900);
}

function setMovement(actor, path, state) {
  actor.path = path;
  actor.pathIndex = 1;
  actor.state = state;
  if (actor.path.length > 0) actor.mesh.position.copy(actor.path[0]);
}

function pathToMeeting(agent) {
  const p = agent.mesh.position.clone();
  const seat = agent.meetingPos.clone();
  return [
    p.clone(),
    new THREE.Vector3(Math.min(p.x + 14, 18), 0, p.z),
    new THREE.Vector3(24, 0, clamp(p.z * 0.55, -14, 14)),
    DOORS.openMeetingIn.clone(),
    DOORS.openMeetingOut.clone(),
    new THREE.Vector3(48, 0, clamp(seat.z * 0.6, -12, 12)),
    seat
  ];
}

function pathToDesk(agent) {
  const p = agent.mesh.position.clone();
  const d = agent.deskPos.clone();
  return [
    p.clone(),
    new THREE.Vector3(48, 0, clamp(p.z * 0.6, -12, 12)),
    DOORS.openMeetingOut.clone(),
    DOORS.openMeetingIn.clone(),
    new THREE.Vector3(24, 0, clamp(d.z * 0.58, -18, 18)),
    new THREE.Vector3(d.x - 3.7, 0, d.z),
    d
  ];
}

function pathCeoToMeeting() {
  const p = ceoActor.mesh.position.clone();
  return [
    p.clone(),
    new THREE.Vector3(60, 0, 40),
    DOORS.meetingCeoOut.clone(),
    DOORS.meetingCeoIn.clone(),
    new THREE.Vector3(60, 0, 6),
    ceoActor.meetingPos.clone()
  ];
}

function pathCeoToOffice() {
  const p = ceoActor.mesh.position.clone();
  return [
    p.clone(),
    new THREE.Vector3(60, 0, 6),
    DOORS.meetingCeoIn.clone(),
    DOORS.meetingCeoOut.clone(),
    new THREE.Vector3(60, 0, 40),
    ceoActor.deskPos.clone()
  ];
}

function moveCEOToMeeting() {
  if (!ceoActor) return;
  if (ceoActor.state === "meeting_seated" || ceoActor.state === "moving_to_meeting") return;
  setMovement(ceoActor, pathCeoToMeeting(), "moving_to_meeting");
  addEvent("CEO Sanntiago saiu da sala e esta indo para reuniao.");
}

function moveCEOToOffice() {
  if (!ceoActor) return;
  if (ceoActor.state === "in_office" || ceoActor.state === "moving_to_office") return;
  setMovement(ceoActor, pathCeoToOffice(), "moving_to_office");
  addEvent("CEO Sanntiago retornando para sala executiva.");
}

function refreshMetrics() {
  let desk = 0;
  let moving = 0;
  let meeting = 0;
  let active = 0;
  for (const agent of agents) {
    if (agent.liveActive) active += 1;
    if (agent.state === "at_desk") desk += 1;
    else if (agent.state === "meeting_seated") meeting += 1;
    else moving += 1;
  }
  if (ceoActor) {
    if (ceoActor.state === "in_office") desk += 1;
    else if (ceoActor.state === "meeting_seated") meeting += 1;
    else moving += 1;
  }
  mtTotal.textContent = String(agents.length + (ceoActor ? 1 : 0));
  mtActive.textContent = String(active);
  mtDesk.textContent = String(desk);
  mtMoving.textContent = String(moving);
  mtMeeting.textContent = String(meeting);
}

function updateMovingActor(actor, dt) {
  if (actor.state !== "moving_to_meeting" && actor.state !== "moving_to_desk" && actor.state !== "moving_to_office") return;
  if (!actor.path || actor.pathIndex >= actor.path.length) return;

  const target = actor.path[actor.pathIndex];
  const delta = target.clone().sub(actor.mesh.position);
  const dist = delta.length();
  const step = actor.speed * dt;
  if (dist <= step) {
    actor.mesh.position.copy(target);
    actor.pathIndex += 1;
    if (actor.pathIndex >= actor.path.length) {
      if (actor.state === "moving_to_meeting") {
        actor.state = "meeting_seated";
        addEvent(`${actor.name} sentou na reuniao.`);
      } else if (actor.state === "moving_to_desk") {
        actor.state = "at_desk";
      } else if (actor.state === "moving_to_office") {
        actor.state = "in_office";
      }
      refreshMetrics();
    }
  } else {
    delta.normalize();
    actor.mesh.position.addScaledVector(delta, step);
    actor.mesh.rotation.y = Math.atan2(delta.x, delta.z);
  }
}

function convokeVisual(scope, source = "manual") {
  const list = scope === "all" ? agents : agents.filter((agent) => CORE_TEAM.has(agent.name));
  let moved = 0;
  for (const agent of list) {
    if (agent.state === "meeting_seated" || agent.state === "moving_to_meeting") continue;
    setMovement(agent, pathToMeeting(agent), "moving_to_meeting");
    moved += 1;
  }
  moveCEOToMeeting();
  if (source === "manual") manualMeetingActive = true;
  refreshMetrics();
  addEvent(`Convocacao visual: ${moved} agente(s) indo para sala.`);
}

function endMeeting(source = "manual") {
  let moved = 0;
  for (const agent of agents) {
    if (agent.state === "at_desk" || agent.state === "moving_to_desk") continue;
    setMovement(agent, pathToDesk(agent), "moving_to_desk");
    moved += 1;
  }
  moveCEOToOffice();
  if (source === "manual") manualMeetingActive = false;
  refreshMetrics();
  addEvent(`Encerrar reuniao: ${moved} agente(s) voltando para mesas.`);
}

async function callBackend(scope) {
  try {
    const response = await fetch("/api/convocar-equipe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ scope, durationSec: scope === "all" ? 300 : 180 })
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok || !payload.ok) {
      addEvent(`Aviso backend: erro ${payload.error || `HTTP ${response.status}`}.`);
      return;
    }
    addEvent(`Backend confirmado: ${Array.isArray(payload.started) ? payload.started.length : 0} agente(s) acionados.`);
  } catch (err) {
    addEvent(`Aviso backend: falha de rede (${err.message}).`);
  }
}

async function readRegistryAgents() {
  let loadedRegistry = false;
  try {
    const response = await fetch(`/memory-enterprise/60_AGENT_MEMORY/runtime/agents-registry.json?ts=${Date.now()}`, { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const payload = await response.json();
    loadedRegistry = true;
    const list = Array.isArray(payload?.agents) ? payload.agents : [];
    const records = list
      .map((item) => ({
        name: String(item?.name || "").trim(),
        specialty: String(item?.specialty || "").trim(),
        departmentOverride: String(item?.department_override || "").trim().toLowerCase(),
        employmentStatus: String(item?.employment_status || "").trim().toLowerCase(),
        active: typeof item?.active === "boolean" ? item.active : true
      }))
      .filter((record) => record.name)
      .filter((record) => record.active && record.employmentStatus !== "dismissed");
    const unique = uniqueBySlug(records);
    return unique.slice(0, MAX_AGENTS);
  } catch (err) {
    addEvent(`Aviso: registry indisponivel (${err.message}). Usando fallback.`);
  }
  if (loadedRegistry) return [];
  return FALLBACK_AGENT_RECORDS.slice(0, MAX_AGENTS);
}

function findHeartbeatEntry(heartbeatAgents, agent) {
  if (!heartbeatAgents || typeof heartbeatAgents !== "object") return null;
  return (
    heartbeatAgents[agent.slug] ||
    heartbeatAgents[agent.name] ||
    heartbeatAgents[slugify(agent.name)] ||
    null
  );
}

function isLiveActive(hbEntry) {
  if (!hbEntry || typeof hbEntry !== "object") return false;
  const status = String(hbEntry.status || "").toLowerCase();
  const activeTaskIds = Array.isArray(hbEntry.active_task_ids) ? hbEntry.active_task_ids : [];
  const updatedAtMs = parseIsoMs(hbEntry.updated_at);
  const fresh = updatedAtMs !== null && (Date.now() - updatedAtMs) <= HEARTBEAT_FRESH_MS;
  return fresh && (status === "in_progress" || activeTaskIds.length > 0);
}

function syncAgentMovementWithLiveState(agent, liveActive) {
  if (manualMeetingActive) return;
  if (liveActive) {
    if (agent.state === "at_desk" || agent.state === "moving_to_desk") {
      setMovement(agent, pathToMeeting(agent), "moving_to_meeting");
    }
  } else if (agent.state === "meeting_seated" || agent.state === "moving_to_meeting") {
    setMovement(agent, pathToDesk(agent), "moving_to_desk");
  }
}

async function syncAgentsWithHeartbeat() {
  try {
    const response = await fetch(`/memory-enterprise/60_AGENT_MEMORY/runtime/agent-heartbeats.json?ts=${Date.now()}`, { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const payload = await response.json();
    const heartbeatAgents = payload && typeof payload.agents === "object" ? payload.agents : {};

    let changed = 0;
    for (const agent of agents) {
      const hbEntry = findHeartbeatEntry(heartbeatAgents, agent);
      const liveActive = isLiveActive(hbEntry);
      const activeTaskIds = Array.isArray(hbEntry?.active_task_ids) ? hbEntry.active_task_ids : [];
      const taskId = String(activeTaskIds[0] || hbEntry?.current_task_id || "").trim();

      if (agent.liveActive !== liveActive || agent.liveTaskId !== taskId) {
        changed += 1;
      }

      if (agent.liveActive !== liveActive) {
        if (liveActive) {
          addEvent(`${agent.name} entrou em atividade${taskId ? ` (${taskId})` : ""}.`);
        } else {
          addEvent(`${agent.name} finalizou atividade e voltou ao fluxo normal.`);
        }
      }

      agent.liveActive = liveActive;
      agent.liveTaskId = taskId;
      syncAgentMovementWithLiveState(agent, liveActive);
    }

    const activeNow = agents.filter((agent) => agent.liveActive).length;
    if (!manualMeetingActive) {
      if (activeNow > 0) moveCEOToMeeting();
      else moveCEOToOffice();
    }

    refreshMetrics();
    if (!heartbeatHealthy) {
      heartbeatHealthy = true;
      addEvent("Sincronizacao de heartbeat restabelecida.");
    }
    if (firstHeartbeatSync) {
      firstHeartbeatSync = false;
      addEvent(`Sincronizacao inicial concluida: ${activeNow} agente(s) em execucao.`);
    } else if (changed > 0) {
      addEvent(`Heartbeat atualizado: ${activeNow} agente(s) em execucao agora.`);
    }
  } catch (err) {
    if (heartbeatHealthy) {
      heartbeatHealthy = false;
      addEvent(`Aviso: sem sincronizacao de heartbeat (${err.message}).`);
    }
  }
}

const observer = {
  pos: new THREE.Vector3(0, 2, 62),
  yaw: Math.PI,
  pitch: -0.22,
  zoom: 22,
  topHeight: 130,
  mode: "free",
  orbitAngle: 0,
  move: { w: 0, a: 0, s: 0, d: 0, shift: 0 },
  follow: ""
};

const pointer = { active: false, x: 0, y: 0 };

function setCameraMode(mode) {
  observer.mode = mode;
  if (cameraModeLabel) cameraModeLabel.textContent = `Modo atual: ${mode.toUpperCase()}`;
}

function getActorByMention(token) {
  const normalized = slugify(token);
  if (!normalized) return null;
  if (normalized === "ceo" || normalized === "sanntiago" || normalized === "santiago") return ceoActor;
  if (normalized === "todos") return { type: "all" };
  return agentBySlug.get(normalized) || null;
}

function getFollowTargetPosition(name) {
  const slug = slugify(name);
  if (slug === "sanntiago") return ceoActor?.mesh.position || null;
  const agent = agentBySlug.get(slug);
  return agent?.mesh.position || null;
}

function focusZone(zone) {
  observer.follow = "";
  followSelect.value = "";
  setCameraMode("free");
  if (zone === "open") {
    observer.pos.set(-34, 2, 58);
    observer.yaw = Math.PI;
    observer.pitch = -0.2;
  } else if (zone === "meeting") {
    observer.pos.set(60, 2, 27);
    observer.yaw = Math.PI;
    observer.pitch = -0.28;
  } else if (zone === "ceo") {
    observer.pos.set(60, 2, 66);
    observer.yaw = Math.PI;
    observer.pitch = -0.26;
  }
  addEvent(`Camera focada em ${zone.toUpperCase()}.`);
}

function updateObserver(dt) {
  if (observer.mode !== "free") return;
  if (observer.follow) {
    const target = getFollowTargetPosition(observer.follow);
    if (target) observer.pos.lerp(new THREE.Vector3(target.x, 2.1, target.z + 4.8), Math.min(1, dt * 4.6));
    return;
  }
  const speed = (observer.move.shift ? 35 : 21) * dt;
  const front = new THREE.Vector3(Math.sin(observer.yaw), 0, Math.cos(observer.yaw)).normalize();
  const side = new THREE.Vector3(front.z, 0, -front.x);
  if (observer.move.w) observer.pos.addScaledVector(front, speed);
  if (observer.move.s) observer.pos.addScaledVector(front, -speed);
  if (observer.move.a) observer.pos.addScaledVector(side, -speed);
  if (observer.move.d) observer.pos.addScaledVector(side, speed);
  observer.pos.x = clamp(observer.pos.x, -100, 98);
  observer.pos.z = clamp(observer.pos.z, -52, 66);
}

function updateCamera(dt, elapsed) {
  if (observer.mode === "top") {
    const desired = new THREE.Vector3(0, observer.topHeight, 6);
    camera.position.lerp(desired, 0.12);
    camera.lookAt(0, 0, 6);
    return;
  }

  if (observer.mode === "orbit") {
    observer.orbitAngle += dt * 0.35;
    const radius = 54;
    const cx = MEETING_CENTER.x;
    const cz = MEETING_CENTER.z;
    const ox = cx + Math.cos(observer.orbitAngle + elapsed * 0.01) * radius;
    const oz = cz + Math.sin(observer.orbitAngle + elapsed * 0.01) * radius;
    const desired = new THREE.Vector3(ox, 28, oz);
    camera.position.lerp(desired, 0.11);
    camera.lookAt(cx, 1.6, cz);
    return;
  }

  if (observer.mode === "meeting") {
    const desired = new THREE.Vector3(93, 18, 33);
    camera.position.lerp(desired, 0.15);
    camera.lookAt(60, 1.8, 0);
    return;
  }

  const cp = Math.cos(observer.pitch);
  const sp = Math.sin(observer.pitch);
  const bx = Math.sin(observer.yaw) * cp;
  const by = sp;
  const bz = Math.cos(observer.yaw) * cp;

  const desired = new THREE.Vector3(
    observer.pos.x - bx * observer.zoom,
    observer.pos.y + 5.6 - by * observer.zoom,
    observer.pos.z - bz * observer.zoom
  );
  camera.position.lerp(desired, 0.16);
  camera.lookAt(observer.pos.x, observer.pos.y + 1.6, observer.pos.z);
}

function updateAgents(dt) {
  for (const agent of agents) updateMovingActor(agent, dt);
  if (ceoActor) updateMovingActor(ceoActor, dt);
}

function parseMentions(message) {
  const mentions = [];
  const regex = /@([a-zA-Z0-9_\-]+)/g;
  let match = null;
  while ((match = regex.exec(message)) !== null) {
    mentions.push(match[1]);
  }
  return mentions;
}

function detectTopicDepartments(message, explicitActors = []) {
  const lower = String(message || "").toLowerCase();
  const out = new Set();

  for (const rule of KEYWORD_RULES) {
    if (rule.keys.some((key) => lower.includes(key))) out.add(rule.dept);
  }

  for (const actor of explicitActors) {
    if (actor?.departmentId) out.add(actor.departmentId);
  }

  return out;
}

function isResponsibilityQuestion(message) {
  const lower = String(message || "").toLowerCase();
  return /quem/.test(lower) && (/respons/.test(lower) || /cuida/.test(lower) || /lider/.test(lower));
}

function actorsFromDepartments(deptSet) {
  const deptIds = Array.from(deptSet);
  if (!deptIds.length) return [];
  return agents.filter((agent) => deptIds.includes(agent.departmentId));
}

function uniqueActors(actors) {
  const seen = new Set();
  const out = [];
  for (const actor of actors) {
    if (!actor) continue;
    const key = actor.slug || slugify(actor.name);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    out.push(actor);
  }
  return out;
}

function getDepartmentLeaderActor(deptId) {
  const leaderName = departmentLeaders.get(deptId);
  if (!leaderName) return null;
  if (slugify(leaderName) === "sanntiago") return ceoActor;
  return agentBySlug.get(slugify(leaderName)) || null;
}

function buildResponsibilityActors(deptSet) {
  const deptIds = deptSet.size ? Array.from(deptSet) : ROW_DEPARTMENT_ORDER.slice();
  const actors = deptIds.map((deptId) => getDepartmentLeaderActor(deptId));
  if (!actors.some(Boolean) && ceoActor) actors.push(ceoActor);
  return uniqueActors(actors);
}

function selectResponders(message) {
  const mentions = parseMentions(message);
  const mentionedActors = [];
  let hasAll = false;
  for (const token of mentions) {
    const actor = getActorByMention(token);
    if (!actor) continue;
    if (actor.type === "all") hasAll = true;
    else mentionedActors.push(actor);
  }
  const directActors = uniqueActors(mentionedActors);
  const topicDepartments = detectTopicDepartments(message, directActors);
  const responsibilityQuery = isResponsibilityQuestion(message);

  if (directActors.length > 0 && !hasAll) {
    return { actors: directActors, topicDepartments, responsibilityQuery };
  }

  if (responsibilityQuery) {
    const leaders = buildResponsibilityActors(topicDepartments);
    return { actors: leaders, topicDepartments, responsibilityQuery: true };
  }

  if (hasAll) {
    let involved = actorsFromDepartments(topicDepartments);
    if (involved.length === 0) involved = buildResponsibilityActors(new Set());
    return { actors: uniqueActors(involved), topicDepartments, responsibilityQuery: false };
  }

  if (directActors.length === 0) {
    const leaders = buildResponsibilityActors(topicDepartments);
    if (leaders.length > 0) {
      const jarvina = agentBySlug.get("jarvina");
      return { actors: uniqueActors([jarvina, ...leaders]), topicDepartments, responsibilityQuery: false };
    }
  }

  return { actors: [], topicDepartments, responsibilityQuery: false };
}

function departmentText(deptId) {
  return DEPARTMENTS[deptId]?.label || "Area Geral";
}

function formatTopic(deptSet) {
  if (!deptSet.size) return "escopo geral da agencia";
  return Array.from(deptSet).map((deptId) => departmentText(deptId)).join(" + ");
}

function buildAgentReply(actor, message, topicDepartments, responsibilityQuery, index, total) {
  const topic = formatTopic(topicDepartments);
  const deptId = actor.departmentId || "direcao";
  const deptLabel = departmentText(deptId);
  const deptAction = DEPARTMENTS[deptId]?.action || "execucao operacional";

  if (responsibilityQuery) {
    const isLeader = actor.isChief || slugify(actor.name) === slugify(departmentLeaders.get(deptId) || "");
    if (isLeader) {
      return `(${index + 1}/${total}) Eu sou ${actor.name}, lider de ${deptLabel}. Para "${topic}" eu sou ponto focal e posso acionar o time agora.`;
    }
    const leader = departmentLeaders.get(deptId) || "Sanntiago";
    return `(${index + 1}/${total}) Sou ${actor.name} (${deptLabel}). O responsavel principal por esse tema e ${leader}.`;
  }

  if (actor.type === "ceo") {
    return `(${index + 1}/${total}) Sou Sanntiago, CEO. Para "${topic}" vamos priorizar resultado, definir dono e prazo nesta rodada.`;
  }

  if (/\bstatus\b|\bandamento\b|\bcomo esta\b/.test(String(message).toLowerCase())) {
    return `(${index + 1}/${total}) ${actor.name} aqui (${deptLabel}). Status da minha frente: ${deptAction}. Posso detalhar tarefas em seguida.`;
  }

  return `(${index + 1}/${total}) ${actor.name} respondendo por ${deptLabel}. Neste assunto, minha atuacao cobre ${deptAction}. Proximo passo: alinhar entrega e validar com o lider da area.`;
}

const CHAT_CONVERSATION_STORAGE_KEY = "agencia3d.chat.conversationId";
let chatConversationId = "";

function getStoredConversationId() {
  if (chatConversationId) return chatConversationId;
  try {
    const raw = localStorage.getItem(CHAT_CONVERSATION_STORAGE_KEY) || "";
    const clean = String(raw).trim();
    if (clean) {
      chatConversationId = clean;
      return clean;
    }
  } catch {}
  return "";
}

function setStoredConversationId(value) {
  const clean = String(value || "").trim();
  if (!clean) return;
  chatConversationId = clean;
  try {
    localStorage.setItem(CHAT_CONVERSATION_STORAGE_KEY, clean);
  } catch {}
}

async function runChatQueue() {
  if (chatQueueRunning) return;
  chatQueueRunning = true;
  while (chatQueue.length > 0) {
    const item = chatQueue.shift();
    const actor = item?.actor || null;
    const speaker = actor?.name || item?.speaker || "Agente";
    const text = typeof item?.text === "string"
      ? item.text
      : buildAgentReply(
        actor,
        item.message,
        item.topicDepartments,
        item.responsibilityQuery,
        item.index,
        item.total
      );

    await sleep(440);
    addChatMessage("agent", speaker, text);
    if (actor && actor.mesh) {
      showSpeechBubble(actor, text);
    }
    await sleep(460);
  }
  chatQueueRunning = false;
}

function enqueueAgentReplies(actors, message, topicDepartments, responsibilityQuery) {
  const unique = uniqueActors(actors);
  const total = unique.length;
  for (let i = 0; i < unique.length; i += 1) {
    chatQueue.push({
      actor: unique[i],
      message,
      topicDepartments,
      responsibilityQuery,
      index: i,
      total
    });
  }
  runChatQueue();
}

function enqueueBackendReplies(responses) {
  const list = Array.isArray(responses) ? responses : [];
  for (const response of list) {
    const agentSlug = slugify(response?.agent_slug || response?.agent_name || "");
    const actor = chatActorMap.get(agentSlug) || null;
    const speaker = String(response?.agent_name || actor?.name || "Agente");
    const text = String(response?.text || "").trim();
    if (!text) continue;
    chatQueue.push({
      actor,
      speaker,
      text
    });
  }
  runChatQueue();
}

function removeFollowOptionByName(name) {
  const target = String(name || "").trim();
  if (!target) return;
  const options = Array.from(followSelect.options || []);
  for (const option of options) {
    if (String(option.value || "").trim() === target) {
      followSelect.remove(option.index);
      break;
    }
  }
}

function removeAgentImmediatelyBySlug(slug, reason = "desligamento") {
  const targetSlug = slugify(slug || "");
  if (!targetSlug) return false;
  const agent = agentBySlug.get(targetSlug);
  if (!agent) return false;

  if (agent.bubbleTimer) {
    clearTimeout(agent.bubbleTimer);
    agent.bubbleTimer = null;
  }
  if (agent.bubble) {
    agent.mesh.remove(agent.bubble);
    if (agent.bubble.material?.map) agent.bubble.material.map.dispose();
    agent.bubble.material?.dispose?.();
    agent.bubble = null;
  }

  world.remove(agent.mesh);
  const idx = agents.indexOf(agent);
  if (idx >= 0) agents.splice(idx, 1);
  agentBySlug.delete(targetSlug);
  agentByName.delete(agent.name);
  chatActorMap.delete(targetSlug);
  removeFollowOptionByName(agent.name);

  if (observer.follow === agent.name) {
    observer.follow = "";
    followSelect.value = "";
  }

  addEvent(`${agent.name} saiu da agencia imediatamente (${reason}).`);
  refreshMetrics();
  return true;
}

function applyBackendActions(actions) {
  const list = Array.isArray(actions) ? actions : [];
  if (!list.length) return;

  for (const action of list) {
    const type = String(action?.type || "").toLowerCase();
    const result = action?.result && typeof action.result === "object" ? action.result : {};
    if (type === "dismiss") {
      const dismissed = Array.isArray(result.dismissed) ? result.dismissed : [];
      let removed = 0;
      for (const item of dismissed) {
        const slug = String(item?.slug || item?.name || "").trim();
        if (removeAgentImmediatelyBySlug(slug, "demissao")) removed += 1;
      }
      if (removed > 0) {
        addEvent(`Demissao aplicada visualmente: ${removed} agente(s) removido(s) da sala.`);
      }
      continue;
    }

    if (type === "hire") {
      const hired = Array.isArray(result.hired) ? result.hired : [];
      const reactivated = Array.isArray(result.reactivated) ? result.reactivated : [];
      if (hired.length || reactivated.length) {
        addEvent("Cadastro de equipe atualizado no backend. Recarregue a pagina para redistribuir os novos assentos.");
      }
      continue;
    }

    if (type === "reactivate" || type === "promote" || type === "transfer") {
      addEvent(`Ordem '${type}' executada no backend. Recarregue a pagina para refletir toda a estrutura visual.`);
    }
  }
}

async function requestBackendChat(message) {
  const payload = {
    message,
    conversation_id: getStoredConversationId() || undefined,
    user_id: "local-user"
  };
  const response = await fetch("/api/agencia-chat", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });
  const json = await response.json().catch(() => ({}));
  if (!response.ok || !json?.ok) {
    const reason = json?.error || `HTTP ${response.status}`;
    throw new Error(reason);
  }
  if (json?.conversation_id) {
    setStoredConversationId(String(json.conversation_id));
  }
  return json;
}

function enqueueLocalFallback(message) {
  const { actors, topicDepartments, responsibilityQuery } = selectResponders(message);
  if (!actors.length) {
    addChatMessage("system", "Sistema", "Nao identifiquei o dono automaticamente. Use @todos ou @nomedoagente para direcionar.");
    return;
  }
  enqueueAgentReplies(actors, message, topicDepartments, responsibilityQuery);
}

async function handleChatSend(rawMessage) {
  const message = String(rawMessage || "").trim();
  if (!message) return;
  addChatMessage("user", "Voce", message);
  chatInput.value = "";

  try {
    const payload = await requestBackendChat(message);
    const responses = Array.isArray(payload?.responses) ? payload.responses : [];
    applyBackendActions(payload?.actions);
    if (payload?.preferred_name) {
      addEvent(`Memoria do chat ativa para: ${payload.preferred_name}.`);
    }
    if (responses.length === 0) {
      addChatMessage("system", "Sistema", "Backend ativo, mas sem resposta para esta rodada.");
      return;
    }
    enqueueBackendReplies(responses);
    return;
  } catch (error) {
    const detail = error?.message || "erro desconhecido";
    addChatMessage("system", "Sistema", `Falha no backend (${detail}). Ativando fallback local.`);
  }

  enqueueLocalFallback(message);
}

function bindChat() {
  document.getElementById("chatSend").addEventListener("click", () => handleChatSend(chatInput.value));
  chatInput.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      handleChatSend(chatInput.value);
    }
  });
  document.getElementById("chatAtAll").addEventListener("click", () => {
    chatInput.focus();
    if (!chatInput.value.trim()) chatInput.value = "@todos ";
    else if (!chatInput.value.includes("@todos")) chatInput.value = `@todos ${chatInput.value}`.trim();
  });
  document.getElementById("chatResponsavel").addEventListener("click", () => {
    chatInput.value = "Quem e o responsavel por isso?";
    handleChatSend(chatInput.value);
  });
}

function bindUI() {
  document.getElementById("btnConvocarCore").addEventListener("click", async () => {
    convokeVisual("core", "manual");
    await callBackend("core");
  });
  document.getElementById("btnConvocarAll").addEventListener("click", async () => {
    convokeVisual("all", "manual");
    await callBackend("all");
  });
  document.getElementById("btnEncerrar").addEventListener("click", () => endMeeting("manual"));
  document.getElementById("btnFocusOpen").addEventListener("click", () => focusZone("open"));
  document.getElementById("btnFocusMeeting").addEventListener("click", () => focusZone("meeting"));
  document.getElementById("btnFocusCeo").addEventListener("click", () => focusZone("ceo"));
  document.getElementById("btnCamFree").addEventListener("click", () => setCameraMode("free"));
  document.getElementById("btnCamTop").addEventListener("click", () => setCameraMode("top"));
  document.getElementById("btnCamOrbit").addEventListener("click", () => setCameraMode("orbit"));
  document.getElementById("btnCamMeeting").addEventListener("click", () => setCameraMode("meeting"));

  followSelect.addEventListener("change", () => {
    observer.follow = followSelect.value;
    if (observer.follow) {
      setCameraMode("free");
      addEvent(`Camera seguindo ${observer.follow}.`);
    } else {
      addEvent("Camera em modo livre.");
    }
  });

  btnLabels.addEventListener("click", () => {
    labelsVisible = !labelsVisible;
    for (const agent of agents) agent.label.visible = labelsVisible;
    if (ceoActor?.label) ceoActor.label.visible = labelsVisible;
    btnLabels.textContent = labelsVisible ? "Ocultar Nomes" : "Mostrar Nomes";
  });
}

function bindInput() {
  window.addEventListener("keydown", (event) => {
    const key = event.key.toLowerCase();
    if (key in observer.move) observer.move[key] = 1;
  });

  window.addEventListener("keyup", (event) => {
    const key = event.key.toLowerCase();
    if (key in observer.move) observer.move[key] = 0;
  });

  canvas.addEventListener("pointerdown", (event) => {
    pointer.active = true;
    pointer.x = event.clientX;
    pointer.y = event.clientY;
  });
  window.addEventListener("pointerup", () => {
    pointer.active = false;
  });
  window.addEventListener("pointermove", (event) => {
    if (!pointer.active || observer.mode !== "free") return;
    const dx = event.clientX - pointer.x;
    const dy = event.clientY - pointer.y;
    pointer.x = event.clientX;
    pointer.y = event.clientY;
    observer.yaw -= dx * 0.0045;
    observer.pitch = clamp(observer.pitch - dy * 0.0038, -1.35, 0.35);
  });

  canvas.addEventListener(
    "wheel",
    (event) => {
      if (observer.mode === "top") {
        observer.topHeight = clamp(observer.topHeight + event.deltaY * 0.06, 42, 240);
      } else {
        observer.zoom = clamp(observer.zoom + event.deltaY * 0.015, 8, 140);
      }
    },
    { passive: true }
  );

  window.addEventListener("resize", () => {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
  });
}

async function setAgentsFromRegistry() {
  const records = await readRegistryAgents();
  const assignments = assignAgents(records);

  followSelect.innerHTML = "<option value=\"\">Nenhum</option>";
  for (let i = 0; i < assignments.length; i += 1) {
    const assignment = assignments[i];
    const agent = createAgent(assignment, i);
    agents.push(agent);
    agentBySlug.set(agent.slug, agent);
    agentByName.set(agent.name, agent);
    chatActorMap.set(agent.slug, agent);

    const option = document.createElement("option");
    option.value = agent.name;
    option.textContent = agent.name;
    followSelect.appendChild(option);
  }

  const ceoOption = document.createElement("option");
  ceoOption.value = "Sanntiago";
  ceoOption.textContent = "Sanntiago (CEO)";
  followSelect.appendChild(ceoOption);

  addEvent(`Cenario pronto com ${agents.length} agentes + CEO.`);
  refreshMetrics();
}

function bootInitialMessages() {
  addChatMessage("system", "Sistema", "Chat transparente ativo. Use @todos ou @nomedoagente. Resposta em pt-BR, um por vez.");
  addChatMessage("system", "Sistema", "Quando perguntar responsabilidade, os lideres de departamento respondem automaticamente.");
  const conv = getStoredConversationId();
  if (conv) {
    addChatMessage("system", "Sistema", `Sessao anterior detectada (${conv}). Memoria de conversa habilitada.`);
  }
}

async function boot() {
  buildWorldBase();
  buildDeskArea();
  buildMeetingAndCeoFurniture();
  createCeoActor();
  buildWallClock();
  bindUI();
  bindInput();
  bindChat();
  setCameraMode("free");
  focusZone("open");

  addEvent("Inicializando cenario 3D...");
  await setAgentsFromRegistry();
  await syncAgentsWithHeartbeat();
  if (heartbeatTimer !== null) clearInterval(heartbeatTimer);
  heartbeatTimer = setInterval(() => {
    syncAgentsWithHeartbeat();
  }, HEARTBEAT_SYNC_MS);

  bootInitialMessages();
  addEvent("Pronto. Portas ativas e chat multiagente online.");
}

const clock = new THREE.Clock();

function loop() {
  requestAnimationFrame(loop);
  const dt = Math.min(clock.getDelta(), 0.045);
  const elapsed = clock.elapsedTime;
  updateObserver(dt);
  updateAgents(dt);
  updateCamera(dt, elapsed);
  updateWallClock(false);
  renderer.render(scene, camera);
}

boot();
loop();
