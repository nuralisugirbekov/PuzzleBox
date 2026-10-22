package com.nurali.puzzlebox.games.kit

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** A dynamic or static (invMass == 0) circle. y grows downwards. */
class Ball(var x: Float, var y: Float, val r: Float, var tag: Int = 0, dynamic: Boolean = true) {
    var vx = 0f
    var vy = 0f
    var restitution = 0.12f
    var friction = 0.55f
    var damping = 0.3f
    var invMass = if (dynamic) 1f / (PI.toFloat() * r * r) else 0f
    var data: Any? = null
    var birth = 0.0
    var sensor = false      // reports contacts but does not collide
    var dead = false
}

/** A static line segment wall. */
class Seg(val x1: Float, val y1: Float, val x2: Float, val y2: Float, val restitution: Float = 0.2f, val friction: Float = 0.4f)

/**
 * A tiny impulse-based 2D physics world: circles against circles and static segments, with gravity,
 * damping, restitution and Coulomb friction (no rotation). Good enough for the casual games.
 */
class PhysWorld(var gravity: Float = 900f) {
    val balls = ArrayList<Ball>()
    val segs = ArrayList<Seg>()
    /** Ball-vs-ball pairs that touched during the last [step]. */
    val touching = ArrayList<Pair<Ball, Ball>>()
    var iterations = 4
    var maxSubstep = 1f / 180f

    fun add(b: Ball): Ball { balls.add(b); return b }

    fun wall(x1: Float, y1: Float, x2: Float, y2: Float, restitution: Float = 0.2f, friction: Float = 0.4f) {
        segs.add(Seg(x1, y1, x2, y2, restitution, friction))
    }

    fun box(x: Float, y: Float, w: Float, h: Float, restitution: Float = 0.2f, friction: Float = 0.4f) {
        wall(x, y, x + w, y, restitution, friction); wall(x + w, y, x + w, y + h, restitution, friction)
        wall(x + w, y + h, x, y + h, restitution, friction); wall(x, y + h, x, y, restitution, friction)
    }

    fun step(dt: Float) {
        touching.clear()
        val n = max(1, ceil(dt / maxSubstep).toInt())
        val h = dt / n
        repeat(n) { sub(h, it == n - 1) }
        balls.removeAll { it.dead }
    }

    private fun sub(h: Float, last: Boolean) {
        for (b in balls) if (b.invMass > 0f) {
            b.vy += gravity * h
            val damp = 1f / (1f + b.damping * h)
            b.vx *= damp; b.vy *= damp
            b.x += b.vx * h; b.y += b.vy * h
        }
        repeat(iterations) { iter ->
            for (b in balls) if (!b.sensor && b.invMass > 0f) for (s in segs) collideSeg(b, s)
            for (i in balls.indices) {
                val a = balls[i]
                for (j in i + 1 until balls.size) {
                    val b = balls[j]
                    collideBalls(a, b, last && iter == 0)
                }
            }
        }
    }

    private fun collideSeg(b: Ball, s: Seg) {
        val dx = s.x2 - s.x1; val dy = s.y2 - s.y1
        val len2 = dx * dx + dy * dy
        var t = if (len2 > 0f) ((b.x - s.x1) * dx + (b.y - s.y1) * dy) / len2 else 0f
        t = t.coerceIn(0f, 1f)
        val cx = s.x1 + dx * t; val cy = s.y1 + dy * t
        var nx = b.x - cx; var ny = b.y - cy
        val d2 = nx * nx + ny * ny
        if (d2 >= b.r * b.r) return
        val d = sqrt(d2)
        if (d > 1e-4f) { nx /= d; ny /= d } else { // centre exactly on the wall: push along the wall normal
            val l = sqrt(len2); nx = dy / l; ny = -dx / l
        }
        b.x += nx * (b.r - d); b.y += ny * (b.r - d)
        val vn = b.vx * nx + b.vy * ny
        if (vn < 0f) {
            val e = if (-vn > 40f) max(b.restitution, s.restitution * 0.5f).coerceAtMost(s.restitution.coerceAtLeast(b.restitution)) else 0f
            b.vx -= (1 + e) * vn * nx; b.vy -= (1 + e) * vn * ny
            // Tangential friction.
            val tx = -ny; val ty = nx
            val vt = b.vx * tx + b.vy * ty
            val mu = min(b.friction, s.friction + 0.2f)
            val jt = (-vt).coerceIn(-mu * abs(vn), mu * abs(vn))
            b.vx += jt * tx; b.vy += jt * ty
        }
    }

    private fun collideBalls(a: Ball, b: Ball, record: Boolean) {
        if (a.invMass == 0f && b.invMass == 0f) return
        val dx = b.x - a.x; val dy = b.y - a.y
        val rr = a.r + b.r
        val d2 = dx * dx + dy * dy
        if (d2 > (rr + 0.6f) * (rr + 0.6f)) return
        if (record) touching.add(a to b)
        if (a.sensor || b.sensor || d2 >= rr * rr) return
        val d = sqrt(d2)
        val nx: Float; val ny: Float
        if (d > 1e-4f) { nx = dx / d; ny = dy / d } else { nx = 0f; ny = 1f }
        val total = a.invMass + b.invMass
        val pen = rr - d
        a.x -= nx * pen * a.invMass / total; a.y -= ny * pen * a.invMass / total
        b.x += nx * pen * b.invMass / total; b.y += ny * pen * b.invMass / total
        val rvx = b.vx - a.vx; val rvy = b.vy - a.vy
        val vn = rvx * nx + rvy * ny
        if (vn < 0f) {
            val e = if (-vn > 40f) min(a.restitution, b.restitution) else 0f
            val j = -(1 + e) * vn / total
            a.vx -= j * nx * a.invMass; a.vy -= j * ny * a.invMass
            b.vx += j * nx * b.invMass; b.vy += j * ny * b.invMass
            val tx = -ny; val ty = nx
            val vt = rvx * tx + rvy * ty
            val mu = min(a.friction, b.friction)
            val jt = (-vt / total).coerceIn(-mu * abs(j), mu * abs(j))
            a.vx -= jt * tx * a.invMass; a.vy -= jt * ty * a.invMass
            b.vx += jt * tx * b.invMass; b.vy += jt * ty * b.invMass
        }
    }
}
