package com.example.sign_language

import androidx.test.espresso.Espresso.onView
import androidx.test.espresso.assertion.ViewAssertions.matches
import androidx.test.espresso.matcher.ViewMatchers.isDisplayed
import androidx.test.espresso.matcher.ViewMatchers.isRoot
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MainActivityEspressoTest {
    @Test
    fun appLaunchesAndDisplaysRootView() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val activity = instrumentation.startActivitySync(intent)
        instrumentation.waitForIdleSync()

        onView(isRoot()).check(matches(isDisplayed()))
        activity.finish()
    }

    @Test
    fun flutterActivityRemainsResumedWithoutClosing() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val intent = Intent(instrumentation.targetContext, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val activity = instrumentation.startActivitySync(intent)
        instrumentation.waitForIdleSync()

        assertTrue("MainActivity should remain open", !activity.isFinishing && !activity.isDestroyed)
        assertTrue("Root decor view should be attached", activity.window.decorView.isAttachedToWindow)
        activity.finish()
    }

    @Test
    fun targetApplicationPackageIsInstalledOnDevice() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assertEquals("com.example.sign_language", context.packageName)
        assertTrue(context.packageManager.getLaunchIntentForPackage(context.packageName) != null)
    }
}
