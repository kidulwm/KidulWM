# Peek black-glass border visibility fix

Session: 2026-07-15, target VM `bob-is-a-douche`, host repo branch `corner-bg-fix` @ `da2a384`.

## Symptom

Glass overlay was filling the full peek window shape and was so dark (top/bottom alpha 0.97) that the original border ring was invisible. The fallback background colour between glass and border was also not visible.

## Fix

Clip the glass to the **inner content shape** instead of the full outer window path:

```zig
const border: f64 = @max(1.0, @as(f64, style.border_width));
const depth: f64 = @max(0.0, @as(f64, style.corner_depth));
var inner_style = style;
inner_style.corner_depth = @max(@as(f32, 0.0), @as(f32, @floatCast(depth - border)));
windowPath(cr, border, border, w - border * 2.0, h - border * 2.0, inner_style);
c.cairo_clip(cr);
```

Draw order stays:
1. Glass clipped to inner content shape.
2. Border ring (outer path minus inner path) drawn on top of the glass in the original border colour.
3. Hidden-edge `DEST_OUT` trim unchanged.

## Result

The dark glass stops at the inside edge of the border ring, so the border and its background-colour band become fully visible while the glass remains behind it.

## When to use full-shape vs inner-shape clip

- **Translucent glass** (mid alpha ~0.45, not overwhelmingly dark): clip to the full outer `windowPath` so the glass reaches the border. The border ring shows through or sits cleanly on top.
- **Near-opaque glass** (top alpha 0.97, body so dark it hides the ring): clip to the inner content shape inset by `border_width`, otherwise the ring is swallowed.
