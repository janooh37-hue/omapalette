.pragma library

// Palette helpers shared by the bar widget and its popup. The shell's Color
// singleton only exposes foreground/background/accent/muted/urgent, so the
// full theme palette is parsed straight out of the active theme's colors.toml.

var SWATCH_KEYS = ["red", "green", "yellow", "blue", "magenta", "cyan", "orange", "brown"];
var HEX_LINE = /^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/;

// --- contrast -------------------------------------------------------------
// Theme palettes are authored against their own background, so anything this
// widget paints on a *different* surface (a wallpaper preview, the bar island,
// the popup card) has to be re-checked or it renders invisible. Fixes stay
// hue-preserving: colours are only mixed toward white/black until they clear
// the WCAG ratio the surface needs.

function channels(value) {
  var text = String(value || "").trim().replace("#", "");
  if (text.length === 3)
    text = text[0] + text[0] + text[1] + text[1] + text[2] + text[2];
  if (text.length < 6)
    return null;
  var out = [];
  for (var i = 0; i < 3; i++) {
    var part = parseInt(text.substr(i * 2, 2), 16);
    if (isNaN(part))
      return null;
    out.push(part / 255);
  }
  return out;
}

function luminance(value) {
  var rgb = channels(value);
  if (!rgb)
    return 0;
  var lin = [];
  for (var i = 0; i < 3; i++)
    lin.push(rgb[i] <= 0.03928 ? rgb[i] / 12.92 : Math.pow((rgb[i] + 0.055) / 1.055, 2.4));
  return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2];
}

function contrast(a, b) {
  var la = luminance(a);
  var lb = luminance(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

function toHex(rgb) {
  var out = "#";
  for (var i = 0; i < 3; i++) {
    var part = Math.round(Math.max(0, Math.min(1, rgb[i])) * 255).toString(16);
    out += part.length < 2 ? "0" + part : part;
  }
  return out;
}

function mix(value, target, amount) {
  var a = channels(value);
  var b = channels(target);
  if (!a || !b)
    return value;
  var out = [];
  for (var i = 0; i < 3; i++)
    out.push(a[i] + (b[i] - a[i]) * amount);
  return toHex(out);
}

// Nudge `value` away from `surface` until it clears `minRatio`, keeping its
// hue. Falls back to plain black/white when the hue simply cannot get there.
function legible(value, surface, minRatio) {
  if (!channels(value) || !channels(surface))
    return value;
  var need = minRatio || 4.5;
  if (contrast(value, surface) >= need)
    return value;
  var target = luminance(surface) > 0.4 ? "#000000" : "#ffffff";
  for (var step = 1; step <= 10; step++) {
    var candidate = mix(value, target, step / 10);
    if (contrast(candidate, surface) >= need)
      return candidate;
  }
  return target;
}

// Swatches only need to be *seen*, not read, so they get a much lower bar than
// text — enough to survive a same-tone surface without repainting the palette.
function visible(value, surface) {
  return legible(value, surface, 1.9);
}

function visibleList(values, surface) {
  var out = [];
  if (!values)
    return out;
  for (var i = 0; i < values.length; i++)
    out.push(surface ? visible(values[i], surface) : values[i]);
  return out;
}

function parseColors(raw) {
  var colors = {};
  if (!raw)
    return colors;
  var lines = String(raw).split("\n");
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(HEX_LINE);
    if (match)
      colors[match[1]] = match[2];
  }
  return colors;
}

// Ordered accent swatches, ANSI-ish order, falling back to the few roles every
// theme is guaranteed to carry.
function swatches(colors, limit) {
  var picked = [];
  if (colors) {
    for (var i = 0; i < SWATCH_KEYS.length && picked.length < limit; i++) {
      var value = colors[SWATCH_KEYS[i]];
      if (value)
        picked.push(value);
    }
    if (!picked.length) {
      var roles = [colors.accent, colors.foreground, colors.muted];
      for (var r = 0; r < roles.length; r++)
        if (roles[r])
          picked.push(roles[r]);
    }
  }
  return picked;
}

function displayName(slug) {
  var text = String(slug || "").replace(/-/g, " ");
  return text.replace(/(^|\s)([a-z])/g, function (all, lead, letter) {
    return lead + letter.toUpperCase();
  });
}

function basename(path) {
  var text = String(path || "");
  var cut = text.lastIndexOf("/");
  return cut < 0 ? text : text.slice(cut + 1);
}

function firstPath(list) {
  return list && list.length && list[0] ? String(list[0].path) : "";
}
