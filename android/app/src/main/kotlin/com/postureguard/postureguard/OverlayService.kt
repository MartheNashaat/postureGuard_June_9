// android/app/src/main/kotlin/com/postureguard/postureguard/OverlayService.kt
package com.postureguard.postureguard

import android.app.Service
import android.content.Intent
import android.graphics.*
import android.os.Build
import android.util.Log  
import android.os.IBinder
import android.view.*
import android.widget.FrameLayout

class OverlayService : Service() {
    private lateinit var windowManager: WindowManager
    private lateinit var overlayView: View
    private var currentScore = 100
    private var currentStatus = "good"
    
    // Declare baseline variables at class level
    private var baselineNoseX = 0.5f
    private var baselineNoseY = 0.3f
    private var baselineLeftEarX = 0.35f
    private var baselineLeftEarY = 0.3f
    private var baselineRightEarX = 0.65f
    private var baselineRightEarY = 0.3f
    private var baselineLeftShoulderX = 0.35f
    private var baselineLeftShoulderY = 0.6f
    private var baselineRightShoulderX = 0.65f
    private var baselineRightShoulderY = 0.6f
    
    companion object {
        var instance: OverlayService? = null
        // Holds baseline sent before the service was started
        private var pendingBaseline: Map<String, Float>? = null

        fun updatePosture(score: Int, status: String) {
            instance?.updateOverlay(score, status)
        }

        fun updateBaseline(landmarks: Map<String, Float>) {
            Log.d("OverlayService", "Updating baseline with: $landmarks")
            pendingBaseline = landmarks
            instance?.setBaseline(landmarks)
        }

    }
    
