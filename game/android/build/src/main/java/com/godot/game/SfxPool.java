package com.godot.game;

import android.app.Activity;
import android.app.NotificationManager;
import android.content.Context;
import android.media.AudioAttributes;
import android.media.AudioManager;
import android.media.AudioPlaybackConfiguration;
import android.media.SoundPool;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.widget.Toast;

import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * Spieltöne über Androids SoundPool (Beta 1.4.8, scripts/app/sound.gd).
 *
 * Anlass: Nach einem Telefonat blieb die App auf dem S24 (Android 16) stumm. Godot 4.6 spielt auf Android über einen einzigen
 * OpenSL-ES-Abspieler mit Puffer-Warteschlange, der beim Start einmal angelegt wird (platform/android/audio_driver_opensl.cpp): Jeder
 * Rückruf reiht selbst den nächsten Puffer ein, bei Fokusverlust wird er nur pausiert (set_pause), nie neu angelegt; Fehler beim
 * Einreihen und Wechsel der Ausgabe (Hörer/Bluetooth-SCO während des Gesprächs) werden nicht behandelt, und GDScript kann den
 * Treiber nicht neu starten (AudioServer.set_output_device tut unter OpenSL nichts). Bleibt die Kette einmal stehen, ist die App bis
 * zum Neustart stumm. SoundPool legt für jeden Ton eine frische Ausgabe an und folgt dem aktuellen Ausgabeweg.
 *
 * Neuaufbau (Beta 1.5.1, Protokoll S24 10.10.2026): Beginnt ein Anruf, während die App im Hintergrund liegt, schaltet das System
 * die vorhandenen Abspieler der App stumm (AudioTrack-Lautstärke 0, dumpsys: mutedState clientVolume) und hebt das nicht wieder
 * auf; neue Tracks desselben SoundPool erben das, erst ein App-Neustart half. Deshalb baut sound.gd beim Zurückkehren
 * (NOTIFICATION_APPLICATION_RESUMED nach PAUSED) den Vorrat mit rebuild() neu auf: Der neue Pool lädt, bis dahin spielt der alte
 * weiter; erst wenn alle Töne geladen sind (spätestens nach 5 s), wird getauscht und der alte freigegeben (ein laufender Jubel
 * bricht dabei ab). Zusätzlich schreibt play() höchstens einmal je Sekunde Lautstärke und Stumm-Gründe ins Log (Tag „godot“,
 * Präfix „SfxPool:“) und baut neu auf, wenn Android Spiel-Abspieler als stumm durch Client-Lautstärke/App-Ops/Volume-Shaper meldet
 * (soweit Android das einer App verrät: die Abspieler-Liste ist für Apps anonymisiert).
 *
 * Die Töne liegen als Rohressourcen res/raw/sfx_<name>.ogg im Paket (tools/build.ps1 kopiert sie aus game/assets/sfx). Fehlen sie,
 * meldet init 0 und sound.gd spielt wie bisher über Godot.
 */
public final class SfxPool {
    private static final String TAG = "godot";
    private static final String P = "SfxPool: ";
    private static final int MAX_STREAMS = 6;
    private static final long SWAP_TIMEOUT_MS = 5000;
    private static final long DIAG_EVERY_MS = 1000;
    private static final long AUTO_REBUILD_EVERY_MS = 15000;
    private static final Object LOCK = new Object();

    private static SoundPool pool;
    private static Context appContext;
    private static String[] names = new String[0];
    private static Map<String, Integer> ids = new HashMap<>();
    private static Set<Integer> ready = new HashSet<>();
    private static final Handler main = new Handler(Looper.getMainLooper());
    private static Handler worker;                                 // Diagnose abseits des Spiel-Threads
    private static final Set<Integer> active = new HashSet<>();   // gestartete Streams für stopAll
    private static int fails = 0;
    private static int generation = 0;                            // zählt Tauschvorgänge (alte Stream-Nummern gelten dann nicht mehr)

    // Neuaufbau: lädt, während der alte Pool weiterspielt.
    private static SoundPool pending;
    private static Map<String, Integer> pendingIds = new HashMap<>();
    private static Set<Integer> pendingReady = new HashSet<>();
    private static int pendingExpected = 0;
    private static int pendingDone = 0;
    private static long pendingSince = 0;
    private static String pendingReason = "";
    private static int rebuilds = 0;

    private static long lastDiagMs = -DIAG_EVERY_MS;
    private static long lastAutoRebuildMs = -AUTO_REBUILD_EVERY_MS;

    private SfxPool() {}

