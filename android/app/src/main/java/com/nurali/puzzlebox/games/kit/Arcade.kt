package com.nurali.puzzlebox.games.kit

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nurali.puzzlebox.core.L10n
import com.nurali.puzzlebox.game.GameEngine
import com.nurali.puzzlebox.game.GameState
import com.nurali.puzzlebox.ui.Pal
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

val ArenaColor = Color(0xFF111319)

/** HSB colour like SwiftUI's `Color(hue:saturation:brightness:)`; hue in 0..1. */
fun hsb(h: Double, s: Float, b: Float): Color = Color.hsv(((h % 1.0 + 1.0) % 1.0).toFloat() * 360f, s, b)

/** A mutable rectangle used by the arcade engines. */
class R(var x: Float, var y: Float, var w: Float, var h: Float) {
    val minX get() = x
    val maxX get() = x + w
    val minY get() = y
    val maxY get() = y + h
    val midX get() = x + w / 2
    val midY get() = y + h / 2
    fun intersects(o: R) = x < o.maxX && maxX > o.x && y < o.maxY && maxY > o.y
    fun copy() = R(x, y, w, h)
}

class P2(var x: Float, var y: Float)

fun rnd(a: Float, b: Float): Float = a + Random.nextFloat() * (b - a)
fun rnd(a: Double, b: Double): Double = a + Random.nextDouble() * (b - a)

/** An engine that is stepped once per frame by [ArcadeField]. */
interface FrameGame : GameEngine {
    fun advance(dt: Double)
}

// MARK: - Juice

class FxParticle(var x: Float, var y: Float, var vx: Float, var vy: Float, var life: Float, val maxLife: Float,
                 val size: Float, val color: Color, val gravity: Float)

class FxPopup(val text: String, var x: Float, var y: Float, var life: Float, val color: Color, val size: Float)

/** Particles, floating score popups, screen shake and a short flash, all in playfield coordinates. */
class ArcadeFX {
    val particles = ArrayList<FxParticle>()
    val popups = ArrayList<FxPopup>()
    var shake = 0f
    var flash = 0f
    var flashColor = Color.White
    private var clock = 0f

    fun reset() { particles.clear(); popups.clear(); shake = 0f; flash = 0f }

    fun burst(x: Float, y: Float, color: Color, count: Int = 12, speed: Float = 140f, gravity: Float = 320f,
              size: Float = 3f, life: Float = 0.6f, from: Float = 0f, to: Float = (2 * Math.PI).toFloat()) {
        val room = maxOf(0, 180 - particles.size)
        repeat(minOf(count, room)) {
            val a = rnd(from, to)
            val s = speed * rnd(0.35f, 1f)
            val l = life * rnd(0.6f, 1f)
            particles.add(FxParticle(x, y, cos(a) * s, sin(a) * s, l, l, size * rnd(0.6f, 1.3f), color, gravity))
        }
    }

    fun popup(text: String, x: Float, y: Float, color: Color = Color.White, size: Float = 16f) {
        if (popups.size >= 6) popups.removeAt(0)
        popups.add(FxPopup(text, x, y, 0.9f, color, size))
    }

    fun kick(amount: Float) { shake = maxOf(shake, amount) }

    fun flash(color: Color, amount: Float = 0.35f) { flashColor = color; flash = maxOf(flash, amount) }

    fun update(dt: Float) {
        clock += dt
        for (p in particles) { p.vy += p.gravity * dt; p.x += p.vx * dt; p.y += p.vy * dt; p.life -= dt }
        particles.removeAll { it.life <= 0 }
        for (p in popups) { p.y -= 42 * dt; p.life -= dt }
        popups.removeAll { it.life <= 0 }
        shake = maxOf(0f, shake - dt * (10 + shake * 7))
        flash = maxOf(0f, flash - dt * 1.6f)
    }

    fun shakeX() = if (shake > 0) sin(clock * 73) * shake else 0f
    fun shakeY() = if (shake > 0) cos(clock * 59) * shake * 0.7f else 0f

    fun draw(pen: Pen) {
        for (p in particles) pen.circle(p.x, p.y, p.size, p.color.copy(alpha = (p.life / p.maxLife).coerceIn(0f, 1f)))
        for (p in popups) {
            val t = p.life / 0.9f
            pen.label(p.text, p.x, p.y, p.size * (1 + maxOf(0f, t - 0.8f) * 2), p.color.copy(alpha = minOf(1f, t * 2.5f)))
        }
    }

