import Phaser from 'phaser';
import { TIER_SCALE, type GraphicsSettings } from '@nsl/shared';
import { graphics } from '../../settings/graphics';
import { bus, type GameState } from '../bus';
import { HALF_H, HALF_W, TILE_W, headingToDir, tileToWorld } from '../art/iso';
import { drawBuilding, drawTile, type TileKind } from '../art/tiles';
import { drawGenerator, drawPalm, drawPole, drawUmbrella } from '../art/props';
import { DANFO, drawVehicle } from '../art/vehicles';
import { CHAR_DIRS, FRAME_H, FRAME_W, TUNDE, WALK_FRAMES, drawCharacterSheet, randomLook } from '../art/characters';
import { makeCanvas } from '../art/paint';
import { CHUNK, MAP_SIZE, buildYaba, isRoad, type WorldData } from '../world/yaba';

interface Walker {
  sprite: Phaser.GameObjects.Sprite;
  shadowless?: boolean;
  tx: number;
  ty: number;
  target?: { tx: number; ty: number };
  speed: number; // tiles / second
  sheet: string;
  dirRow: number;
  animT: number;
  idleT: number;
}

const TILE_VARIANTS = 3;

/** M0 style test: one painted Yaba junction you can walk and drive around. */
export class StreetScene extends Phaser.Scene {
  private world!: WorldData;
  private s = 1; // texture scale for the current tier
  private settings!: GraphicsSettings;
  private chunkLayers: Phaser.GameObjects.Container[][] = [];
  private player!: Walker;
  private npcs: Walker[] = [];
  private danfo!: { sprite: Phaser.GameObjects.Image; tx: number; ty: number; heading: number; speed: number };
  private mode: GameState['mode'] = 'walking';
  private night = false;
  private nepaOn = true;
  private overlay?: Phaser.GameObjects.Image;
  private smoke: Phaser.GameObjects.Particles.ParticleEmitter[] = [];
  private keys!: Record<'up' | 'down' | 'left' | 'right' | 'w' | 'a' | 's' | 'd' | 'e', Phaser.Input.Keyboard.Key>;
  private joy = { x: 0, y: 0 };
  private outageTimer = 0;
  private stateTimer = 0;
  /** Frames actually updated (loop.actualFps reports the display refresh rate, not the capped rate). */
  private frameCount = 0;
  private fpsWindow = 0;
  private fps = 0;
  private toast?: string;
  private unsubs: Array<() => void> = [];

  constructor() {
    super('street');
  }

  create(): void {
    this.settings = graphics.get();
    this.s = TIER_SCALE[this.settings.textureTier];
    this.world = buildYaba();
    this.makeTextures();
    this.buildGround();
    this.buildObjects();
    this.spawnPlayerAndDanfo();
    this.spawnNpcs();
    this.setupCamera();
    this.setupInput();
    this.applySettings(this.settings, true);
    this.redrawOverlay();

    this.unsubs.push(
      graphics.subscribe((next) => {
        // Texture tier changes need regenerated art: restart the scene. Everything else applies live.
        if (TIER_SCALE[next.textureTier] !== this.s) this.scene.restart();
        else this.applySettings(next, false);
      }),
      bus.on('joystick', (v) => (this.joy = v)),
      bus.on('toggleNight', () => { this.night = !this.night; this.redrawOverlay(); this.pushState(); }),
      bus.on('toggleNepa', () => this.setNepa(!this.nepaOn)),
      bus.on('enterExit', () => this.enterExit()),
    );
    this.events.once(Phaser.Scenes.Events.SHUTDOWN, () => { this.unsubs.forEach((u) => u()); this.unsubs = []; this.npcs = []; this.smoke = []; this.chunkLayers = []; });
    document.getElementById('boot')?.remove();
    this.pushState();
  }

  // ---------- art ----------

  private addCanvasTexture(key: string, canvas: HTMLCanvasElement): void {
    if (this.textures.exists(key)) this.textures.remove(key);
    this.textures.addCanvas(key, canvas);
  }