    /** Legt den Vorrat an und lädt alle vorhandenen Töne (Namen durch Komma getrennt). Ergebnis: Zahl der gefundenen Dateien. */
    public static int init(Activity activity, String csv) {
        synchronized (LOCK) {
            if (activity == null || csv == null) {
                return 0;
            }
            appContext = activity.getApplicationContext();
            names = csv.split(",");
            return build();
        }
    }

    private static SoundPool newPool() {
        AudioAttributes attrs = new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build();
        SoundPool p = new SoundPool.Builder().setMaxStreams(MAX_STREAMS).setAudioAttributes(attrs).build();
        p.setOnLoadCompleteListener(SfxPool::onLoaded);
        return p;
    }

    /** Lädt alle Töne in p; Ergebnis: Zahl der gestarteten Ladevorgänge. */
    private static int loadAll(SoundPool p, Map<String, Integer> into) {
        int found = 0;
        for (String raw : names) {
            String n = raw.trim();
            if (n.isEmpty()) {
                continue;
            }
            int res = appContext.getResources().getIdentifier("sfx_" + n, "raw", appContext.getPackageName());
            if (res == 0) {
                continue;
            }
            try {
                into.put(n, p.load(appContext, res, 1));
                found++;
            } catch (RuntimeException e) {
                Log.w(TAG, P + "Laden " + n + ": " + e);
            }
        }
        return found;
    }

    /** Sofortiger Aufbau (App-Start). */
    private static int build() {
        if (pool != null) {
            pool.release();
            pool = null;
        }
        dropPending();
        ids = new HashMap<>();
        ready = new HashSet<>();
        active.clear();
        fails = 0;
        generation++;
        pool = newPool();
        int found = loadAll(pool, ids);
        Log.i(TAG, P + "SoundPool bereit: " + found + " Töne");
        return found;
    }

    private static void onLoaded(SoundPool sp, int sampleId, int status) {
        synchronized (LOCK) {
            if (sp == pool) {
                if (status == 0) {
                    ready.add(sampleId);
                }
            } else if (sp == pending) {
                pendingDone++;
                if (status == 0) {
                    pendingReady.add(sampleId);
                }
                if (pendingDone >= pendingExpected) {
                    swap("alle geladen");
                }
            }
        }
    }

    /**
     * Baut den Vorrat frisch auf (beim Zurückkehren in die App oder wenn das System die Abspieler stumm geschaltet hat). Der alte
     * Pool spielt weiter, bis der neue alle Töne geladen hat. Ergebnis: true = Neuaufbau gestartet (false: läuft schon / nicht
     * eingerichtet).
     */
    public static boolean rebuild(String reason) {
        synchronized (LOCK) {
            if (appContext == null) {
                return false;
            }
            String why = reason == null ? "" : reason;
            if (pending != null) {
                Log.i(TAG, P + "Neuaufbau (" + why + ") läuft schon");
                return false;
            }
            final SoundPool p = newPool();
            pending = p;
            pendingIds = new HashMap<>();
            pendingReady = new HashSet<>();
            pendingDone = 0;
            pendingSince = SystemClock.elapsedRealtime();
            pendingReason = why;
            pendingExpected = loadAll(p, pendingIds);
            if (pendingExpected == 0) {
                dropPending();
                return false;
            }
            Log.i(TAG, P + "Neuaufbau gestartet (" + why + "), lade " + pendingExpected + " Töne, alter Pool spielt weiter");
            main.postDelayed(() -> {
                synchronized (LOCK) {
                    if (pending == p) {
                        swap("Zeitlimit");
                    }
                }
            }, SWAP_TIMEOUT_MS);
            return true;
        }
    }

    /** Tauscht den fertig geladenen neuen Pool ein (unter LOCK). */
    private static void swap(String why) {
        if (pending == null) {
            return;
        }
        if (pendingReady.isEmpty()) {
            Log.w(TAG, P + "Neuaufbau (" + pendingReason + ") ohne geladene Töne (" + why + "), alter Pool bleibt");
            dropPending();
            return;
        }
        SoundPool old = pool;
        pool = pending;
        ids = pendingIds;
        ready = pendingReady;
        int expected = pendingExpected;
        pending = null;
        pendingIds = new HashMap<>();
        pendingReady = new HashSet<>();
        pendingExpected = 0;
        pendingDone = 0;
        active.clear();
        fails = 0;
        generation++;
        rebuilds++;
        long ms = SystemClock.elapsedRealtime() - pendingSince;
        Log.i(TAG, P + "Neuaufbau fertig (" + pendingReason + ", " + why + "): " + ready.size() + "/" + expected
                + " Töne in " + ms + " ms, Nr. " + rebuilds + ", alter Pool freigegeben");
        if (old != null) {
            old.release();
        }
    }