    fun drawFlash(pen: Pen) {
        if (flash > 0) pen.box(-20f, -20f, 360f, 500f, flashColor.copy(alpha = minOf(0.45f, flash)), 0f)
    }
}

// MARK: - Drawing helpers

/** Small drawing toolkit over a scaled [DrawScope]; everything uses playfield coordinates. */
class Pen(val ds: DrawScope, private val tm: TextMeasurer) {
    fun circle(x: Float, y: Float, r: Float, color: Color, stroke: Float = 0f) {
        if (r <= 0f) return
        if (stroke > 0f) ds.drawCircle(color, r, Offset(x, y), style = Stroke(stroke)) else ds.drawCircle(color, r, Offset(x, y))
    }

    fun shiny(x: Float, y: Float, r: Float, light: Color, dark: Color) {
        if (r <= 0f) return
        ds.drawCircle(Brush.radialGradient(listOf(light, dark), Offset(x - r * 0.35f, y - r * 0.4f), r * 1.5f), r, Offset(x, y))
    }

    fun box(x: Float, y: Float, w: Float, h: Float, color: Color, radius: Float = 5f) {
        if (w <= 0f || h <= 0f) return
        ds.drawRoundRect(color, Offset(x, y), Size(w, h), CornerRadius(radius))
    }

    fun boxBrush(x: Float, y: Float, w: Float, h: Float, brush: Brush, radius: Float = 5f) {
        ds.drawRoundRect(brush, Offset(x, y), Size(w, h), CornerRadius(radius))
    }

    fun strokeBox(x: Float, y: Float, w: Float, h: Float, color: Color, width: Float, radius: Float = 5f) {
        ds.drawRoundRect(color, Offset(x, y), Size(w, h), CornerRadius(radius), style = Stroke(width))
    }

    fun line(x1: Float, y1: Float, x2: Float, y2: Float, color: Color, width: Float) {
        ds.drawLine(color, Offset(x1, y1), Offset(x2, y2), width, StrokeCap.Round)
    }

    fun polyline(points: List<Offset>, color: Color, width: Float) {
        if (points.size < 2) {
            points.firstOrNull()?.let { ds.drawCircle(color, width / 2f, it) }
            return
        }
        val path = androidx.compose.ui.graphics.Path().apply {
            moveTo(points[0].x, points[0].y)
            for (i in 1 until points.size) lineTo(points[i].x, points[i].y)
        }
        ds.drawPath(path, color, style = Stroke(width, cap = StrokeCap.Round, join = androidx.compose.ui.graphics.StrokeJoin.Round))
    }

    fun oval(x: Float, y: Float, w: Float, h: Float, color: Color) {
        ds.drawOval(color, Offset(x, y), Size(w, h))
    }

    fun strokeOval(x: Float, y: Float, w: Float, h: Float, color: Color, width: Float) {
        ds.drawOval(color, Offset(x, y), Size(w, h), style = Stroke(width))
    }

    /** Vertical two-colour rounded tile. */
    fun tile(x: Float, y: Float, w: Float, h: Float, top: Color, bottom: Color, radius: Float = 6f) {
        ds.drawRoundRect(Brush.verticalGradient(listOf(top, bottom), y, y + h), Offset(x, y), Size(w, h), CornerRadius(radius))
    }

    /** A glossy ball inside the given rectangle. */
    fun ball(x: Float, y: Float, w: Float, color: Color) {
        ds.drawCircle(
            Brush.radialGradient(listOf(Color.White.copy(alpha = 0.9f), color, color.copy(alpha = 0.75f)), Offset(x + w * 0.35f, y + w * 0.3f), w * 0.75f),
            w / 2f, Offset(x + w / 2f, y + w / 2f))
    }

    /** Runs [block] with a translate / rotate (radians) / uniform scale applied around the origin. */
    fun xf(tx: Float, ty: Float, rotRad: Float = 0f, scale: Float = 1f, block: () -> Unit) {
        ds.withTransform({
            translate(tx, ty)
            if (rotRad != 0f) rotate(Math.toDegrees(rotRad.toDouble()).toFloat(), Offset.Zero)
            if (scale != 1f) scale(scale, scale, Offset.Zero)
        }) { block() }
    }

    /** Fills a path built from [points] (closed). */
    fun polygon(points: List<Offset>, color: Color) {
        val path = androidx.compose.ui.graphics.Path().apply {
            moveTo(points[0].x, points[0].y)
            for (i in 1 until points.size) lineTo(points[i].x, points[i].y)
            close()
        }
        ds.drawPath(path, color)
    }

