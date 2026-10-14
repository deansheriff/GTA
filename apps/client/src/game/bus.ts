/** Tiny typed event bus between the Phaser game and the Preact UI. */
export interface GameState {
  mode: 'walking' | 'driving';
  nearDanfo: boolean;
  night: boolean;
  nepaOn: boolean;
  fps: number;
  /** Shown as a toast, e.g. "UP NEPA!". Cleared by the UI. */
  toast?: string;
}

export interface Events {
  state: GameState;
  joystick: { x: number; y: number }; // screen-space, -1..1
  toggleNight: void;
  toggleNepa: void;
  enterExit: void;
}

type Handler<T> = (payload: T) => void;
const handlers: { [K in keyof Events]?: Set<Handler<Events[K]>> } = {};

export const bus = {
  on<K extends keyof Events>(k: K, h: Handler<Events[K]>) {
    (handlers[k] ??= new Set() as never).add(h as never);
    return () => handlers[k]!.delete(h as never);
  },
  emit<K extends keyof Events>(k: K, payload: Events[K]) {
    handlers[k]?.forEach((h) => (h as Handler<Events[K]>)(payload));
  },
};
