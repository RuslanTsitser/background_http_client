package com.tsitser.background_http_plugin.data.datasource

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

/**
 * ForegroundService for executing HTTP requests in the background.
 * This ensures requests continue even when app is in background on Android 15+.
 */
class HttpRequestForegroundService : Service() {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    
    companion object {
        private const val TAG = "HttpRequestForegroundService"
        private const val CHANNEL_ID = "background_http_client_channel"
        private const val NOTIFICATION_ID = 1
        const val ACTION_START = "com.tsitser.background_http_plugin.START"
        const val ACTION_STOP = "com.tsitser.background_http_plugin.STOP"
        const val EXTRA_REQUEST_ID = "request_id"
        
        private var isServiceRunning = false
        private val activeRequests = mutableSetOf<String>()
        
        fun isRunning(): Boolean = isServiceRunning
        
        @Synchronized
        fun addActiveRequest(requestId: String) {
            activeRequests.add(requestId)
            isServiceRunning = true
        }
        
        @Synchronized
        fun removeActiveRequest(requestId: String): Boolean {
            activeRequests.remove(requestId)
            isServiceRunning = activeRequests.isNotEmpty()
            return isServiceRunning
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        Log.d(TAG, "ForegroundService created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val requestId = intent.getStringExtra(EXTRA_REQUEST_ID)
                if (requestId != null) {
                    addActiveRequest(requestId)
                    startForeground(NOTIFICATION_ID, createNotification(requestId))
                    Log.d(TAG, "ForegroundService started for requestId: $requestId (active: ${activeRequests.size})")
                }
            }
            ACTION_STOP -> {
                val requestId = intent.getStringExtra(EXTRA_REQUEST_ID)
                if (requestId != null) {
                    val hasMoreRequests = removeActiveRequest(requestId)
                    Log.d(TAG, "Request $requestId completed (remaining: ${activeRequests.size})")
                    if (!hasMoreRequests) {
                        Log.d(TAG, "No more active requests, stopping service")
                        stopForeground(true)
                        stopSelf()
                    }
                }
            }
        }
        // Return START_NOT_STICKY to avoid restarting service if killed
        // WorkManager will handle retries
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?) = null

    override fun onDestroy() {
        super.onDestroy()
        activeRequests.clear()
        isServiceRunning = false
        serviceScope.cancel()
        Log.d(TAG, "ForegroundService destroyed")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Background HTTP Requests",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows notification when HTTP requests are being processed in background"
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(requestId: String): Notification {
        // Create a simple notification
        // In a real app, you might want to use the app's main activity as the intent
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Processing HTTP request")
            .setContentText("Request ID: ${requestId.take(20)}...")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setSilent(true) // Don't make sound
            .build()
    }
}
