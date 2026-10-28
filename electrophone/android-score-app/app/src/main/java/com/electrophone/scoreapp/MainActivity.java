package com.electrophone.scoreapp;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.AlertDialog;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.text.method.ScrollingMovementMethod;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.GridLayout;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.ScrollView;
import android.widget.Spinner;
import android.widget.TextView;

import org.json.JSONException;

import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;

public final class MainActivity extends Activity {
    private static final String PREFS = "score_app";
    private static final String PREF_CATALOG_URL = "catalog_url_v2";
    private static final String PREF_PERFORMANCE_CONFIG = "performance_config";
    private static final String DEFAULT_CATALOG_URL =
            "https://1q2w3e-wed.github.io/electrophone-scores/catalog.json";
    private static final int REQUEST_BLUETOOTH_CONNECT = 2001;
    private static final int PAGE_SCORES = 0;
    private static final int PAGE_PERFORMANCE = 1;
    private static final int PAGE_RECORDING = 2;

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private final ScheduledExecutorService keyPoller =
            Executors.newSingleThreadScheduledExecutor();
    private final SppClient sppClient = new SppClient();
    private final Spinner[] mappingSpinners = new Spinner[8];
    private final Button[] remotePads = new Button[8];
    private final boolean[] remotePressed = new boolean[8];

    private EditText catalogUrlInput;
    private EditText searchInput;
    private TextView catalogStatus;
    private TextView deviceText;
    private TextView selectedTitle;
    private TextView scorePreview;
    private TextView statusText;
    private TextView protocolStatus;
    private TextView recordingStatus;
    private EditText recordingText;
    private TextView followTitle;
    private TextView followProgress;
    private TextView followExpected;
    private TextView followFeedback;
    private LinearLayout followGuidePanel;
    private ListView resultList;
    private LinearLayout scoresPage;
    private LinearLayout performancePage;
    private LinearLayout recordingPage;
    private Button scoresTabButton;
    private Button performanceTabButton;
    private Button recordingTabButton;
    private Button connectDeviceButton;
    private Button startRecordingButton;
    private Button performanceRecordButton;
    private Button editKeysButton;
    private Button testModeButton;
    private RadioGroup performanceModeGroup;
    private RadioButton freePlayRadio;
    private RadioButton followScoreRadio;

    private ScoreFetcher fetcher;
    private ScoreCatalog catalog;
    private ScoreCatalog.ScoreEntry selectedEntry;
    private ScoreValidator.Result currentScore;
    private BluetoothDevice selectedDevice;
    private List<ScoreCatalog.ScoreEntry> visibleEntries = new ArrayList<>();
    private ArrayAdapter<String> resultAdapter;
    private Runnable pendingBluetoothAction;
    private PerformanceConfig performanceConfig;
    private boolean connected;
    private boolean recording;
    private boolean editMode;
    private volatile boolean testMode;
    private boolean changingMode;
    private volatile boolean followMode;
    private volatile boolean pollInFlight;
    private volatile int remoteMask;
    private int followGeneration;
    private PracticeScore practiceScore;
    private FollowSession followSession;
    private ScheduledFuture<?> pollFuture;
    private int protocolVersion;
    private int currentPage = PAGE_SCORES;

    private interface BluetoothAction {
        void run() throws IOException;
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        fetcher = new ScoreFetcher(this);
        bindViews();
        setupResultList();
        setupTabs();
        setupMappingSpinners();
        setupRemotePads();
        loadPerformanceConfig();
        loadPreferences();
        bindActions();
        showPage(PAGE_SCORES);
        updateConnectionState(false, 0);
        updateRecordingUi();
    }

    private void bindViews() {
        catalogUrlInput = findViewById(R.id.catalogUrlInput);
        searchInput = findViewById(R.id.searchInput);
        catalogStatus = findViewById(R.id.catalogStatus);
        deviceText = findViewById(R.id.deviceText);
        selectedTitle = findViewById(R.id.selectedTitle);
        scorePreview = findViewById(R.id.scorePreview);
        scorePreview.setMovementMethod(new ScrollingMovementMethod());
        statusText = findViewById(R.id.statusText);
        protocolStatus = findViewById(R.id.protocolStatus);
        recordingStatus = findViewById(R.id.recordingStatus);
        recordingText = findViewById(R.id.recordingText);
        recordingText.setMovementMethod(new ScrollingMovementMethod());
        followGuidePanel = findViewById(R.id.followGuidePanel);
        followTitle = findViewById(R.id.followTitle);
        followProgress = findViewById(R.id.followProgress);
        followExpected = findViewById(R.id.followExpected);
        followFeedback = findViewById(R.id.followFeedback);
        performanceModeGroup = findViewById(R.id.performanceModeGroup);
        freePlayRadio = findViewById(R.id.freePlayRadio);
        followScoreRadio = findViewById(R.id.followScoreRadio);
        resultList = findViewById(R.id.resultList);
        scoresPage = findViewById(R.id.scoresPage);
        performancePage = findViewById(R.id.performancePage);
        recordingPage = findViewById(R.id.recordingPage);
        scoresTabButton = findViewById(R.id.tabScoresButton);
        performanceTabButton = findViewById(R.id.tabPerformanceButton);
        recordingTabButton = findViewById(R.id.tabRecordingButton);
        connectDeviceButton = findViewById(R.id.connectDeviceButton);
        startRecordingButton = findViewById(R.id.startRecordingButton);
        performanceRecordButton = findViewById(R.id.performanceRecordButton);
        editKeysButton = findViewById(R.id.editKeysButton);
        testModeButton = findViewById(R.id.testModeButton);

        GridLayout grid = findViewById(R.id.remotePadGrid);
        for (int index = 0; index < 8; index++) {
            int buttonId = getResources().getIdentifier(
                    "padButton" + index, "id", getPackageName());
            int spinnerId = getResources().getIdentifier(
                    "mapSpinner" + index, "id", getPackageName());
            remotePads[index] = grid.findViewById(buttonId);
            mappingSpinners[index] = findViewById(spinnerId);
        }
    }