  private makeTextures(): void {
    const s = this.s;
    const kinds: TileKind[] = ['earth', 'grass', 'road_x', 'road_y', 'interlock', 'gutter_x', 'gutter_y'];
    for (const k of kinds) for (let v = 0; v < TILE_VARIANTS; v++) this.addCanvasTexture(`tile_${k}_${v}`, drawTile(k, v, s));
    for (let d = 0; d < 8; d++) {
      const v = drawVehicle(DANFO, d, s);
      this.addCanvasTexture(`danfo_${d}`, v.canvas);
      this.registry.set(`danfo_origin_${d}`, [v.originX, v.originY]);
    }
    this.addCharacterSheet('tunde', drawCharacterSheet(TUNDE, s));
    for (let i = 0; i < 8; i++) this.addCharacterSheet(`npc_${i}`, drawCharacterSheet(randomLook(900 + i * 17), s));
    const { c, g } = makeCanvas(16, 16);
    const grad = g.createRadialGradient(8, 8, 0, 8, 8, 8);
    grad.addColorStop(0, 'rgba(90,90,95,0.8)');
    grad.addColorStop(1, 'rgba(90,90,95,0)');
    g.fillStyle = grad; g.fillRect(0, 0, 16, 16);
    this.addCanvasTexture('smoke', c);
  }

  private addCharacterSheet(key: string, canvas: HTMLCanvasElement): void {
    this.addCanvasTexture(key, canvas);
    const tex = this.textures.get(key);
    const fw = FRAME_W * this.s, fh = FRAME_H * this.s;
    CHAR_DIRS.forEach((_, row) => {
      for (let f = 0; f < WALK_FRAMES; f++) tex.add(`${row}_${f}`, 0, f * fw, row * fh, fw, fh);
    });
  }

  // ---------- world ----------

  private buildGround(): void {
    const inv = 1 / this.s;
    const chunks = Math.ceil(MAP_SIZE / CHUNK);
    for (let cy = 0; cy < chunks; cy++) {
      this.chunkLayers.push([]);
      for (let cx = 0; cx < chunks; cx++) {
        const layer = this.add.container(0, 0).setDepth(-1e6);
        this.chunkLayers[cy]!.push(layer);
      }
    }
    for (let ty = 0; ty < MAP_SIZE; ty++) {
      for (let tx = 0; tx < MAP_SIZE; tx++) {
        const kind = this.world.tiles[ty]![tx]!;
        const v = (tx * 7 + ty * 13) % TILE_VARIANTS;
        const { x, y } = tileToWorld(tx, ty);
        // 2% overlap hides hairline seams between diamonds.
        const img = this.add.image(x, y + HALF_H, `tile_${kind}_${v}`).setOrigin(0.5, 0.5).setScale(inv * 1.02);
        this.chunkLayers[Math.floor(ty / CHUNK)]![Math.floor(tx / CHUNK)]!.add(img);
      }
    }
  }

  private buildObjects(): void {
    const inv = 1 / this.s;
    this.world.buildings.forEach((b, i) => {
      const art = drawBuilding({ a: b.a, b: b.b, h: b.h, wall: b.wall, sign: b.sign, seed: b.seed }, this.s);
      const key = `bld_${i}`;
      this.addCanvasTexture(key, art.canvas);
      const { x, y } = tileToWorld(b.tx, b.ty);
      // Depth: the front-most ground corner of the footprint.
      this.add.image(x, y, key).setOrigin(art.originX, art.originY).setScale(inv).setDepth(tileToWorld(b.tx + b.a, b.ty + b.b).y - 4);
    });
    this.world.props.forEach((p, i) => {
      const art =
        p.kind === 'umbrella' ? drawUmbrella(i % 2 ? ['#c0392b', '#f4f1e8'] : ['#1f6f8b', '#f2b705'], i % 2 ? 'KONFAM POS' : 'TAP-TAP POS', this.s, p.seed)
        : p.kind === 'pole' ? drawPole(this.s, false, p.seed)
        : p.kind === 'transformer' ? drawPole(this.s, true, p.seed)
        : p.kind === 'generator' ? drawGenerator(this.s, p.seed)
        : drawPalm(this.s, p.seed);
      const key = `prop_${i}`;
      this.addCanvasTexture(key, art.canvas);
      const { x, y } = tileToWorld(p.tx + 0.5, p.ty + 0.5);
      this.add.image(x, y, key).setOrigin(art.originX, art.originY).setScale(inv).setDepth(y);
      if (p.kind === 'generator') {
        const em = this.add.particles(x + 8, y - 22, 'smoke', {
          speed: { min: 6, max: 18 }, angle: { min: 250, max: 290 }, scale: { start: 0.6, end: 2.2 },
          alpha: { start: 0.55, end: 0 }, lifespan: 1800, frequency: 160, emitting: false,
        });
        em.setDepth(y + 1);
        this.smoke.push(em);
      }
    });
  }

