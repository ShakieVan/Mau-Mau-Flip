package com.godot.game;

import android.content.Intent;
import android.net.Uri;

/**
 * App-Link „In der App spielen“ (Beta 1.0.2): Die Spielseite des Gastgebers öffnet die App mit
 * maumauflip://join?h=<IP>&p=<Port> (auf Android als intent://…;scheme=maumauflip;package=de.maumauflip.game;…).
 * GodotApp meldet hier jedes Intent beim Start (onCreate) und bei neuem Intent (onNewIntent); die Adresse bleibt gemerkt, bis
 * scripts/app/net_android.gd sie per JavaClassWrapper abholt (take()). Geprüft wird sie erst in GDScript (private IP, Port).
 * Der Intent-Filter hängt an der Activity-Alias .GodotAppLink (AndroidManifest.xml), Ziel ist .GodotApp.
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
}
