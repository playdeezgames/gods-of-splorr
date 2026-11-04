// Takes the player's guide screenshots (manual/img/*.png) from build/web, driving headless Chrome over
// the DevTools protocol. Run `./build.sh` first, then: node manual/screenshots.mjs
import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const WEB = join(HERE, "..", "build", "web");
const IMG = join(HERE, "img");
const HTTP_PORT = 8765, CDP_PORT = 9333;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const server = spawn("python3", ["-m", "http.server", "-d", WEB, String(HTTP_PORT)], { stdio: "ignore" });
const chrome = spawn("google-chrome", ["--headless", "--no-sandbox", "--disable-gpu", "--hide-scrollbars",
  `--remote-debugging-port=${CDP_PORT}`, "--window-size=1600,930", "about:blank"], { stdio: "ignore" });

async function connect() {
  for (let i = 0; i < 50; i++) {
    try {
      const pages = await (await fetch(`http://127.0.0.1:${CDP_PORT}/json`)).json();
      const page = pages.find((p) => p.type === "page");
      if (page) return new WebSocket(page.webSocketDebuggerUrl);
    } catch {}
    await sleep(200);
  }
  throw new Error("Chrome did not start");
}

let ws, nextId = 1;
const pending = new Map();
const send = (method, params = {}) => new Promise((resolve, reject) => {
  const id = nextId++;
  pending.set(id, { resolve, reject });
  ws.send(JSON.stringify({ id, method, params }));
});
const run = async (js) => {
  const r = await send("Runtime.evaluate", { expression: js, awaitPromise: true, returnByValue: true });
  if (r.exceptionDetails) throw new Error(`${js}: ${r.exceptionDetails.text}`);
  return r.result.value;
};
const shot = async (name) => {
  const { data } = await send("Page.captureScreenshot", { format: "png" });
  writeFileSync(join(IMG, name), Buffer.from(data, "base64"));
  console.log(join(IMG, name));
};
// Let the game run until the clock panel reads at least this date and hour.
const runUntil = async (year, month, day, hour = 0) => {
  const goal = ((year * 100 + month) * 100 + day) * 100 + hour;
  for (let i = 0; i < 4000; i++) {
    const [, y, m, d, h] = (await run(`document.getElementById("clock").textContent`)).match(/Year (\d+), Month (\d+), Day (\d+)\n(\d+)/).map(Number);
    if (((y * 100 + m) * 100 + d) * 100 + h >= goal) return;
    await sleep(100);
  }
  throw new Error("the clock did not get there");
};
// Fast-forward to the start of a day, then go on at normal speed to the hour, so the shot lands on time.
const goTo = async (year, month, day, hour) => {
  for (let i = 0; i < 8; i++) await run(`game().on_speed(1)`);
  await runUntil(year, month, day);
  for (let i = 0; i < 8; i++) await run(`game().on_speed(-1)`);
  for (let i = 0; i < 2; i++) await run(`game().on_speed(1)`); // 1x
  await runUntil(year, month, day, hour);
  await run(`game().on_pause()`);
};

try {
  mkdirSync(IMG, { recursive: true });
  ws = await connect();
  await new Promise((r) => ws.addEventListener("open", r));
  ws.addEventListener("message", (e) => {
    const msg = JSON.parse(e.data);
    if (msg.id && pending.has(msg.id)) {
      const { resolve, reject } = pending.get(msg.id);
      pending.delete(msg.id);
      msg.error ? reject(new Error(msg.error.message)) : resolve(msg.result);
    }
  });
  await send("Page.enable");
  await send("Emulation.setDeviceMetricsOverride", { width: 1600, height: 930, deviceScaleFactor: 1, mobile: false });
  // A short day (10 real seconds) so the year passes in a couple of minutes. Each run is a new world.
  await send("Page.navigate", { url: `http://127.0.0.1:${HTTP_PORT}/?day=10` });
  await sleep(2000);
  await run(`(async () => { for (let i = 0; i < 10 && !window.memory?.exports?.on_speed; i++) await new Promise(r => setTimeout(r, 200)); })()`);
  await sleep(1000);

  // Early summer: follow someone so the status panel describes them.
  await goTo(1, 3, 20, 12);
  await run(`game().on_follow_next()`);
  await sleep(400);
  await shot("summer.png");

  // A miracle armed: the button lights up and a click on the map casts it.
  await run(`game().on_arm(4)`);
  await sleep(300);
  await shot("armed.png");
  await run(`game().on_disarm()`);

  // Deep winter at the camp: a lit fire, racks of dried food, people in coats.
  await run(`game().on_pause()`);
  await goTo(1, 10, 15, 12);
  await run(`game().on_follow_next()`);
  await sleep(400);
  await shot("winter.png");

  // The menu, with the controls.
  await run(`document.getElementById("menu-btn").click()`);
  await sleep(300);
  await shot("menu.png");
} finally {
  ws?.close();
  chrome.kill();
  server.kill();
}
