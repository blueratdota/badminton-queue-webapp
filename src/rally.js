// Stable per-court flights, shared with the finished iPad web frontend.
export function rallySeed(id) {
  let seed = 2166136261;
  for (const ch of id) seed = Math.imul(seed ^ ch.charCodeAt(0), 16777619) >>> 0;
  return seed;
}
export function rallyUnit(seed, shot, channel) {
  let x = (seed ^ Math.imul(shot + 1, 374761393) ^ Math.imul(channel + 1, 668265263)) >>> 0;
  x = Math.imul(x ^ x >>> 13, 1274126177) >>> 0;
  return ((x ^ x >>> 16) >>> 0) / 4294967295;
}