  private spawnPlayerAndDanfo(): void {
    const inv = 1 / this.s;
    const ps = this.world.playerStart;
    this.player = this.makeWalker('tunde', ps.tx, ps.ty, 3.2);
    const ds = this.world.danfoStart;
    const dir = headingToDir(ds.heading);
    const [ox, oy] = this.registry.get(`danfo_origin_${dir}`) as [number, number];
    const { x, y } = tileToWorld(ds.tx, ds.ty);
    this.danfo = { sprite: this.add.image(x, y, `danfo_${dir}`).setOrigin(ox, oy).setScale(inv).setDepth(y), tx: ds.tx, ty: ds.ty, heading: ds.heading, speed: 0 };
  }

  private makeWalker(sheet: string, tx: number, ty: number, speed: number): Walker {
    const { x, y } = tileToWorld(tx, ty);
    const sprite = this.add.sprite(x, y, sheet, '0_0').setOrigin(0.5, (FRAME_H - 4) / FRAME_H).setScale(1 / this.s).setDepth(y);
    return { sprite, tx, ty, speed, sheet, dirRow: 0, animT: 0, idleT: 0 };
  }

  private spawnNpcs(): void {
    const want = Math.min(this.settings.maxOnScreenNpcs, 30);
    const r = new Phaser.Math.RandomDataGenerator(['nsl-npcs']);
    let tries = 0;
    while (this.npcs.length < want && tries++ < 500) {
      const tx = r.between(0, MAP_SIZE - 1), ty = r.between(0, MAP_SIZE - 1);
      const k = this.world.tiles[ty]![tx]!;
      if (this.world.blocked[ty]![tx] || isRoad(k)) continue;
      this.npcs.push(this.makeWalker(`npc_${this.npcs.length % 8}`, tx + 0.5, ty + 0.5, r.realInRange(0.9, 1.6)));
    }
  }

  private setupCamera(): void {
    const cam = this.cameras.main;
    const left = tileToWorld(0, MAP_SIZE).x, right = tileToWorld(MAP_SIZE, 0).x;
    cam.setBounds(left - TILE_W, -200, right - left + TILE_W * 2, MAP_SIZE * HALF_H * 2 + 400);
    cam.setBackgroundColor('#2b2350');
    const small = Math.min(this.scale.width, this.scale.height) < 500;
    cam.setZoom(small ? 0.75 : 1);
    cam.startFollow(this.player.sprite, false, 0.12, 0.12);
    this.input.on('wheel', (_p: unknown, _o: unknown, _dx: number, dy: number) => {
      cam.setZoom(Phaser.Math.Clamp(cam.zoom * (dy > 0 ? 0.9 : 1.1), 0.4, 2));
    });
  }

  private setupInput(): void {
    const kb = this.input.keyboard!;
    const K = Phaser.Input.Keyboard.KeyCodes;
    this.keys = {
      up: kb.addKey(K.UP), down: kb.addKey(K.DOWN), left: kb.addKey(K.LEFT), right: kb.addKey(K.RIGHT),
      w: kb.addKey(K.W), a: kb.addKey(K.A), s: kb.addKey(K.S), d: kb.addKey(K.D), e: kb.addKey(K.E),
    };
    this.keys.e.on('down', () => this.enterExit());
    // Tap / click to walk.
    this.input.on('pointerdown', (p: Phaser.Input.Pointer) => {
      if (this.mode !== 'walking') return;
      const wp = this.cameras.main.getWorldPoint(p.x, p.y);
      const tx = (wp.x / HALF_W + wp.y / HALF_H) / 2, ty = (wp.y / HALF_H - wp.x / HALF_W) / 2;
      if (this.walkable(tx, ty)) this.player.target = { tx, ty };
    });
  }

  // ---------- settings ----------

