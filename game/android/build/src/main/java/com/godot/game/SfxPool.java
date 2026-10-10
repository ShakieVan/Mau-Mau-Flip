package com.godot.game;

import android.app.Activity;
import android.content.Context;
import android.media.AudioAttributes;
import android.media.SoundPool;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import java.util.HashMap;
import java.util.HashSet;
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
 * Die Töne liegen als Rohressourcen res/raw/sfx_<name>.ogg im Paket (tools/build.ps1 kopiert sie aus game/assets/sfx). Fehlen sie,
 * meldet init 0 und sound.gd spielt wie bisher über Godot.
 */
public final class SfxPool {
    private static final String TAG = "MauMauFlipSfx";
    private static final int MAX_STREAMS = 6;
    private static final Object LOCK = new Object();

    private static SoundPool pool;
    private static Context appContext;
    private static String[] names = new String[0];
    private static final Map<String, Integer> ids = new HashMap<>();
    private static final Set<Integer> ready = new HashSet<>();
    private static final Handler main = new Handler(Looper.getMainLooper());
    private static final Set<Integer> active = new HashSet<>();   // gestartete Streams für stopAll
    private static int fails = 0;

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

    private static int build() {
        if (pool != null) {
            pool.release();
            pool = null;
        }
        ids.clear();
        ready.clear();
        active.clear();
        fails = 0;
        AudioAttributes attrs = new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build();
        SoundPool p = new SoundPool.Builder().setMaxStreams(MAX_STREAMS).setAudioAttributes(attrs).build();
        p.setOnLoadCompleteListener((sp, sampleId, status) -> {
            synchronized (LOCK) {
                if (sp == pool && status == 0) {
                    ready.add(sampleId);
                }
            }
        });
        pool = p;
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
                ids.put(n, p.load(appContext, res, 1));
                found++;
            } catch (RuntimeException e) {
                Log.w(TAG, "Laden " + n + ": " + e);
            }
        }
        Log.i(TAG, "SoundPool bereit: " + found + " Töne");
        return found;
    }

    /** Wie viele Töne fertig geladen sind. */
    public static int readyCount() {
        synchronized (LOCK) {
            return ready.size();
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
                // Ein geladener Ton startet nicht: Vorrat beim nächsten Mal neu anlegen (wie ein frischer App-Start).
                fails++;
                Log.w(TAG, "play " + name + " fehlgeschlagen (" + fails + ")");
                if (fails >= 2 && appContext != null) {
                    build();
                }
            } else {
                fails = 0;
                if (active.size() > 64) {
                    active.clear();
                }
                active.add(stream);
            }
            return stream;
        }
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

    /** Blendet einen Ton in ms Millisekunden von volume auf 0 aus und stoppt ihn. */
    public static void fade(int stream, float volume, int ms) {
        if (stream <= 0) {
            return;
        }
        final int steps = Math.max(1, ms / 40);
        for (int i = 1; i <= steps; i++) {
            final float v = volume * (1f - (float) i / steps);
            final boolean last = i == steps;
            main.postDelayed(() -> {
                synchronized (LOCK) {
                    if (pool == null) {
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
}