    fun label(text: String, x: Float, y: Float, size: Float, color: Color, weight: FontWeight = FontWeight.ExtraBold) {
        // The canvas is scaled to playfield units, so measure in raw units: px -> sp for this density.
        val style = TextStyle(color = color, fontSize = with(ds) { size.toSp() }, fontWeight = weight, fontFamily = FontFamily.SansSerif, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        val layout = tm.measure(text, style)
        ds.drawText(layout, topLeft = Offset(x - layout.size.width / 2f, y - layout.size.height / 2f))
    }
}

// MARK: - Field

/** Pointer events in playfield coordinates. */
open class FieldInput {
    open fun onDown(x: Float, y: Float) {}
    open fun onMove(x: Float, y: Float) {}
    /** [tapped] is true when the finger barely moved, like a tap. */
    open fun onUp(x: Float, y: Float, tapped: Boolean) {}
}

/**
 * The shared playfield: a fixed-aspect canvas in playfield units, stepped once per frame.
 * [draw] is called every frame; plain (non-snapshot) engine state is fine to read in it.
 */
@Composable
fun ArcadeField(
    engine: FrameGame,
    modifier: Modifier = Modifier,
    fieldW: Float = 320f,
    fieldH: Float = 460f,
    background: Color = ArenaColor,
    fx: ArcadeFX? = null,
    input: FieldInput = remember { FieldInput() },
    animated: Boolean = true,
    overlay: (@Composable () -> Unit)? = null,
    draw: Pen.() -> Unit,
) {
    var frame by remember { mutableIntStateOf(0) }
    val tm = rememberTextMeasurer()
    LaunchedEffect(engine, animated) {
        var last = 0L
        while (animated) {
            androidx.compose.runtime.withFrameNanos { now ->
                if (last != 0L) engine.advance(((now - last) / 1_000_000_000.0).coerceIn(0.0, 0.1))
                last = now
                frame++
            }
        }
    }
    Box(modifier.fillMaxWidth().aspectRatio(fieldW / fieldH).clip(RoundedCornerShape(24.dp)).background(background)) {
        Canvas(
            Modifier.fillMaxSize().pointerInput(input) {
                awaitEachGesture {
                    val down = awaitFirstDown()
                    val sx = fieldW / size.width; val sy = fieldH / size.height
                    input.onDown(down.position.x * sx, down.position.y * sy)
                    var last = down.position
                    var moved = 0f
                    while (true) {
                        val ev = awaitPointerEvent()
                        val c = ev.changes.firstOrNull() ?: break
                        last = c.position
                        moved = maxOf(moved, kotlin.math.abs(last.x - down.position.x), kotlin.math.abs(last.y - down.position.y))
                        c.consume()
                        if (!c.pressed) break
                        input.onMove(last.x * sx, last.y * sy)
                    }
                    input.onUp(last.x * sx, last.y * sy, moved < 20f * density)
                }
            },
        ) {
            @Suppress("UNUSED_EXPRESSION") frame
            val sx = size.width / fieldW; val sy = size.height / fieldH
            scale(sx, sy, pivot = Offset.Zero) {
                val pen = Pen(this, tm)
                translate(fx?.shakeX() ?: 0f, fx?.shakeY() ?: 0f) {
                    pen.draw()
                    fx?.draw(pen)
                    fx?.drawFlash(pen)
                }
            }
        }
        overlay?.invoke()
    }
}

/** Centered "Tap to start" prompt. */
@Composable
fun StartPrompt(text: String = L10n.t("Tap to start")) {
    val pal = Pal.current
    Box(Modifier.fillMaxWidth().aspectRatio(1.6f), contentAlignment = Alignment.Center) {
        Box(Modifier.clip(RoundedCornerShape(16.dp)).background(pal.background.copy(alpha = 0.9f)).padding(24.dp)) {
            Text(text, color = pal.accent, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
fun Hearts(lives: Int, max: Int) {
    Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        repeat(max) { i ->
            Text(if (i < lives) "❤" else "♡", color = if (i < lives) Color(0xFFFF2D55) else Pal.current.textSecondary, fontSize = 16.sp)
        }
    }
}

/** Steps a [FrameGame] once per display frame (for games that do not use [ArcadeField]). */
@Composable
fun FrameLoop(engine: FrameGame) {
    LaunchedEffect(engine) {
        var last = 0L
        while (true) {
            androidx.compose.runtime.withFrameNanos { now ->
                if (last != 0L) engine.advance(((now - last) / 1_000_000_000.0).coerceIn(0.0, 0.1))
                last = now
            }
        }
    }
}