  private applySettings(next: GraphicsSettings, initial: boolean): void {
    this.settings = next;
    this.game.loop.setFPSLimit(next.fpsCap);
    for (const em of this.smoke) em.emitting = next.effects !== 'off' && (!this.nepaOn);
    if (!initial) this.redrawOverlay();
    this.cullChunks(true);
  }

  /** Draw distance: show only ground chunks within N chunks of the camera centre. */
  private lastChunk = '';
  private cullChunks(force = false): void {
    const cam = this.cameras.main;
    const cxw = cam.midPoint.x, cyw = cam.midPoint.y;
    const ctx = (cxw / HALF_W + cyw / HALF_H) / 2, cty = (cyw / HALF_H - cxw / HALF_W) / 2;
    const ccx = Math.floor(ctx / CHUNK), ccy = Math.floor(cty / CHUNK);
    const key = `${ccx},${ccy},${this.settings.drawDistance}`;
    if (!force && key === this.lastChunk) return;
    this.lastChunk = key;
    const dd = this.settings.drawDistance;
    this.chunkLayers.forEach((row, cy) => row.forEach((layer, cx) => layer.setVisible(Math.abs(cx - ccx) <= dd && Math.abs(cy - ccy) <= dd)));
  }

  // ---------- NEPA and lighting ----------

  private setNepa(on: boolean): void {
    if (on === this.nepaOn) return;
    this.nepaOn = on;
    this.toast = on ? 'UP NEPA! 💡' : 'NEPA don take light 🕯️';
    for (const em of this.smoke) em.emitting = !on && this.settings.effects !== 'off';
    this.redrawOverlay();
    this.pushState();
  }

  /**
   * Night and NEPA lighting as one low-res multiply overlay (cheap on phones).
   * Light pools: poles and windows when NEPA is on; only generator houses when it's off.
   */
  private redrawOverlay(): void {
    this.overlay?.destroy();
    this.overlay = undefined;
    if (!this.night && this.nepaOn) return;
    const scale = this.settings.nepaOverlay === 'full' ? 4 : 8;
    const left = tileToWorld(0, MAP_SIZE).x - TILE_W, right = tileToWorld(MAP_SIZE, 0).x + TILE_W;
    const top = -300, bottom = MAP_SIZE * HALF_H * 2 + 100;
    const { c, g } = makeCanvas((right - left) / scale, (bottom - top) / scale);
    const base = !this.night ? '#d9d3e6' : this.nepaOn ? '#4a4378' : '#231c40';
    g.fillStyle = base;
    g.fillRect(0, 0, c.width, c.height);
    const pool = (tx: number, ty: number, radius: number, colour: string) => {
      const { x, y } = tileToWorld(tx, ty);
      const px = (x - left) / scale, py = (y - top) / scale, r = radius / scale;
      const grad = g.createRadialGradient(px, py, 0, px, py, r);
      grad.addColorStop(0, colour);
      grad.addColorStop(1, base);
      g.fillStyle = grad;
      g.beginPath(); g.ellipse(px, py, r, r * 0.6, 0, 0, Math.PI * 2); g.fill();
    };
    if (this.night && this.nepaOn) {
      for (const p of this.world.props) if (p.kind === 'pole' || p.kind === 'transformer') pool(p.tx + 0.5, p.ty + 0.5, 260, '#fff1c4');
      for (const b of this.world.buildings) pool(b.tx + b.a / 2, b.ty + b.b + 0.3, 200, '#ffe6a8');
    } else {
      // Only generator owners have light. Everyone else: candles and phone torches.
      for (const b of this.world.buildings) if (b.generator) pool(b.tx + b.a / 2, b.ty + b.b + 0.3, 230, '#ffd98a');
    }
    this.addCanvasTexture('light_overlay', c);
    this.overlay = this.add.image(left, top, 'light_overlay').setOrigin(0, 0).setScale(scale).setDepth(1e7).setBlendMode(Phaser.BlendModes.MULTIPLY);
  }

  // ---------- movement ----------

  private walkable(tx: number, ty: number): boolean {
    const ix = Math.floor(tx), iy = Math.floor(ty);
    if (ix < 0 || iy < 0 || ix >= MAP_SIZE || iy >= MAP_SIZE) return false;
    return !this.world.blocked[iy]![ix];
  }

