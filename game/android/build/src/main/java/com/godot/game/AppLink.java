package com.godot.game;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;

/**
 * App-Link „In der App spielen“ (Beta 1.0.2): Die Spielseite des Gastgebers öffnet die App mit
 * maumauflip://join?h=<IP>&p=<Port> (auf Android als intent://…;scheme=maumauflip;package=de.maumauflip.game;…).
 * Online-Spiel (docs/online/ENTWURF.md): maumauflip://join?r=<Raumcode>&v=<Vermittler> – der Link wird unverändert
 * durchgereicht, geprüft wird er erst in GDScript (scripts/app/net_android.gd, parse_app_link).
 * GodotApp meldet hier jedes Intent beim Start (onCreate) und bei neuem Intent (onNewIntent); die Adresse bleibt gemerkt, bis
 * scripts/app/net_android.gd sie per JavaClassWrapper abholt (take()). Geprüft wird sie erst in GDScript (private IP, Port bzw.
 * Raumcode und Vermittler).
 * Der Intent-Filter hängt an der Activity-Alias .GodotAppLink (AndroidManifest.xml), Ziel ist .GodotApp.
 * Dazu shareText: Teilen-Menü mit einem Text (Raum-Link des Online-Spiels).
 */
public final class AppLink {
    private static volatile String pending = "";

    private AppLink() {}

    /** Intent merken, falls es ein App-Link ist (Schema maumauflip). Alles andere bleibt unbeachtet. */
    public static void remember(Intent intent) {
        if (intent == null || !Intent.ACTION_VIEW.equals(intent.getAction())) {
            return;
        }
        Uri data = intent.getData();
        if (data == null || !"maumauflip".equalsIgnoreCase(data.getScheme())) {
            return;
        }
        String text = data.toString();
        if (text.length() > 512) {
            return;
        }
        pending = text;
    }

    /** Gemerkten Link abholen und vergessen ("" = keiner). */
    public static synchronized String take() {
        String out = pending;
        pending = "";
        return out == null ? "" : out;
    }

    /** Gemerkten Link nur ansehen (für Tests/Log). */
    public static String peek() {
        return pending == null ? "" : pending;
    }

    /** Teilen-Menü mit einem Text (Messenger, E-Mail …). Leerer Text = geöffnet, sonst Fehlerbeschreibung. */
    public static String shareText(Activity activity, String text, String title) {
        try {
            Intent send = new Intent(Intent.ACTION_SEND);
            send.setType("text/plain");
            send.putExtra(Intent.EXTRA_TEXT, text);
            Intent chooser = Intent.createChooser(send, title);
            activity.runOnUiThread(() -> {
                try {
                    activity.startActivity(chooser);
                } catch (Throwable ignored) {
                }
            });
            return "";
        } catch (Throwable e) {
            return "Teilen nicht möglich: " + e.getMessage();
        }
    }
}
