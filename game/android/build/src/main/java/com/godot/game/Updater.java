package com.godot.game;

import android.app.Activity;
import android.app.KeyguardManager;
import android.content.ClipData;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.view.WindowManager;

import androidx.core.content.FileProvider;

import java.io.File;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;

/**
 * Android-Teil der Update-Funktion (übernommen aus Draw2Race 1.0.1). Download und SHA-256-Prüfung erledigt scripts/app/updater.gd;
 * hier: Installationsberechtigung, Signatur-/Versionsprüfung der geladenen APK und Start des System-Installers über den FileProvider
 * der Godot-Bibliothek (Kennung &lt;paket&gt;.fileprovider, gibt files/ frei). Aufruf aus GDScript per JavaClassWrapper (statische
 * Methoden).
 * minSdk ist 24 (Android 7.0): Schnittstellen ab API 26/28 nur hinter Build.VERSION.SDK_INT mit Rückfall. Fehlt eine Methode doch,
 * wirft Android einen Error (NoSuchMethodError) statt einer Exception – darum fangen alle Einstiege Throwable.
 */
public final class Updater {
    private Updater() {}

    @SuppressWarnings("deprecation")
    public static boolean canInstall(Activity activity) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) return activity.getPackageManager().canRequestPackageInstalls();
            // Android 7.x: kein Recht je App, sondern der Schalter „Unbekannte Herkunft“ (Einstellungen → Sicherheit).
            return Settings.Secure.getInt(activity.getContentResolver(), Settings.Secure.INSTALL_NON_MARKET_APPS, 0) == 1;
        } catch (Throwable t) {
            // Unbekannt: Android 7 lässt den System-Installer selbst nachfragen, ab Android 8 lieber die Einstellung anbieten.
            return Build.VERSION.SDK_INT < Build.VERSION_CODES.O;
        }
    }

    /** "" = Einstellung geöffnet, UNLOCK = wartet aufs Entsperren (Ergebnis über launchState). */
    public static String openInstallPermission(Activity activity) {
        try {
            Intent intent = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                    ? new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + activity.getPackageName()))
                    : new Intent(Settings.ACTION_SECURITY_SETTINGS);
            return startSystemDialog(activity, intent);
        } catch (Throwable ignored) {
            return "";
        }
    }

    // --- Systemdialoge und Sperrbildschirm (Beta 1.6.9) ---
    // Befund 16.10.2026 (S10, Testschalter MauMauFlipTestLock an, Handy gesperrt): Die App lag über dem Sperrbildschirm; die Dialoge
    // „Unbekannte Apps installieren“ und „App scannen“ (Play Protect) blitzten nur kurz auf und verschwanden hinter der Sperre, die
    // Installation hing bei 90 %. Systemdialoge erscheinen nie über der Sperre. Darum vor jedem Systemdialog: „über Sperrbildschirm“
    // und „Bildschirm einschalten“ zurücknehmen, bei gesperrtem Gerät um Entsperren bitten und den Dialog erst danach starten.
    // Ohne Sperre startet der Dialog wie bisher sofort.

    /** Rückgabe an GDScript (Updater.UNLOCK_MARK): Der Systemdialog wartet aufs Entsperren, Ergebnis über launchState. */
    public static final String UNLOCK = "@entsperren";

    // Ein Update-Vorgang hat einen Systemdialog angefordert: GodotApp.applyTestLock legt die App danach nicht mehr über den
    // Sperrbildschirm. Gilt bis zum nächsten Prozessstart (statisches Feld).
    private static volatile boolean systemDialogRequested = false;
    // "" = nichts offen, "waiting" = Entsperren angefragt, "started" = entsperrt und Dialog gestartet, "cancelled" = nicht entsperrt.
    private static volatile String launch = "";

    static boolean systemDialogRequested() {
        return systemDialogRequested;
    }

    /** Stand des Entsperrens; "started" und "cancelled" werden beim Abholen gelöscht. */
    public static String launchState() {
        String state = launch;
        if (!"waiting".equals(state)) launch = "";
        return state;
    }

    private static String startSystemDialog(Activity activity, Intent intent) {
        systemDialogRequested = true;
        boolean locked = false;
        // requestDismissKeyguard gibt es ab Android 8.0 (API 26); darunter wird wie bisher sofort gestartet.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                KeyguardManager km = activity.getSystemService(KeyguardManager.class);
                locked = km != null && km.isKeyguardLocked();
            } catch (Throwable ignored) {
            }
        }
        final boolean waitForUnlock = locked;
        launch = waitForUnlock ? "waiting" : "";
        activity.runOnUiThread(() -> {
            leaveLockScreen(activity);
            if (!waitForUnlock) {
                startQuietly(activity, intent);
                return;
            }
            try {
                KeyguardManager km = activity.getSystemService(KeyguardManager.class);
                // Die Activity liegt nach leaveLockScreen hinter der Sperre, wäre ohne sie aber sichtbar – das genügt dem System.
                km.requestDismissKeyguard(activity, new KeyguardManager.KeyguardDismissCallback() {
                    @Override
                    public void onDismissSucceeded() {
                        startQuietly(activity, intent);
                        launch = "started";
                    }

                    @Override
                    public void onDismissCancelled() {
                        launch = "cancelled";
                    }

                    @Override
                    public void onDismissError() {
                        launch = "cancelled";
                    }
                });
            } catch (Throwable t) {
                launch = "cancelled";
            }
        });
        return waitForUnlock ? UNLOCK : "";
    }

    // „Über Sperrbildschirm“ und „Bildschirm einschalten“ zurücknehmen: setShowWhenLocked/setTurnScreenOn ab API 27, davor die
    // Fenster-Flags. Nur auf dem UI-Thread aufrufen.
    @SuppressWarnings("deprecation")
    static void leaveLockScreen(Activity activity) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                activity.setShowWhenLocked(false);
                activity.setTurnScreenOn(false);
            } else if (activity.getWindow() != null) {
                activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                        | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON);
            }
        } catch (Throwable ignored) {
        }
    }

    private static void startQuietly(Activity activity, Intent intent) {
        try {
            activity.startActivity(intent);
        } catch (Throwable ignored) {
        }
    }

    public static String installedVersion(Activity activity) {
        try {
            return activity.getPackageManager().getPackageInfo(activity.getPackageName(), 0).versionName;
        } catch (Throwable e) {
            return "";
        }
    }

    /** Leerer Text = in Ordnung, sonst Fehlerbeschreibung. */
    public static String verify(Activity activity, String path, String version) {
        try {
            PackageManager pm = activity.getPackageManager();
            PackageInfo installed = pm.getPackageInfo(activity.getPackageName(), signatureFlag());
            PackageInfo candidate = pm.getPackageArchiveInfo(path, signatureFlag());
            if (candidate == null) return "APK nicht lesbar (Datei beschädigt?)";
            if (!activity.getPackageName().equals(candidate.packageName)) return "Falsches Paket – die Datei ist nicht Mau-Mau Flip";
            if (versionCode(candidate) <= versionCode(installed)) return "Keine neuere Version (eine ältere wird nie installiert)";
            if (!version.equals(candidate.versionName)) return "Versionsangabe passt nicht zur Datei";
            Set<Signature> current = signers(installed);
            Set<Signature> incoming = signers(candidate);
            if (incoming.isEmpty()) return "Signatur passt nicht – die Datei ist nicht signiert";
            if (current.isEmpty() || !current.equals(incoming)) return "Signatur passt nicht – die Datei stammt nicht vom Mau-Mau-Flip-Projekt oder wurde verändert";
            return "";
        } catch (Throwable e) {
            return "Prüfung fehlgeschlagen: " + e;
        }
    }

    // Signaturen und Versionsnummer: ab Android 9 (API 28) über signingInfo/getLongVersionCode, davor über die alten Felder.
    @SuppressWarnings("deprecation")
    private static int signatureFlag() {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.P ? PackageManager.GET_SIGNING_CERTIFICATES : PackageManager.GET_SIGNATURES;
    }

    @SuppressWarnings("deprecation")
    static long versionCode(PackageInfo info) {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.P ? info.getLongVersionCode() : info.versionCode;
    }

    @SuppressWarnings("deprecation")
    private static Set<Signature> signers(PackageInfo info) {
        Signature[] list;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            list = info.signingInfo == null ? null : info.signingInfo.getApkContentsSigners();
        } else {
            list = info.signatures;
        }
        return list == null ? Collections.emptySet() : new HashSet<>(Arrays.asList(list));
    }

    public static String install(Activity activity, String path) {
        try {
            File file = new File(path);
            Uri uri = FileProvider.getUriForFile(activity, activity.getPackageName() + ".fileprovider", file);
            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setDataAndType(uri, "application/vnd.android.package-archive");
            intent.setClipData(ClipData.newRawUri("MauMauFlip-Update", uri));
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            return startSystemDialog(activity, intent);   // "" oder UNLOCK
        } catch (Throwable e) {
            return "Installation nicht möglich: " + e.getMessage();
        }
    }
}
