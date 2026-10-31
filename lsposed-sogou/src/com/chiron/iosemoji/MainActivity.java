package com.chiron.iosemoji;

import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.widget.Button;
import android.widget.ProgressBar;
import android.widget.TextView;

import java.text.SimpleDateFormat;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;

public class MainActivity extends Activity {

    private static final int MAX_LOG_LINES = 300;
    private static final long RESPONSE_TIMEOUT_MS = 4000L;

    private final ArrayDeque<String> logLines = new ArrayDeque<>();
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final SimpleDateFormat clock = new SimpleDateFormat("HH:mm:ss", Locale.US);

    private TextView statusView;
    private TextView logView;
    private ProgressBar bar;
    private Button btnAll;
    private Button btnCore;
    private Button btnRestore;
    private Button btnPing;

    private boolean receiverRegistered = false;
    private boolean awaitingResponse = false;
    private Runnable timeoutTask;

    private final BroadcastReceiver statusReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            if (intent == null) return;
            String phase = intent.getStringExtra(Protocol.EXTRA_PHASE);
            int current = intent.getIntExtra(Protocol.EXTRA_CURRENT, 0);
            int total = intent.getIntExtra(Protocol.EXTRA_TOTAL, 0);
            String message = intent.getStringExtra(Protocol.EXTRA_MESSAGE);

            awaitingResponse = false;
            if (timeoutTask != null) handler.removeCallbacks(timeoutTask);

            if (message != null) {
                statusView.setText(message);
                appendLog(message);
            }
            if (total > 0 && current > 0) {
                bar.setVisibility(View.VISIBLE);
                bar.setIndeterminate(false);
                bar.setMax(total);
                bar.setProgress(Math.min(current, total));
            } else if ("ready".equals(phase)) {
                bar.setVisibility(View.GONE);
                setBusy(false);
            } else if ("extract".equals(phase) || "commit".equals(phase)
                    || "restore".equals(phase)) {
                bar.setVisibility(View.VISIBLE);
                bar.setIndeterminate(true);
                setBusy(true);
            } else if ("done".equals(phase)) {
                bar.setVisibility(View.GONE);
                bar.setIndeterminate(false);
                setBusy(false);
                appendLog("搜狗输入法已重启，切回输入法查看效果");
            } else if ("error".equals(phase)) {
                bar.setVisibility(View.GONE);
                bar.setIndeterminate(false);
                setBusy(false);
            }
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        statusView = findViewById(R.id.status);
        logView = findViewById(R.id.log);
        bar = findViewById(R.id.bar);
        btnAll = findViewById(R.id.btn_all);
        btnCore = findViewById(R.id.btn_core);
        btnRestore = findViewById(R.id.btn_restore);
        btnPing = findViewById(R.id.btn_ping);

        btnAll.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                run(Protocol.CMD_INSTALL_ALL, "安装全部 10 组");
            }
        });
        btnCore.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                run(Protocol.CMD_INSTALL_CORE, "只装 黄脸 / 符号 / 旗帜");
            }
        });
        btnRestore.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                run(Protocol.CMD_RESTORE, "还原成安装前");
            }
        });
        btnPing.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                ping(true);
            }
        });

        logView.setText("等待连接…");
    }

    @Override
    protected void onStart() {
        super.onStart();
        IntentFilter filter = new IntentFilter(Protocol.ACTION_STATUS);
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                registerReceiver(statusReceiver, filter, Context.RECEIVER_EXPORTED);
            } else {
                registerReceiver(statusReceiver, filter);
            }
            receiverRegistered = true;
        } catch (Throwable ignored) {
            receiverRegistered = false;
        }
        ping(false);
    }

    @Override
    protected void onStop() {
        super.onStop();
        if (receiverRegistered) {
            try {
                unregisterReceiver(statusReceiver);
            } catch (Throwable ignored) {
            }
            receiverRegistered = false;
        }
        if (timeoutTask != null) handler.removeCallbacks(timeoutTask);
    }

    private void run(String cmd, String label) {
        appendLog("→ " + label);
        boolean sent = sendCommand(cmd);
        if (!sent) {
            statusView.setText("没找到搜狗输入法（小米渠道包或通用包）");
            return;
        }
        bar.setVisibility(View.VISIBLE);
        bar.setIndeterminate(true);
        setBusy(true);
        awaitingResponse = true;
        if (timeoutTask != null) handler.removeCallbacks(timeoutTask);
        timeoutTask = new Runnable() {
            @Override
            public void run() {
                if (!awaitingResponse) return;
                bar.setVisibility(View.GONE);
                setBusy(false);
                statusView.setText("没有收到响应。请确认：LSPosed 已启用本模块、作用域勾选了「搜狗输入法」，"
                        + "并且刚才切到输入法打过字（让搜狗进程先启动）");
                appendLog("超时：搜狗进程里没有 Hook 在监听");
            }
        };
        handler.postDelayed(timeoutTask, RESPONSE_TIMEOUT_MS);
    }

    private void ping(boolean manual) {
        if (sendCommand(Protocol.CMD_PING)) {
            if (manual) {
                statusView.setText("正在检测…");
                appendLog("→ 检查连接");
            }
            awaitingResponse = true;
            if (timeoutTask != null) handler.removeCallbacks(timeoutTask);
            timeoutTask = new Runnable() {
                @Override
                public void run() {
                    if (!awaitingResponse) return;
                    setBusy(false);
                    statusView.setText("未连接。LSPosed 里启用模块并勾选搜狗输入法作用域，"
                            + "然后切到搜狗打一次字，再回来点这里");
                    appendLog("未连接：Hook 没有应答");
                }
            };
            handler.postDelayed(timeoutTask, RESPONSE_TIMEOUT_MS);
        } else if (manual) {
            statusView.setText("没找到搜狗输入法（小米渠道包或通用包）");
        }
    }

    private boolean sendCommand(String cmd) {
        List<String> targets = installedTargets();
        if (targets.isEmpty()) return false;
        for (String pkg : targets) {
            Intent intent = new Intent(Protocol.ACTION_CMD)
                    .setPackage(pkg)
                    .putExtra(Protocol.EXTRA_CMD, cmd);
            try {
                sendBroadcast(intent);
            } catch (Throwable t) {
                appendLog("发送失败：" + pkg + " " + t.getMessage());
            }
        }
        return true;
    }

    private List<String> installedTargets() {
        List<String> found = new ArrayList<>();
        PackageManager pm = getPackageManager();
        for (String pkg : Protocol.TARGETS) {
            try {
                pm.getPackageInfo(pkg, 0);
                found.add(pkg);
            } catch (PackageManager.NameNotFoundException ignored) {
            }
        }
        return found;
    }

    private void setBusy(boolean busy) {
        btnAll.setEnabled(!busy);
        btnCore.setEnabled(!busy);
        btnRestore.setEnabled(!busy);
    }

    private void appendLog(String line) {
        logLines.addLast(clock.format(new Date()) + "  " + line);
        while (logLines.size() > MAX_LOG_LINES) logLines.removeFirst();
        StringBuilder sb = new StringBuilder();
        for (String s : logLines) sb.append(s).append('\n');
        logView.setText(sb.toString());
    }
}
