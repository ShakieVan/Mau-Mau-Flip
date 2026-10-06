# Play-Protect-Einspruch für Mau-Mau Flip

Vorbild: Ocean Live-Wallpaper (Einspruch am 13.09.2026, Eingang bestätigt, keine Entscheidung mitgeteilt; laut Nutzer war die Warnung nach etwa einem Tag weg, auch für spätere Versionen).

## Stand

- **06.10.2026:** Einspruch für 0.1.3 eingereicht (Bestätigung „Your email has been sent“, Bild `bestaetigung_20261006.jpg`, nur lokal).
- VirusTotal: Datei 0/65 (https://www.virustotal.com/gui/file/9d9f9c8e58f080d8ad67d9d2fe6514a84189d8c89dc04f3af165393db0329d12), Adressprüfung des GitHub-Downloads 0/93.
- Das Feld „Additional information“ erlaubt höchstens **1000 Zeichen**; eingereicht wurde die Kurzfassung unten.

## Ablauf

1. **APK bei VirusTotal hochladen:** https://www.virustotal.com, Datei `builds/MauMauFlip-0.1.3.apk`. Die APK ist ohnehin öffentlich. Das Formular verlangt den SHA-256 *einer Datei, die bei VirusTotal liegt*.
   - Erwarteter SHA-256 (0.1.3): `9d9f9c8e58f080d8ad67d9d2fe6514a84189d8c89dc04f3af165393db0329d12`
   - Ergebnis notieren (z. B. „0/67“) und den Link in den Text unten eintragen.
2. **Einspruch einreichen:** https://support.google.com/googleplay/android-developer/contact/protectappeals (mit dem eigenen Google-Konto angemeldet).
   - Email address: eigene Adresse. Danach den **Bestätigungslink in der Mail anklicken**, sonst verzögert es sich.
   - Developer name (optional): ShakieVan
   - Application package name: `de.maumauflip.game`
   - SHA256 Hash of the apk: `9d9f9c8e58f080d8ad67d9d2fe6514a84189d8c89dc04f3af165393db0329d12`
   - Additional information: Text unten.
3. Bestätigungsseite als Bild hier ablegen (`bestaetigung_<datum>.png`).

Google antwortet laut Formular nicht („All appeal decisions are final and you will not receive a response“). Jede neue Version hat einen neuen Hash. Ob die Einstufung für spätere Versionen hilft, ist nicht dokumentiert.

## Eingereichte Kurzfassung (991 Zeichen)

```
Mau-Mau Flip is a free, non-commercial card game by a hobby developer (CC BY-NC 4.0), distributed only via GitHub.
Source: https://github.com/ShakieVan/Mau-Mau-Flip
APKs: https://github.com/ShakieVan/Mau-Mau-Flip-Beta/releases
v0.1.3 (code 1003), signed with the developer's own key. VirusTotal: 0/65 detections.
No ads, analytics, accounts, third-party SDKs or data collection.
Permissions: INTERNET, ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE, CHANGE_WIFI_MULTICAST_STATE only for local Wi-Fi multiplayer (the host serves the game on port 24690 in the LAN, UDP discovery). REQUEST_INSTALL_PACKAGES for the in-app updater: it only downloads from the project's own GitHub releases, verifies the SHA-256 and hands the APK to the system installer; the user confirms every install. VIBRATE and WAKE_LOCK for haptics and keeping the screen on. Players can share the APK with nearby friends offline via the share sheet, always user-initiated.
The full source code is public. Thank you for reviewing.
```

## Ausführliche Fassung (zu lang für das Formular, als Vorlage)

```
Mau-Mau Flip is a free, non-commercial card game by an individual hobby developer
(license CC BY-NC 4.0). It is distributed only on GitHub, not on Google Play:
- Source code: https://github.com/ShakieVan/Mau-Mau-Flip
- Test releases (APK): https://github.com/ShakieVan/Mau-Mau-Flip-Beta/releases
Version 0.1.3 (versionCode 1003), signed with the developer's own release key
(certificate SHA-256 85d6f9d94693e675a71ef5348c3e212b5962f793dd1ab1cdf1c86a0dfc8d15cd).
VirusTotal: <ERGEBNIS UND LINK EINTRAGEN>

Users see the Play Protect warning "scan app" when installing. The app contains no ads,
no analytics, no accounts, no third-party SDKs and collects no personal data.

Why each permission is needed:
- INTERNET, ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE, CHANGE_WIFI_MULTICAST_STATE:
  local Wi-Fi multiplayer. One phone hosts a game; others join with the app or a
  browser. The host serves a small web page and WebSocket on port 24690 inside the
  local network and announces the game via UDP broadcast (port 24692). No servers
  on the internet are involved.
- REQUEST_INSTALL_PACKAGES: in-app updater. It only checks the project's own GitHub
  releases, verifies the SHA-256 digest of the download and hands the APK to the
  Android system installer; the user confirms every installation.
- VIBRATE, WAKE_LOCK: haptic feedback and keeping the screen on during a game.

The app can also share its own APK with nearby players (Android share sheet or a
download page on the local network), so friends without internet access on holiday
can join. This is always started by the user.

The complete source code is public for review. Thank you for checking the app.
```