  private enterExit(): void {
    if (this.mode === 'driving') {
      if (Math.abs(this.danfo.speed) > 0.5) return;
      this.mode = 'walking';
      const side = this.danfo.heading + Math.PI / 2;
      const tx = this.danfo.tx + Math.cos(side) * 0.9, ty = this.danfo.ty + Math.sin(side) * 0.9;
      this.player.tx = this.walkable(tx, ty) ? tx : this.danfo.tx;
      this.player.ty = this.walkable(tx, ty) ? ty : this.danfo.ty;
      this.player.target = undefined;
      this.player.sprite.setVisible(true);
      this.cameras.main.startFollow(this.player.sprite, false, 0.12, 0.12);
    } else if (this.nearDanfo()) {
      this.mode = 'driving';
      this.player.sprite.setVisible(false);
      this.cameras.main.startFollow(this.danfo.sprite, false, 0.08, 0.08);
    }
    this.pushState();
  }

  private nearDanfo(): boolean {
    return Phaser.Math.Distance.Between(this.player.tx, this.player.ty, this.danfo.tx, this.danfo.ty) < 1.6;
  }

  /** Combined keyboard + joystick input as a screen-space vector, converted to tile space. */
  private inputVector(): { tx: number; ty: number; mag: number } {
    let sx = this.joy.x, sy = this.joy.y;
    const k = this.keys;
    if (k.left.isDown || k.a.isDown) sx -= 1;
    if (k.right.isDown || k.d.isDown) sx += 1;
    if (k.up.isDown || k.w.isDown) sy -= 1;
    if (k.down.isDown || k.s.isDown) sy += 1;
    const mag = Math.min(1, Math.hypot(sx, sy));
    if (mag < 0.15) return { tx: 0, ty: 0, mag: 0 };
    // Screen direction -> tile direction (inverse iso), then normalize.
    let tx = sx / HALF_W + sy / HALF_H, ty = sy / HALF_H - sx / HALF_W;
    const l = Math.hypot(tx, ty) || 1;
    tx /= l; ty /= l;
    return { tx, ty, mag };
  }

  private stepWalker(w: Walker, dt: number, dir: { tx: number; ty: number } | null): void {
    let mx = 0, my = 0;
    if (dir) { mx = dir.tx; my = dir.ty; }
    else if (w.target) {
      const dx = w.target.tx - w.tx, dy = w.target.ty - w.ty;
      const d = Math.hypot(dx, dy);
      if (d < 0.08) w.target = undefined;
      else { mx = dx / d; my = dy / d; }
    }
    const moving = mx !== 0 || my !== 0;
    if (moving) {
      const nx = w.tx + mx * w.speed * dt, ny = w.ty + my * w.speed * dt;
      if (this.walkable(nx, ny)) { w.tx = nx; w.ty = ny; }
      else if (this.walkable(nx, w.ty)) w.tx = nx;
      else if (this.walkable(w.tx, ny)) w.ty = ny;
      else w.target = undefined;
      // Screen-space facing: s, e, n, w rows.
      const sxv = (mx - my) * HALF_W, syv = (mx + my) * HALF_H;
      w.dirRow = Math.abs(sxv) > Math.abs(syv) * 1.2 ? (sxv > 0 ? 1 : 3) : syv > 0 ? 0 : 2;
      w.animT += dt * this.settings.npcAnimFps * (w === this.player ? 1 : 0.8) * 0.6;
    } else {
      w.animT = 0;
    }
    const frame = moving ? Math.floor(w.animT) % WALK_FRAMES : 0;
    const { x, y } = tileToWorld(w.tx, w.ty);
    w.sprite.setPosition(x, y).setDepth(y).setFrame(`${w.dirRow}_${frame}`);
  }

  private stepNpc(w: Walker, dt: number): void {
    if (!w.target) {
      w.idleT -= dt;
      if (w.idleT <= 0) {
        const tx = Phaser.Math.Clamp(w.tx + Phaser.Math.FloatBetween(-4, 4), 0.5, MAP_SIZE - 0.5);
        const ty = Phaser.Math.Clamp(w.ty + Phaser.Math.FloatBetween(-4, 4), 0.5, MAP_SIZE - 0.5);
        const k = this.world.tiles[Math.floor(ty)]![Math.floor(tx)]!;
        // NPCs stay off the road unless crossing at the junction.
        if (this.walkable(tx, ty) && !isRoad(k)) w.target = { tx, ty };
        w.idleT = Phaser.Math.FloatBetween(0.5, 3);
      }
    }
    this.stepWalker(w, dt, null);
  }