    fun setBaseline(landmarks: Map<String, Float>) {
        Log.d("OverlayService", "setBaseline called with ${landmarks.size} landmarks")
        landmarks.forEach { (key, value) ->
            when (key) {
                // Flip X to match the mirrored front-camera preview
                "noseX"          -> baselineNoseX          = 1.0f - value
                "noseY"          -> baselineNoseY          = value
                "leftEarX"       -> baselineLeftEarX       = 1.0f - value
                "leftEarY"       -> baselineLeftEarY       = value
                "rightEarX"      -> baselineRightEarX      = 1.0f - value
                "rightEarY"      -> baselineRightEarY      = value
                "leftShoulderX"  -> baselineLeftShoulderX  = 1.0f - value
                "leftShoulderY"  -> baselineLeftShoulderY  = value
                "rightShoulderX" -> baselineRightShoulderX = 1.0f - value
                "rightShoulderY" -> baselineRightShoulderY = value
            }
        }
        if (::overlayView.isInitialized) {
            overlayView.invalidate()
        }
    }
    
    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createOverlayView()
        instance = this
        pendingBaseline?.let { setBaseline(it) }
    }
    
    private fun createOverlayView() {
        overlayView = object : View(this) {
            private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG)
            private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
            
            override fun onDraw(canvas: Canvas) {
                super.onDraw(canvas)

                val width = width.toFloat()
                val height = height.toFloat()

                // Convert normalized baseline coordinates to actual screen pixels
                val noseX = baselineNoseX * width
                val noseY = baselineNoseY * height
                val leftEarX = baselineLeftEarX * width
                val leftEarY = baselineLeftEarY * height
                val rightEarX = baselineRightEarX * width
                val rightEarY = baselineRightEarY * height
                val leftShoulderX = baselineLeftShoulderX * width
                val leftShoulderY = baselineLeftShoulderY * height
                val rightShoulderX = baselineRightShoulderX * width
                val rightShoulderY = baselineRightShoulderY * height
                
                // Annoying bright colors based on how bad posture is
                val mainColor = when {
                    currentScore >= 80 -> Color.parseColor("#40E0E0E0")  // Teal (mild)
                    currentScore >= 50 -> Color.parseColor("#FFFF4500")  // Bright Orange-Red
                    else -> Color.parseColor("#FFFF0000")  // Pure Red - VERY ANNOYING
                }
                
                val glowColor = when {
                    currentScore >= 80 -> Color.parseColor("#20E0E0E0")
                    currentScore >= 50 -> Color.parseColor("#80FF4500")
                    else -> Color.parseColor("#C0FF0000")  // Strong red glow
                }
                
                // EXTREMELY THICK LINES
                paint.color = mainColor
                paint.style = Paint.Style.STROKE
                paint.strokeWidth = when {
                    currentScore < 50 -> 32f
                    currentScore < 80 -> 24f
                    else -> 16f
                }
                paint.strokeCap = Paint.Cap.ROUND
                paint.strokeJoin = Paint.Join.ROUND
                
                // Glow paint
                glowPaint.color = glowColor
                glowPaint.style = Paint.Style.STROKE
                glowPaint.strokeWidth = paint.strokeWidth * 2.5f
                glowPaint.strokeCap = Paint.Cap.ROUND
                
                // Fill paint for joints
                fillPaint.color = mainColor
                fillPaint.style = Paint.Style.FILL
                
                // Draw GLOW first
                canvas.drawLine(leftEarX, leftEarY, noseX, noseY, glowPaint)
                canvas.drawLine(rightEarX, rightEarY, noseX, noseY, glowPaint)
                canvas.drawLine(leftShoulderX, leftShoulderY, rightShoulderX, rightShoulderY, glowPaint)
                
                val midX = (leftShoulderX + rightShoulderX) / 2
                val midY = (leftShoulderY + rightShoulderY) / 2
                canvas.drawLine(noseX, noseY, midX, midY, glowPaint)
                
                // Draw MAIN SKELETON
                canvas.drawLine(leftEarX, leftEarY, noseX, noseY, paint)
                canvas.drawLine(rightEarX, rightEarY, noseX, noseY, paint)
                canvas.drawLine(leftShoulderX, leftShoulderY, rightShoulderX, rightShoulderY, paint)
                canvas.drawLine(noseX, noseY, midX, midY, paint)
                
                // Draw JOINTS
                val jointSize = when {
                    currentScore < 50 -> 80f
                    currentScore < 80 -> 50f
                    else -> 30f
                }
                
                canvas.drawCircle(noseX, noseY, jointSize, fillPaint)
                canvas.drawCircle(leftEarX, leftEarY, jointSize * 0.7f, fillPaint)
                canvas.drawCircle(rightEarX, rightEarY, jointSize * 0.7f, fillPaint)
                canvas.drawCircle(leftShoulderX, leftShoulderY, jointSize, fillPaint)
                canvas.drawCircle(rightShoulderX, rightShoulderY, jointSize, fillPaint)
                
                // Draw TEXT
                val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    isFakeBoldText = true
                    textAlign = Paint.Align.CENTER
                }
                
                if (currentScore < 80) {
                    textPaint.textSize = when {
                        currentScore < 50 -> 120f
                        currentScore < 80 -> 80f
                        else -> 48f
                    }
                    textPaint.color = when {
                        currentScore >= 80 -> Color.parseColor("#E0E0E0")
                        currentScore >= 50 -> Color.parseColor("#FF4500")
                        else -> Color.parseColor("#FF0000")
                    }
                    
                    val scoreText = "${currentScore}%"
                    canvas.drawText(scoreText, width / 2, height * 0.15f, textPaint)
                    
                    if (currentScore < 70) {
                        textPaint.textSize = when {
                            currentScore < 40 -> 64f
                            else -> 48f
                        }
                        textPaint.color = Color.WHITE
                        
                        val warningText = when {
                            currentScore < 30 -> "⚠️ CRITICAL! FIX NOW! ⚠️"
                            currentScore < 50 -> "⚠️ BAD POSTURE! ADJUST! ⚠️"
                            else -> "⚠️ CORRECT YOUR POSTURE ⚠️"
                        }
                        canvas.drawText(warningText, width / 2, height * 0.25f, textPaint)
                        
                        textPaint.textSize = 32f
                        textPaint.color = Color.parseColor("#FFCC00")
                        canvas.drawText("MATCH THE GHOST OUTLINE!", width / 2, height * 0.35f, textPaint)
                    }
                }
            }
        }
        
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )
        
        windowManager.addView(overlayView, params)
    }
    
    fun updateOverlay(score: Int, status: String) {
        currentScore = score
        currentStatus = status
        if (::overlayView.isInitialized) {
            overlayView.invalidate()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        if (::overlayView.isInitialized) {
            windowManager.removeView(overlayView)
        }
        instance = null
    }
}