#!/usr/bin/env node
/**
 * Cuts art-src/raw/veh-sheet-2.png by hand-measured boxes (its top row has three vehicles, the
 * bottom four, so a grid cut is wrong). The sheet has no SUV: it is made from the car art,
 * darkened to a black SUV.   node tools/art/crop_vehicles2.mjs
 */
import sharp from 'sharp';

const SRC = 'art-src/raw/veh-sheet-2.png';
const OUT = 'game/art/vehicles/';
const BOXES = {
  truck: [10, 185, 445, 265, 270],
  tanker: [470, 205, 470, 240, 270],
  bus: [960, 195, 560, 255, 320],
  pickup: [25, 585, 430, 235, 230],
  taxi: [475, 615, 390, 195, 190],
  keke: [895, 595, 310, 215, 120],
  okada: [1235, 645, 260, 135, 90],
};
const CUT = 120;

for (const [name, [x, y, w, h, width]] of Object.entries(BOXES)) {
  const { data, info } = await sharp(SRC).extract({ left: x, top: y, width: w, height: h }).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  for (let i = 3; i < data.length; i += 4) data[i] = data[i] < CUT ? 0 : Math.min(255, Math.round(((data[i] - CUT) / (255 - CUT)) * 255 * 1.6));
  const png = await sharp(data, { raw: { width: info.width, height: info.height, channels: 4 } }).trim({ threshold: 1 }).png().toBuffer();
  await sharp(png).resize({ width }).png({ compressionLevel: 9 }).toFile(OUT + name + '.png');
  console.log(OUT + name + '.png');
}
// Black SUV from the car painting: darker, less colour, a touch longer.
const car = await sharp(OUT + 'car.png').metadata();
await sharp(OUT + 'car.png').modulate({ brightness: 0.42, saturation: 0.25 }).resize({ width: Math.round(car.width * 1.08), height: Math.round(car.height * 1.1), fit: 'fill' }).png().toFile(OUT + 'suv.png');
console.log(OUT + 'suv.png');