  private stepDanfo(dt: number): void {
    const d = this.danfo;
    const inp = this.mode === 'driving' ? this.inputVector() : { tx: 0, ty: 0, mag: 0 };
    const onRoad = isRoad(this.world.tiles[Math.floor(d.ty)]?.[Math.floor(d.tx)] ?? 'earth');
    const maxSpeed = onRoad ? 6.5 : 2.5; // off-road is bumpy go-slow
    if (inp.mag > 0) {
      const want = Math.atan2(inp.ty, inp.tx);
      const diff = Phaser.Math.Angle.Wrap(want - d.heading);
      const turnRate = 2.6 * Math.min(1, 0.3 + Math.abs(d.speed) / 3);
      d.heading += Phaser.Math.Clamp(diff, -turnRate * dt, turnRate * dt);
      const target = Math.abs(diff) > 2.4 ? -2 : maxSpeed * inp.mag;
      d.speed += Phaser.Math.Clamp(target - d.speed, -9 * dt, 4.5 * dt);
    } else {
      d.speed *= Math.pow(0.18, dt);
      if (Math.abs(d.speed) < 0.05) d.speed = 0;
    }
    if (d.speed > maxSpeed) d.speed += (maxSpeed - d.speed) * Math.min(1, 3 * dt);
    const nx = d.tx + Math.cos(d.heading) * d.speed * dt, ny = d.ty + Math.sin(d.heading) * d.speed * dt;
    // Check the bus front and centre against blocked tiles.
    const fx = nx + Math.cos(d.heading) * 0.7 * Math.sign(d.speed || 1), fy = ny + Math.sin(d.heading) * 0.7 * Math.sign(d.speed || 1);
    if (this.walkable(nx, ny) && this.walkable(fx, fy)) { d.tx = nx; d.ty = ny; }
    else if (Math.abs(d.speed) > 1.5) {
      d.speed = -d.speed * 0.3;
      if (!this.settings.reducedMotion) this.cameras.main.shake(140, 0.006);
      this.toast = 'Ehn! Who put wall there? 😤';
      this.pushState();
    } else d.speed = 0;

    const dir = headingToDir(d.heading);
    const [ox, oy] = this.registry.get(`danfo_origin_${dir}`) as [number, number];
    const { x, y } = tileToWorld(d.tx, d.ty);
    d.sprite.setTexture(`danfo_${dir}`).setOrigin(ox, oy).setPosition(x, y).setDepth(y + 1);
  }

  override update(_time: number, deltaMs: number): void {
    const dt = Math.min(deltaMs / 1000, 0.05);
    if (this.mode === 'walking') {
      const inp = this.inputVector();
      if (inp.mag > 0) this.player.target = undefined;
      this.stepWalker(this.player, dt, inp.mag > 0 ? inp : null);
    } else {
      this.player.tx = this.danfo.tx; this.player.ty = this.danfo.ty;
    }
    this.stepDanfo(dt);
    for (const n of this.npcs) this.stepNpc(n, dt);
    this.cullChunks();

    // Random NEPA cuts at night, like real life. Light returns after a while (sometimes).
    this.outageTimer -= dt;
    if (this.outageTimer <= 0) {
      this.outageTimer = Phaser.Math.FloatBetween(40, 90);
      if (this.night) this.setNepa(!this.nepaOn);
    }

    this.frameCount++;
    this.fpsWindow += deltaMs;
    if (this.fpsWindow >= 1000) { this.fps = Math.round((this.frameCount * 1000) / this.fpsWindow); this.frameCount = 0; this.fpsWindow = 0; }

    this.stateTimer -= dt;
    if (this.stateTimer <= 0) { this.stateTimer = 0.5; this.pushState(); }
  }

  private pushState(): void {
    const near = this.mode === 'walking' && this.nearDanfo();
    bus.emit('state', { mode: this.mode, nearDanfo: near, night: this.night, nepaOn: this.nepaOn, fps: this.fps, toast: this.toast });
    this.toast = undefined;
  }
}
