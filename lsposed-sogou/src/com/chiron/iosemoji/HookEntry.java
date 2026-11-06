package com.chiron.iosemoji;

import android.app.Application;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import java.util.concurrent.atomic.AtomicBoolean;

import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.XposedHelpers;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

/**
 * LSPosed 入口。只在搜狗输入法进程里挂一个钩子，拿到它自己的 Context，
 * 之后所有文件读写都以搜狗的身份进行，因此不需要 root，也没有 SELinux 问题。
 */
public class HookEntry implements IXposedHookLoadPackage {

    private static final String TAG = "IOSEmoji";
    private static final AtomicBoolean ATTACHED = new AtomicBoolean(false);

    @Override
    public void handleLoadPackage(XC_LoadPackage.LoadPackageParam lpparam) throws Throwable {
        if (lpparam == null || !Protocol.isTarget(lpparam.packageName)) return;

        XposedBridge.log(TAG + ": hooked " + lpparam.packageName
                + " process=" + lpparam.processName);

        // 面板手势与文件安装互不依赖，先装手势钩子，失败也不影响安装
        try {
            GestureHook.install(lpparam.classLoader);
        } catch (Throwable t) {
            XposedBridge.log(t);
        }

        // 屏蔽「组合」「拼装」两个内置分组，需要 ExpressionUtil 已加载，
        // 这里先试一次，后面再靠 Application.attach 兜底。
        try {
            GroupFilterHook.install(lpparam.classLoader);
        } catch (Throwable t) {
            XposedBridge.log(t);
        }

        // 输入「苹果」/「pg」上屏成 U+F8FF。不依赖搜狗任何私有类，
        // 挂的是 framework 的 InputMethodService，越早越好。
        try {
            LogoHook.install();
        } catch (Throwable t) {
            XposedBridge.log(t);
        }

        try {
            XposedHelpers.findAndHookMethod(
                    Application.class,
                    "attach",
                    Context.class,
                    new XC_MethodHook() {
                        @Override
                        protected void afterHookedMethod(MethodHookParam param) {
                            try {
                                Object arg = param.args[0];
                                if (!(arg instanceof Context)) return;
                                Context ctx = (Context) arg;
                                if (!Protocol.isTarget(ctx.getPackageName())) return;
                                if (!ATTACHED.compareAndSet(false, true)) return;
                                try {
                                    GestureHook.install(ctx.getClassLoader());
                                } catch (Throwable t) {
                                    XposedBridge.log(t);
                                }
                                scheduleGroupFilter(ctx);
                                try {
                                    LogoHook.install();
                                } catch (Throwable t) {
                                    XposedBridge.log(t);
                                }
                                EmojiService.register(ctx);
                            } catch (Throwable t) {
                                XposedBridge.log(t);
                            }
                        }
                    });
        } catch (Throwable t) {
            XposedBridge.log(TAG + ": hook failed");
            XposedBridge.log(t);
            Log.e(TAG, "hook failed", t);
        }
    }

    /**
     * ExpressionUtil 在进程很早的阶段不一定已经加载，错开几个时间点补挂。
     * install() 自己幂等，装好之后每次都是一次布尔判断。
     */
    private static void scheduleGroupFilter(Context ctx) {
        final ClassLoader cl = ctx.getClassLoader();
        try {
            Handler handler = new Handler(Looper.getMainLooper());
            for (final long delay : new long[]{0L, 300L, 1200L, 3000L}) {
                handler.postDelayed(new Runnable() {
                    @Override
                    public void run() {
                        try {
                            GroupFilterHook.install(cl);
                        } catch (Throwable t) {
                            XposedBridge.log(t);
                        }
                    }
                }, delay);
            }
        } catch (Throwable t) {
            XposedBridge.log(t);
        }
    }
}