    private void setupResultList() {
        resultAdapter = new ArrayAdapter<>(
                this, android.R.layout.simple_list_item_1, new ArrayList<>());
        resultList.setAdapter(resultAdapter);
        resultList.setOnItemClickListener((parent, view, position, id) -> {
            if (position < 0 || position >= visibleEntries.size()) {
                return;
            }
            selectedEntry = visibleEntries.get(position);
            selectedTitle.setText(selectedEntry.title);
            currentScore = null;
            scorePreview.setText("正在下载并校验…");
            loadSelectedScore(false);
        });
    }

    private void setupTabs() {
        scoresTabButton.setOnClickListener(view -> showPage(PAGE_SCORES));
        performanceTabButton.setOnClickListener(view -> showPage(PAGE_PERFORMANCE));
        recordingTabButton.setOnClickListener(view -> showPage(PAGE_RECORDING));
    }

    private void setupMappingSpinners() {
        ArrayAdapter<String> adapter = new ArrayAdapter<>(
                this, android.R.layout.simple_spinner_item);
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        for (int note = 0; note < 8; note++) {
            adapter.add("音符 " + note);
        }
        for (Spinner spinner : mappingSpinners) {
            spinner.setAdapter(adapter);
        }
    }

    private void setupRemotePads() {
        for (int index = 0; index < 8; index++) {
            final int padIndex = index;
            Button pad = remotePads[index];
            pad.setOnTouchListener((view, event) -> {
                if (editMode) {
                    return false;
                }
                if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
                    pressRemoteKey(padIndex);
                } else if (event.getActionMasked() == MotionEvent.ACTION_UP
                        || event.getActionMasked() == MotionEvent.ACTION_CANCEL) {
                    releaseRemoteKey(padIndex);
                }
                return false;
            });
            pad.setOnClickListener(view -> {
                if (editMode) {
                    showRemoteKeyDialog(padIndex);
                }
            });
        }
    }

    private void loadPreferences() {
        SharedPreferences preferences = getSharedPreferences(PREFS, MODE_PRIVATE);
        catalogUrlInput.setText(preferences.getString(
                PREF_CATALOG_URL, DEFAULT_CATALOG_URL));
        loadCatalog(catalogUrlInput.getText().toString());
    }

    private void loadPerformanceConfig() {
        SharedPreferences preferences = getSharedPreferences(PREFS, MODE_PRIVATE);
        String json = preferences.getString(PREF_PERFORMANCE_CONFIG, null);
        if (json == null) {
            performanceConfig = PerformanceConfig.defaults();
        } else {
            try {
                performanceConfig = PerformanceConfig.fromJson(json);
            } catch (JSONException | IllegalArgumentException error) {
                performanceConfig = PerformanceConfig.defaults();
                statusText.setText("琴键配置损坏，已恢复默认值");
            }
        }
        refreshMappingControls();
        refreshRemotePads();
    }

    private void bindActions() {
        Button loadCatalogButton = findViewById(R.id.loadCatalogButton);
        loadCatalogButton.setOnClickListener(
                view -> loadCatalog(catalogUrlInput.getText().toString()));
        Button searchButton = findViewById(R.id.searchButton);
        searchButton.setOnClickListener(view -> applySearch());
        Button selectDeviceButton = findViewById(R.id.selectDeviceButton);
        selectDeviceButton.setOnClickListener(
                view -> withBluetoothPermission(this::chooseBluetoothDevice));
        connectDeviceButton.setOnClickListener(view -> connectOrDisconnect());
        Button downloadButton = findViewById(R.id.downloadButton);
        downloadButton.setOnClickListener(view -> loadSelectedScore(true));
        Button copyButton = findViewById(R.id.copyButton);
        copyButton.setOnClickListener(view -> copyCurrentScore());
        Button sendButton = findViewById(R.id.sendButton);
        sendButton.setOnClickListener(view -> sendCurrentScore());
        Button applyMappingButton = findViewById(R.id.applyMappingButton);
        applyMappingButton.setOnClickListener(view -> applyPhysicalMapping());
        Button allUpButton = findViewById(R.id.allUpButton);
        allUpButton.setOnClickListener(view -> releaseAllRemoteKeys(true));
        editKeysButton.setOnClickListener(view -> toggleKeyEditMode());
        testModeButton.setOnClickListener(view -> toggleTestMode());
        performanceModeGroup.setOnCheckedChangeListener((group, checkedId) -> {
            if (changingMode) {
                return;
            }
            if (checkedId == R.id.followScoreRadio) {
                startFollowMode();
            } else {
                stopFollowMode(false, false);
            }
        });
        performanceRecordButton.setOnClickListener(view -> {
            if (recording) {
                showPage(PAGE_RECORDING);
            } else {
                confirmStartRecording();
            }
        });
        startRecordingButton.setOnClickListener(view -> confirmStartRecording());
        Button stopAndFetchButton = findViewById(R.id.stopAndFetchButton);
        stopAndFetchButton.setOnClickListener(view -> stopAndFetchRecording());
        Button replayRecordingButton = findViewById(R.id.replayRecordingButton);
        replayRecordingButton.setOnClickListener(view -> replayFpgaRecording());
        Button saveRecordingButton = findViewById(R.id.saveRecordingButton);
        saveRecordingButton.setOnClickListener(view -> saveRecording());
        Button copyRecordingButton = findViewById(R.id.copyRecordingButton);
        copyRecordingButton.setOnClickListener(view -> copyRecording());
        Button clearRecordingButton = findViewById(R.id.clearRecordingButton);
        clearRecordingButton.setOnClickListener(view -> confirmClearRecording());
        Button sendRecordingButton = findViewById(R.id.sendRecordingButton);
        sendRecordingButton.setOnClickListener(view -> sendEditedRecording());
    }

    private void showPage(int page) {
        if (page != PAGE_PERFORMANCE && currentPage == PAGE_PERFORMANCE) {
            releaseAllRemoteKeys(false);
            setKeyEditMode(false, false);
            stopFollowMode(true, false);
        }
        currentPage = page;
        scoresPage.setVisibility(page == PAGE_SCORES ? View.VISIBLE : View.GONE);
        performancePage.setVisibility(
                page == PAGE_PERFORMANCE ? View.VISIBLE : View.GONE);
        recordingPage.setVisibility(page == PAGE_RECORDING ? View.VISIBLE : View.GONE);
        styleTab(scoresTabButton, page == PAGE_SCORES);
        styleTab(performanceTabButton, page == PAGE_PERFORMANCE);
        styleTab(recordingTabButton, page == PAGE_RECORDING);
    }

    private void styleTab(Button button, boolean active) {
        int color = getColor(active ? R.color.navy : R.color.white);
        button.setBackgroundTintList(android.content.res.ColorStateList.valueOf(color));
        button.setTextColor(getColor(active ? R.color.white : R.color.blue));
    }

    private void loadCatalog(String enteredUrl) {
        String url = enteredUrl == null ? "" : enteredUrl.trim();
        String source = url.isEmpty() ? "asset:///catalog.json" : url;
        catalogStatus.setText(url.isEmpty() ? "正在读取内置目录…" : "正在下载在线目录…");
        statusText.setText("更新目录中");
        io.execute(() -> {
            try {
                String json = fetcher.fetch(source);
                ScoreCatalog loaded = ScoreCatalog.parse(json, source);
                runOnUiThread(() -> {
                    catalog = loaded;
                    SharedPreferences preferences = getSharedPreferences(PREFS, MODE_PRIVATE);
                    preferences.edit().putString(PREF_CATALOG_URL, url).apply();
                    catalogStatus.setText(
                            (url.isEmpty() ? "内置目录" : "在线目录")
                                    + " · 共 " + catalog.entries.size() + " 首");
                    statusText.setText("目录加载完成");
                    applySearch();
                });
            } catch (IOException | JSONException error) {
                runOnUiThread(() -> showError("目录加载失败：" + readable(error)));
            }
        });
    }

    private void applySearch() {
        if (catalog == null) {
            showError("曲谱目录尚未加载");
            return;
        }
        visibleEntries = catalog.search(searchInput.getText().toString());
        resultAdapter.clear();
        for (ScoreCatalog.ScoreEntry entry : visibleEntries) {
            resultAdapter.add(entry.listLabel());
        }
        resultAdapter.notifyDataSetChanged();
        if (visibleEntries.isEmpty()) {
            catalogStatus.setText("没有找到匹配曲谱");
        } else {
            catalogStatus.setText("找到 " + visibleEntries.size() + " 首，点击选择");
        }
        selectedEntry = null;
        currentScore = null;
        selectedTitle.setText("请选择一首曲谱");
        scorePreview.setText("下载后在这里预览 NOTE 内容");
    }

    private void loadSelectedScore(boolean saveAfterLoad) {
        if (selectedEntry == null) {
            showError("请先搜索并选择一首曲谱");
            return;
        }
        final ScoreCatalog.ScoreEntry entry = selectedEntry;
        if (currentScore != null && saveAfterLoad) {
            saveCurrentScore(entry);
            return;
        }
        String resolved;
        try {
            resolved = catalog.resolve(entry);
        } catch (IOException error) {
            showError("曲谱地址无效：" + readable(error));
            return;
        }
        statusText.setText("正在下载《" + entry.title + "》");
        io.execute(() -> {
            try {
                String text = fetcher.fetch(resolved);
                ScoreValidator.Result score = ScoreValidator.normalize(text);
                runOnUiThread(() -> {
                    if (selectedEntry != entry) {
                        return;
                    }
                    currentScore = score;
                    scorePreview.setText(score.normalizedText);
                    scorePreview.scrollTo(0, 0);
                    statusText.setText("已校验 " + score.noteCount + " 个音符");
                    if (saveAfterLoad) {
                        saveCurrentScore(entry);
                    }
                });
            } catch (IOException | ScoreValidator.FormatException error) {
                runOnUiThread(() -> showError("曲谱下载或校验失败：" + readable(error)));
            }
        });
    }

    private void saveCurrentScore(ScoreCatalog.ScoreEntry entry) {
        if (currentScore == null) {
            showError("当前没有可保存的曲谱");
            return;
        }
        try {
            ScoreStorage.SavedScore saved =
                    ScoreStorage.save(this, entry.title, currentScore.normalizedText);
            statusText.setText("已保存到 " + saved.displayLocation);
        } catch (IOException error) {
            showError("保存失败：" + readable(error));
        }
    }

    private void copyCurrentScore() {
        if (currentScore == null) {
            showError("请先下载曲谱");
            return;
        }
        ClipboardManager clipboard = (ClipboardManager) getSystemService(
                Context.CLIPBOARD_SERVICE);
        clipboard.setPrimaryClip(
                ClipData.newPlainText("NOTE 曲谱", currentScore.normalizedText));
        statusText.setText("曲谱内容已复制，可粘贴到蓝牙串口软件");
    }

    private void sendCurrentScore() {
        if (selectedDevice == null) {
            withBluetoothPermission(() -> {
                chooseBluetoothDevice();
                statusText.setText("选择设备后再次点击“蓝牙发送”");
            });
            return;
        }
        if (currentScore == null) {
            showError("请先下载并校验曲谱");
            return;
        }
        final ScoreValidator.Result score = currentScore;
        executeBluetooth("准备发送曲谱…", false, () -> {
            SppClient.Listener listener = message ->
                    runOnUiThread(() -> statusText.setText(message));
            sppClient.sendScore(score, listener);
        });
    }

    private void applyPhysicalMapping() {
        int[] notes = new int[8];
        for (int index = 0; index < 8; index++) {
            notes[index] = mappingSpinners[index].getSelectedItemPosition();
        }
        final PerformanceConfig updated;
        try {
            updated = PerformanceConfig.validated(notes, performanceConfig.remoteKeys);
        } catch (IllegalArgumentException error) {
            showError(error.getMessage());
            return;
        }
        releaseAllRemoteKeys(false);
        performanceConfig = updated;
        savePerformanceConfig();
        refreshMappingControls();
        statusText.setText("实体键映射已保存");
        if (sppClient.isConnected()) {
            final int[] mapping = performanceConfig.physicalNotes.clone();
            executeBluetooth("正在应用实体键映射…", false,
                    () -> sppClient.applyPhysicalMapping(mapping));
        }
    }

    private void savePerformanceConfig() {
        getSharedPreferences(PREFS, MODE_PRIVATE)
                .edit()
                .putString(PREF_PERFORMANCE_CONFIG, performanceConfig.toJson())
                .apply();
    }

    private void refreshMappingControls() {
        if (performanceConfig == null) {
            return;
        }
        for (int index = 0; index < 8; index++) {
            mappingSpinners[index].setSelection(performanceConfig.physicalNotes[index]);
        }
    }

    private void refreshRemotePads() {
        if (performanceConfig == null) {
            return;
        }
        for (int index = 0; index < 8; index++) {
            RemoteKeyConfig key = performanceConfig.remoteKeys.get(index);
            remotePads[index].setText(
                    key.label + "\n音" + key.note
                            + " · 力度" + key.velocity
                            + " · 音色" + key.tone
                            + " · 效果" + key.effect);
            int color;
            if (editMode) {
                color = R.color.muted;
            } else if (followMode
                    && (expectedMaskForDisplay() & (1 << key.note)) != 0) {
                color = R.color.navy;
            } else {
                color = R.color.teal;
            }
            remotePads[index].setBackgroundTintList(
                    android.content.res.ColorStateList.valueOf(getColor(color)));
        }
    }

    private void toggleKeyEditMode() {
        if (!editMode && testMode) {
            statusText.setText("32音测试中不能编辑琴键，请先退出测试模式");
            return;
        }
        if (!editMode && followScoreRadio.isChecked()) {
            statusText.setText("曲谱跟弹中不能编辑琴键，请先切换为自由演奏");
            return;
        }
        if (!editMode) {
            releaseAllRemoteKeys(false);
        }
        setKeyEditMode(!editMode, true);
    }

    private void setKeyEditMode(boolean enabled, boolean announce) {
        editMode = enabled;
        editKeysButton.setText(editMode ? "完成编辑" : "编辑琴键");
        editKeysButton.setBackgroundTintList(
                android.content.res.ColorStateList.valueOf(
                        getColor(editMode ? R.color.navy : R.color.muted)));
        refreshRemotePads();
        if (announce) {
            statusText.setText(editMode
                    ? "编辑模式：点击任意琴键修改设置，此时不会发声"
                    : "编辑完成，琴键恢复演奏");
        }
    }

    private int expectedMaskForDisplay() {
        if (!followMode || followSession == null) {
            return 0;
        }
        PracticeScore.Step step = followSession.currentStep();
        return step == null ? 0 : step.mask;
    }

    private void startFollowMode() {
        if (testMode) {
            statusText.setText("32音测试中不能使用曲谱跟弹，请先退出测试模式");
            stopFollowMode(true, false);
            return;
        }
        if (!connected || protocolVersion < 3) {
            statusText.setText("请先连接支持曲谱跟弹的 VERSION 3 固件");
            stopFollowMode(true, false);
            return;
        }
        if (currentScore == null) {
            statusText.setText("请先到“曲谱”页选择并下载一首曲谱");
            stopFollowMode(true, false);
            return;
        }
        practiceScore = PracticeScore.from(currentScore);
        if (practiceScore.steps.isEmpty()) {
            statusText.setText("当前曲谱没有可跟弹的音符");
            stopFollowMode(true, false);
            return;
        }
        if (editMode) {
            setKeyEditMode(false, false);
        }
        releaseAllRemoteKeys(false);
        followSession = new FollowSession(practiceScore);
        followMode = true;
        followGuidePanel.setVisibility(View.VISIBLE);
        followTitle.setText(selectedEntry == null ? "当前曲谱" : selectedEntry.title);
        showInitialFollowStep();
        startKeyPolling();
        statusText.setText("曲谱跟弹已开始，节奏由你控制");
    }

    private void stopFollowMode(boolean switchToFree, boolean announce) {
        followMode = false;
        followGeneration++;
        if (pollFuture != null) {
            pollFuture.cancel(false);
            pollFuture = null;
        }
        followSession = null;
        practiceScore = null;
        followGuidePanel.setVisibility(View.GONE);
        if (switchToFree && followScoreRadio.isChecked()) {
            changingMode = true;
            freePlayRadio.setChecked(true);
            changingMode = false;
        }
        refreshRemotePads();
        if (announce) {
            statusText.setText("已切换到自由演奏");
        }
    }

    private void showInitialFollowStep() {
        PracticeScore.Step step = followSession.currentStep();
        followProgress.setText("第 1/" + followSession.getStepCount() + " 组");
        followExpected.setText("应弹：" + noteMaskText(step.mask));
        followFeedback.setText("请弹奏当前音；按对后松开进入下一组");
        followFeedback.setTextColor(getColor(R.color.muted));
        refreshRemotePads();
    }

    private void startKeyPolling() {
        if (pollFuture != null) {
            pollFuture.cancel(false);
        }
        final int generation = ++followGeneration;
        pollInFlight = false;
        pollFuture = keyPoller.scheduleWithFixedDelay(() -> {
            if (!followMode || generation != followGeneration
                    || pollInFlight || !sppClient.isConnected()) {
                return;
            }
            pollInFlight = true;
            io.execute(() -> {
                try {
                    int physical = sppClient.readKeyState();
                    runOnUiThread(() -> handleFollowMask(
                            physical | remoteMask, generation));
                } catch (IOException | SecurityException error) {
                    runOnUiThread(() -> handleFollowPollingError(generation, error));
                } finally {
                    pollInFlight = false;
                }
            });
        }, 0, 30, TimeUnit.MILLISECONDS);
    }

    private void handleFollowMask(int downMask, int generation) {
        if (!followMode || generation != followGeneration || followSession == null) {
            return;
        }
        FollowSession.Update update = followSession.update(downMask);
        renderFollowUpdate(update);
        if (update.completed) {
            followMode = false;
            followGeneration++;
            if (pollFuture != null) {
                pollFuture.cancel(false);
                pollFuture = null;
            }
            statusText.setText("曲谱跟弹完成");
            refreshRemotePads();
        }
    }

    private void renderFollowUpdate(FollowSession.Update update) {
        followFeedback.setTextColor(getColor(R.color.muted));
        switch (update.status) {
            case WRONG:
                followFeedback.setText("这个音不对，请继续弹当前音");
                followFeedback.setTextColor(Color.RED);
                break;
            case CORRECT_HOLD:
                followFeedback.setText("按对了，松开后进入下一组");
                break;
            case ADVANCED:
                followFeedback.setText("正确，继续下一组");
                break;
            case COMPLETED:
                followProgress.setText("全部完成 · 共 " + update.stepCount + " 组");
                followExpected.setText("曲谱跟弹完成");
                followFeedback.setText("已完成整首曲谱");
                break;
            default:
                followFeedback.setText("请弹奏当前音；按错会提示，不会中断");
                break;
        }
        if (!update.completed) {
            followProgress.setText("第 " + (update.stepIndex + 1)
                    + "/" + update.stepCount + " 组");
            followExpected.setText("应弹：" + noteMaskText(update.expectedMask));
        }
        refreshRemotePads();
    }

    private void handleFollowPollingError(int generation, Exception error) {
        if (!followMode || generation != followGeneration) {
            return;
        }
        stopFollowMode(true, false);
        showError("曲谱跟弹停止：读取实体键失败：" + readable(error));
    }

    private static String noteMaskText(int mask) {
        StringBuilder text = new StringBuilder();
        for (int note = 0; note < 8; note++) {
            if ((mask & (1 << note)) != 0) {
                if (text.length() > 0) {
                    text.append(" + ");
                }
                text.append("音符").append(note);
            }
        }
        return text.length() == 0 ? "--" : text.toString();
    }

    private void showRemoteKeyDialog(int index) {
        RemoteKeyConfig current = performanceConfig.remoteKeys.get(index);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        int padding = dp(16);
        content.setPadding(padding, dp(4), padding, 0);

        EditText labelInput = addTextInput(content, "名称（1-12 字）", current.label);
        Spinner noteInput = addChoice(
                content, "音高（0-7）", "音符 ", 0, 7, current.note);
        TextView swapHint = new TextView(this);
        swapHint.setText("音高已被其他琴键使用时，会自动交换两个琴键的音高。");
        swapHint.setTextColor(getColor(R.color.muted));
        swapHint.setTextSize(12);
        swapHint.setPadding(0, dp(3), 0, dp(2));
        content.addView(swapHint);
        Spinner velocityInput = addChoice(
                content, "力度（0-31）", "", 0, 31, current.velocity);
        Spinner toneInput = addChoice(
                content, "音色（0-3）", "", 0, 3, current.tone);
        Spinner effectInput = addChoice(
                content, "效果（0-3）", "", 0, 3, current.effect);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(content, new ScrollView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));
        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle("设置" + current.label)
                .setView(scroll)
                .setPositiveButton("保存", null)
                .setNegativeButton("取消", null)
                .create();
        dialog.setOnShowListener(ignored -> dialog.getButton(
                AlertDialog.BUTTON_POSITIVE).setOnClickListener(view -> {
            try {
                String label = labelInput.getText().toString().trim();
                if (label.isEmpty()) {
                    label = "琴键" + (index + 1);
                }
                RemoteKeyConfig changed = new RemoteKeyConfig(
                        label,
                        noteInput.getSelectedItemPosition(),
                        velocityInput.getSelectedItemPosition(),
                        toneInput.getSelectedItemPosition(),
                        effectInput.getSelectedItemPosition());
                performanceConfig = performanceConfig.withRemoteKeyChanged(index, changed);
                savePerformanceConfig();
                refreshRemotePads();
                statusText.setText("虚拟琴键配置已保存");
                dialog.dismiss();
            } catch (IllegalArgumentException error) {
                showError(error.getMessage());
            }
        }));
        dialog.show();
    }

    private EditText addTextInput(
            LinearLayout parent, String label, String value) {
        TextView title = new TextView(this);
        title.setText(label);
        title.setTextColor(getColor(R.color.navy));
        title.setTextSize(13);
        title.setPadding(0, dp(8), 0, dp(2));
        parent.addView(title);
        EditText input = new EditText(this);
        input.setText(value);
        input.setSelectAllOnFocus(true);
        input.setSingleLine(true);
        input.setInputType(android.text.InputType.TYPE_CLASS_TEXT);
        parent.addView(input, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));
        return input;
    }

    private Spinner addChoice(
            LinearLayout parent,
            String label,
            String prefix,
            int first,
            int last,
            int selected) {
        TextView title = new TextView(this);
        title.setText(label);
        title.setTextColor(getColor(R.color.navy));
        title.setTextSize(13);
        title.setPadding(0, dp(8), 0, dp(2));
        parent.addView(title);
        Spinner spinner = new Spinner(this);
        ArrayAdapter<String> adapter = new ArrayAdapter<>(
                this, android.R.layout.simple_spinner_item);
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        for (int value = first; value <= last; value++) {
            adapter.add(prefix + value);
        }
        spinner.setAdapter(adapter);
        spinner.setSelection(selected - first, false);
        parent.addView(spinner, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));
        return spinner;
    }

    private void pressRemoteKey(int index) {
        if (editMode || testMode || index < 0 || index >= 8 || remotePressed[index]) {
            return;
        }
        if (!connected || protocolVersion < 2) {
            statusText.setText("请先连接新版 FPGA 码流后再使用手机琴键");
            return;
        }
        RemoteKeyConfig key = performanceConfig.remoteKeys.get(index);
        remotePressed[index] = true;
        updateRemoteMask();
        remotePads[index].setPressed(true);
        remotePads[index].setAlpha(0.72f);
        io.execute(() -> {
            try {
                sppClient.sendRemoteKeyDown(key);
            } catch (IOException | SecurityException error) {
                runOnUiThread(() -> {
                    setRemotePadReleased(index);
                    showError("琴键按下失败：" + readable(error));
                });
            }
        });
    }

    private void releaseRemoteKey(int index) {
        if (index < 0 || index >= 8 || !remotePressed[index]) {
            return;
        }
        RemoteKeyConfig key = performanceConfig.remoteKeys.get(index);
        setRemotePadReleased(index);
        if (connected && protocolVersion >= 2) {
            io.execute(() -> {
                try {
                    sppClient.sendRemoteKeyUp(key.note);
                } catch (IOException | SecurityException error) {
                    runOnUiThread(() ->
                            showError("琴键松开失败：" + readable(error)));
                }
            });
        }
    }

    private void setRemotePadReleased(int index) {
        remotePressed[index] = false;
        updateRemoteMask();
        remotePads[index].setPressed(false);
        remotePads[index].setAlpha(1.0f);
    }

    private void updateRemoteMask() {
        int mask = 0;
        for (int index = 0; index < 8; index++) {
            if (remotePressed[index]) {
                mask |= 1 << performanceConfig.remoteKeys.get(index).note;
            }
        }
        remoteMask = mask;
    }

    private void releaseAllRemoteKeys(boolean showStatus) {
        for (int index = 0; index < 8; index++) {
            setRemotePadReleased(index);
        }
        if (!connected || protocolVersion < 2) {
            return;
        }
        io.execute(() -> {
            try {
                sppClient.releaseAllRemoteKeys();
                if (showStatus) {
                    runOnUiThread(() -> statusText.setText("已松开全部手机琴键"));
                }
            } catch (IOException | SecurityException error) {
                runOnUiThread(() -> showError("全部松开失败：" + readable(error)));
            }
        });
    }

    private void toggleTestMode() {
        if (!connected || protocolVersion < 2) {
            statusText.setText("请先连接 FPGA 后再使用32音测试");
            return;
        }
        final boolean enable = !testMode;
        if (enable) {
            if (followMode) {
                stopFollowMode(true, false);
            }
            setKeyEditMode(false, false);
            releaseAllRemoteKeys(false);
        }
        executeBluetooth(
                enable ? "正在进入32音测试…" : "正在退出32音测试…",
                true,
                () -> {
                    if (enable) {
                        sppClient.releaseAllRemoteKeys();
                    }
                    sppClient.setTestMode(enable);
                    runOnUiThread(() -> {
                        testMode = enable;
                        updateTestModeUi();
                        statusText.setText(enable
                                ? "32音测试已开启，请在 FPGA 上旋到实时频谱页"
                                : "32音测试已退出，实体键和手机琴键恢复演奏");
                    });
                });
    }

    private void updateTestModeUi() {
        testModeButton.setEnabled(connected && protocolVersion >= 2);
        testModeButton.setText(testMode ? "退出32音测试" : "进入32音测试");
        testModeButton.setBackgroundTintList(
                android.content.res.ColorStateList.valueOf(
                        getColor(testMode ? R.color.danger : R.color.blue)));
    }

    private void connectOrDisconnect() {
        if (sppClient.isConnected() || connected) {
            disconnectBluetooth();
            return;
        }
        if (selectedDevice == null) {
            withBluetoothPermission(() -> {
                chooseBluetoothDevice();
                statusText.setText("选择设备后再次点击“连接蓝牙”");
            });
            return;
        }
        executeBluetooth("正在连接蓝牙…", false, () -> {
        });
    }

    private void disconnectBluetooth() {
        for (int index = 0; index < 8; index++) {
            setRemotePadReleased(index);
        }
        io.execute(() -> {
            if (testMode && sppClient.isConnected()) {
                try {
                    sppClient.setTestMode(false);
                } catch (IOException | SecurityException ignored) {
                }
            }
            if (sppClient.isConnected() && sppClient.getProtocolVersion() >= 2) {
                try {
                    sppClient.releaseAllRemoteKeys();
                } catch (IOException | SecurityException ignored) {
                }
            }
            sppClient.close();
            runOnUiThread(() -> {
                updateConnectionState(false, 0);
                statusText.setText("蓝牙已断开");
            });
        });
    }

    private void executeBluetooth(
            String progress, boolean requireRemoteProtocol, BluetoothAction action) {
        if (selectedDevice == null) {
            showError("请先选择已配对的 JDY-31");
            return;
        }
        withBluetoothPermission(() -> {
            statusText.setText(progress);
            io.execute(() -> {
                try {
                    int version = ensureConnectedInWorker();
                    if (requireRemoteProtocol && version < 2) {
                        throw new IOException("请先烧录支持远程演奏的新版 FPGA 码流");
                    }
                    action.run();
                } catch (IOException | SecurityException error) {
                    runOnUiThread(() -> {
                        if (!sppClient.isConnected()) {
                            updateConnectionState(false, 0);
                        }
                        showError("蓝牙操作失败：" + readable(error));
                    });
                }
            });
        });
    }

    private int ensureConnectedInWorker() throws IOException {
        if (sppClient.isConnected()) {
            int version = sppClient.getProtocolVersion();
            runOnUiThread(() -> updateConnectionState(true, version));
            return version;
        }
        if (selectedDevice == null) {
            throw new IOException("尚未选择蓝牙设备");
        }
        BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
        if (adapter == null) {
            throw new IOException("此手机不支持经典蓝牙");
        }
        SppClient.Listener listener = message ->
                runOnUiThread(() -> statusText.setText(message));
        int version = sppClient.connect(adapter, selectedDevice, listener);
        final int[] mapping = performanceConfig.physicalNotes.clone();
        sppClient.applyPhysicalMapping(mapping);
        runOnUiThread(() -> updateConnectionState(true, version));
        return version;
    }

    private void updateConnectionState(boolean isConnected, int version) {
        connected = isConnected;
        protocolVersion = version;
        if (!isConnected) {
            testMode = false;
        }
        connectDeviceButton.setText(isConnected ? "断开蓝牙" : "连接蓝牙");
        if (!isConnected) {
            protocolStatus.setText("未连接 FPGA");
            if (followMode) {
                stopFollowMode(true, false);
            }
        } else if (version >= 3) {
            protocolStatus.setText("FPGA 协议 V3：自由演奏、曲谱跟弹和录音回传可用");
        } else if (version >= 2) {
            protocolStatus.setText("FPGA 协议 V2：手机演奏、实体键映射和录音回传可用");
        } else {
            protocolStatus.setText("旧版 FPGA 码流：只能发送曲谱，请烧录新版码流");
        }
        updateTestModeUi();
    }

    @SuppressLint("MissingPermission")
    private void chooseBluetoothDevice() {
        // Every call enters through withBluetoothPermission().
        BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
        if (adapter == null) {
            showError("此手机不支持经典蓝牙");
            return;
        }
        if (!adapter.isEnabled()) {
            startActivity(new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE));
            showError("请先开启蓝牙，再重新选择设备");
            return;
        }
        List<BluetoothDevice> devices = new ArrayList<>(adapter.getBondedDevices());
        if (devices.isEmpty()) {
            new AlertDialog.Builder(this)
                    .setTitle("没有已配对设备")
                    .setMessage("请先在系统蓝牙设置中配对 JDY-31-SPP，再返回选择。")
                    .setPositiveButton("打开蓝牙设置", (dialog, which) ->
                            startActivity(new Intent(Settings.ACTION_BLUETOOTH_SETTINGS)))
                    .setNegativeButton("取消", null)
                    .show();
            return;
        }
        String[] labels = new String[devices.size()];
        for (int index = 0; index < devices.size(); index++) {
            BluetoothDevice device = devices.get(index);
            String name = device.getName();
            labels[index] = (isBlank(name) ? "未知设备" : name)
                    + "\n" + device.getAddress();
        }
        new AlertDialog.Builder(this)
                .setTitle("选择已配对设备")
                .setItems(labels, (dialog, which) -> {
                    if (sppClient.isConnected() || connected) {
                        disconnectBluetooth();
                    }
                    selectedDevice = devices.get(which);
                    deviceText.setText(labels[which].replace("\n", " · "));
                    statusText.setText("已选择蓝牙设备，请点击“连接蓝牙”");
                })
                .setNegativeButton("取消", null)
                .show();
    }

    private void withBluetoothPermission(Runnable action) {
        if (Build.VERSION.SDK_INT >= 31
                && checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)
                != PackageManager.PERMISSION_GRANTED) {
            pendingBluetoothAction = action;
            requestPermissions(
                    new String[]{Manifest.permission.BLUETOOTH_CONNECT},
                    REQUEST_BLUETOOTH_CONNECT);
        } else {
            action.run();
        }
    }

    @Override
    public void onRequestPermissionsResult(
            int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQUEST_BLUETOOTH_CONNECT) {
            Runnable action = pendingBluetoothAction;
            pendingBluetoothAction = null;
            if (grantResults.length > 0
                    && grantResults[0] == PackageManager.PERMISSION_GRANTED
                    && action != null) {
                action.run();
            } else {
                showError("未授予蓝牙连接权限");
            }
        }
    }

    private void confirmStartRecording() {
        if (testMode) {
            statusText.setText("请先退出32音测试，再开始录音");
            return;
        }
        if (!connected || protocolVersion < 2) {
            statusText.setText("请先连接新版 FPGA 码流");
            return;
        }
        new AlertDialog.Builder(this)
                .setTitle("开始录音")
                .setMessage("这会清除 FPGA 中原有的曲谱和录音事件，确定开始吗？")
                .setPositiveButton("开始", (dialog, which) -> startRecording())
                .setNegativeButton("取消", null)
                .show();
    }

    private void startRecording() {
        executeBluetooth("准备开始录音…", true, () -> {
            sppClient.releaseAllRemoteKeys();
            sppClient.startRecording();
            runOnUiThread(() -> {
                recording = true;
                updateRecordingUi();
                recordingStatus.setText("正在录音：实体压力键和手机琴键都会记录");
            });
        });
    }

    private void stopAndFetchRecording() {
        if (!connected || protocolVersion < 2) {
            statusText.setText("请先连接新版 FPGA 码流");
            return;
        }
        recordingStatus.setText("正在停止并取回录音…");
        executeBluetooth("正在停止录音…", true, () -> {
            sppClient.releaseAllRemoteKeys();
            sppClient.stopRecording();
            sleepBriefly();
            RecordingDumpParser.Result dump = sppClient.dumpRecording();
            runOnUiThread(() -> {
                recording = false;
                updateRecordingUi();
                recordingText.setText(dump.noteText);
                recordingText.setSelection(0);
                recordingStatus.setText(
                        "已取回 " + dump.eventCount + " 条事件，可编辑、保存或发送回放");
                statusText.setText("录音回传完成");
            });
        });
    }

    private static void sleepBriefly() throws IOException {
        try {
            Thread.sleep(30);
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            throw new IOException("等待录音结束时被中断", interrupted);
        }
    }

    private void replayFpgaRecording() {
        executeBluetooth("准备回放 FPGA 录音…", true, () -> {
            sppClient.replayRecording();
            runOnUiThread(() -> recordingStatus.setText("FPGA 正在回放已录制内容"));
        });
    }

    private void sendEditedRecording() {
        final ScoreValidator.Result score;
        try {
            score = readRecordingScore();
        } catch (ScoreValidator.FormatException error) {
            showError("录音内容格式错误：" + readable(error));
            return;
        }
        executeBluetooth("正在发送录音回放…", false, () -> {
            SppClient.Listener listener = message ->
                    runOnUiThread(() -> statusText.setText(message));
            sppClient.sendScore(score, listener);
        });
    }

    private void saveRecording() {
        final ScoreValidator.Result score;
        try {
            score = readRecordingScore();
        } catch (ScoreValidator.FormatException error) {
            showError("录音内容格式错误：" + readable(error));
            return;
        }
        String timestamp = new SimpleDateFormat(
                "yyyyMMdd_HHmmss", Locale.ROOT).format(new Date());
        try {
            ScoreStorage.SavedScore saved = ScoreStorage.save(
                    this, "录音_" + timestamp, score.normalizedText);
            recordingStatus.setText("录音已保存到 " + saved.displayLocation);
        } catch (IOException error) {
            showError("保存录音失败：" + readable(error));
        }
    }

    private void copyRecording() {
        final ScoreValidator.Result score;
        try {
            score = readRecordingScore();
        } catch (ScoreValidator.FormatException error) {
            showError("录音内容格式错误：" + readable(error));
            return;
        }
        ClipboardManager clipboard = (ClipboardManager) getSystemService(
                Context.CLIPBOARD_SERVICE);
        clipboard.setPrimaryClip(
                ClipData.newPlainText("录音 NOTE 曲谱", score.normalizedText));
        recordingStatus.setText("录音内容已复制");
    }

    private void confirmClearRecording() {
        if (recordingText.getText().toString().trim().isEmpty()) {
            recordingStatus.setText("当前没有已取回的录音内容");
            return;
        }
        new AlertDialog.Builder(this)
                .setTitle("清除已取回内容")
                .setMessage("只清除手机中显示的 NOTE 内容，不会删除 FPGA 内的原始录音。")
                .setPositiveButton("清除", (dialog, which) -> {
                    recordingText.setText("");
                    recordingText.setSelection(0);
                    recordingStatus.setText("已清除手机中取回的录音内容");
                    statusText.setText("FPGA 内录音未删除，仍可点击“回放录音”");
                })
                .setNegativeButton("取消", null)
                .show();
    }

    private ScoreValidator.Result readRecordingScore()
            throws ScoreValidator.FormatException {
        String text = recordingText.getText().toString().trim();
        if (text.isEmpty()) {
            throw new ScoreValidator.FormatException("还没有可用的录音内容");
        }
        return ScoreValidator.normalize(text);
    }

    private void updateRecordingUi() {
        startRecordingButton.setEnabled(!recording);
        performanceRecordButton.setText(recording ? "录音中，查看" : "开始录音");
        if (!recording && recordingStatus.getText().toString().startsWith("正在录音")) {
            recordingStatus.setText("录音已停止");
        }
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private void showError(String message) {
        statusText.setText(message);
    }

    private static String readable(Exception error) {
        String message = error.getMessage();
        return isBlank(message) ? error.getClass().getSimpleName() : message;
    }

    private static boolean isBlank(String value) {
        return value == null || value.trim().isEmpty();
    }

    @Override
    protected void onPause() {
        releaseAllRemoteKeys(false);
        if (followMode) {
            stopFollowMode(true, false);
        }
        super.onPause();
    }

    @Override
    protected void onDestroy() {
        keyPoller.shutdownNow();
        sppClient.close();
        io.shutdownNow();
        super.onDestroy();
    }
}