    private static void dropPending() {
        if (pending != null) {
            pending.release();
            pending = null;
        }
        pendingIds = new HashMap<>();
        pendingReady = new HashSet<>();
        pendingExpected = 0;
        pendingDone = 0;
    }

    /** Wie viele Töne fertig geladen sind. */
    public static int readyCount() {
        synchronized (LOCK) {
            return ready.size();
        }
    }

    /** Wie oft der Vorrat im laufenden Prozess neu aufgebaut wurde. */
    public static int rebuildCount() {
        synchronized (LOCK) {
            return rebuilds;
        }
    }

    /** true, solange ein Neuaufbau lädt. */
    public static boolean rebuilding() {
        synchronized (LOCK) {
            return pending != null;
        }
    }

    /** Spielt einen Ton (Lautstärke 0..1). Ergebnis: Stream-Nummer > 0, sonst 0 (nicht geladen, unbekannt). */
    public static int play(String name, float volume) {
        synchronized (LOCK) {
            Integer id = ids.get(name);
            if (pool == null || id == null || !ready.contains(id)) {
                return 0;
            }
            float v = Math.max(0f, Math.min(1f, volume));
            int stream = pool.play(id, v, v, 1, 0, 1f);
            if (stream == 0) {
                // Ein geladener Ton startet nicht: Vorrat neu anlegen (wie ein frischer App-Start); bis dahin spielt Godot.
                fails++;
                Log.w(TAG, P + "play " + name + " fehlgeschlagen (" + fails + "), Lautstärke " + v);
                if (fails >= 2) {
                    rebuild("2 Fehlstarts");
                }
            } else {
                fails = 0;
                if (active.size() > 64) {
                    active.clear();
                }
                active.add(stream);
            }
            diagnose(name, v, stream);
            return stream;
        }
    }

    /**
     * Höchstens einmal je Sekunde (unter LOCK aufgerufen, Arbeit 150 ms später in einem eigenen Thread): Lautstärke, Medienlautstärke,
     * Modus (2 = Anruf) und – soweit Android es einer App zeigt – Stumm-Gründe der Spiel-Abspieler ins Log. Meldet das System
     * Spiel-Abspieler als stumm durch Client-Lautstärke, App-Ops oder Volume-Shaper, wird neu aufgebaut (höchstens alle 15 s).
     */
    private static void diagnose(final String name, final float v, final int stream) {
        long now = SystemClock.elapsedRealtime();
        if (now - lastDiagMs < DIAG_EVERY_MS || appContext == null) {
            return;
        }
        lastDiagMs = now;
        if (worker == null) {
            HandlerThread t = new HandlerThread("SfxPoolDiag");
            t.start();
            worker = new Handler(t.getLooper());
        }
        worker.postDelayed(() -> diagnoseNow(name, v, stream), 150);
    }

    private static void diagnoseNow(String name, float v, int stream) {
        try {
            AudioManager am = (AudioManager) appContext.getSystemService(Context.AUDIO_SERVICE);
            if (am == null) {
                return;
            }
            int music = am.getStreamVolume(AudioManager.STREAM_MUSIC);
            int max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
            boolean streamMute = am.isStreamMute(AudioManager.STREAM_MUSIC);
            int games = 0;
            String mutedBy = "";
            String sample = "";
            if (Build.VERSION.SDK_INT >= 26) {
                List<AudioPlaybackConfiguration> list = am.getActivePlaybackConfigurations();
                for (AudioPlaybackConfiguration c : list) {
                    AudioAttributes a = c.getAudioAttributes();
                    if (a == null || a.getUsage() != AudioAttributes.USAGE_GAME) {
                        continue;
                    }
                    games++;
                    String s = String.valueOf(c);
                    String m = mutedReasons(s);
                    if (!m.isEmpty()) {
                        mutedBy = m;
                        sample = s;
                    }
                }
            }
            boolean problem = v <= 0.001f || stream == 0 || music == 0 || streamMute || !mutedBy.isEmpty();
            String line = P + "Ton " + name + " Lautstärke " + String.format(Locale.ROOT, "%.2f", v) + " Stream " + stream
                    + " Medien " + music + "/" + max + (streamMute ? " (stumm)" : "") + " Modus " + am.getMode()
                    + " Spiel-Abspieler " + games + (mutedBy.isEmpty() ? "" : " stumm durch " + mutedBy)
                    + " Neuaufbauten " + rebuildCount();
            if (problem) {
                Log.w(TAG, line + (sample.isEmpty() ? "" : " | " + sample));
            } else {
                Log.i(TAG, line);
            }
            if (mutedBy.contains("clientVolume") || mutedBy.contains("appOps") || mutedBy.contains("volumeShaper")) {
                long now = SystemClock.elapsedRealtime();
                synchronized (LOCK) {
                    if (now - lastAutoRebuildMs >= AUTO_REBUILD_EVERY_MS) {
                        lastAutoRebuildMs = now;
                        rebuild("stumm erkannt: " + mutedBy);
                    }
                }
            }
        } catch (RuntimeException e) {
            Log.w(TAG, P + "Diagnose: " + e);
        }
    }

    /** Stumm-Gründe aus AudioPlaybackConfiguration.toString() („mutedState:…“, Android 14+); "" = keine/nicht lesbar. */
    static String mutedReasons(String s) {
        int i = s == null ? -1 : s.indexOf("mutedState:");
        if (i < 0) {
            return "";
        }
        String rest = s.substring(i + "mutedState:".length());
        StringBuilder out = new StringBuilder();
        for (String key : new String[] {"master", "streamVolume", "streamMute", "appOps", "clientVolume", "volumeShaper", "portVolume", "opPlayAudio"}) {
            if (rest.contains(key)) {
                if (out.length() > 0) {
                    out.append(' ');
                }
                out.append(key);
            }
        }
        return out.toString();
    }

    public static void stop(int stream) {
        synchronized (LOCK) {
            if (pool != null && stream > 0) {
                pool.stop(stream);
            }
        }
    }

    public static void stopAll() {
        synchronized (LOCK) {
            if (pool != null) {
                for (int s : active) {
                    pool.stop(s);
                }
                active.clear();
            }
        }
    }

    /** Blendet einen Ton in ms Millisekunden von volume auf 0 aus und stoppt ihn (nach einem Tausch gilt die Nummer nicht mehr). */
    public static void fade(int stream, float volume, int ms) {
        if (stream <= 0) {
            return;
        }
        final int gen;
        synchronized (LOCK) {
            gen = generation;
        }
        final int steps = Math.max(1, ms / 40);
        for (int i = 1; i <= steps; i++) {
            final float v = volume * (1f - (float) i / steps);
            final boolean last = i == steps;
            main.postDelayed(() -> {
                synchronized (LOCK) {
                    if (pool == null || gen != generation) {
                        return;
                    }
                    if (last) {
                        pool.stop(stream);
                        active.remove(stream);
                    } else {
                        pool.setVolume(stream, v, v);
                    }
                }
            }, (long) i * ms / steps);
        }
    }

    /** App verliert den Fokus: laufende Töne anhalten (wie Godot seine Ausgabe pausiert). */
    public static void pause() {
        synchronized (LOCK) {
            if (pool != null) {
                pool.autoPause();
            }
        }
    }

    /** App ist zurück: angehaltene Töne fortsetzen. */
    public static void resume() {
        synchronized (LOCK) {
            if (pool != null) {
                pool.autoResume();
            }
        }
    }

    /**
     * „Nicht stören“ (Beta 1.5.1): Abfrage ohne Berechtigung und ohne Dialog. Die App umgeht den Filter bewusst nicht (kein
     * USAGE_ALARM o. ä.); sie sagt nur, dass Android die Spieltöne stummschaltet. Ergebnis: Unterbrechungsfilter
     * (1 alles, 2 nur Priorität, 3 gar nichts, 4 nur Wecker, 0 unbekannt).
     */
    public static int interruptionFilter() {
        synchronized (LOCK) {
            try {
                if (appContext == null) {
                    return 0;
                }
                NotificationManager nm = (NotificationManager) appContext.getSystemService(Context.NOTIFICATION_SERVICE);
                return nm == null ? 0 : nm.getCurrentInterruptionFilter();
            } catch (RuntimeException e) {
                return 0;
            }
        }
    }

    /** Bei „nur Priorität“: erlaubte Kategorien (Bitmaske, Medien = 64, Android 9+); -1 = nicht lesbar. */
    public static int priorityCategories() {
        synchronized (LOCK) {
            try {
                if (appContext == null || Build.VERSION.SDK_INT < 23) {
                    return -1;
                }
                NotificationManager nm = (NotificationManager) appContext.getSystemService(Context.NOTIFICATION_SERVICE);
                if (nm == null || nm.getNotificationPolicy() == null) {
                    return -1;
                }
                return nm.getNotificationPolicy().priorityCategories;
            } catch (RuntimeException e) {
                return -1;
            }
        }
    }

    /** Kurzer Hinweis (Toast) auf dem Bildschirm. */
    public static void toast(final String text) {
        main.post(() -> {
            try {
                if (appContext != null) {
                    Toast.makeText(appContext, text, Toast.LENGTH_LONG).show();
                }
            } catch (RuntimeException e) {
                Log.w(TAG, "Toast: " + e);
            }
        });
    }
}
