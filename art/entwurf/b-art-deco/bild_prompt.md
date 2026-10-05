# Bild-Prompt für das Logo-Motiv (Entwurf B „Art déco / Tarot“)

## Erläuterung

Der Prompt beschreibt das Logo aus `logo.svg` als hochwertige Illustration: eine erwachsene, anmutige Smokingkatze (Mitternachtsblau mit elfenbeinfarbenem Latz), sitzend, Kopf nach oben gedreht, Maul offen, eine Vorderpfote am Maul. Dahinter links eine helle Tag-Karte (Sonne), rechts eine dunkle Nacht-Karte (Mond, Sterne, Neon). Die Pose entspricht `art/referenz/katze_pose_entwurf.png`.

Hinweise:

- **Schrift weglassen.** Bildgeneratoren verunstalten Text oft. Am sichersten erzeugt man das Bild ohne Schrift (zweite Prompt-Variante) und setzt Schriftzug und Sprechblase aus `logo.svg` darüber.
- **Pose sichern.** Wenn das Werkzeug ein Referenzbild annimmt, `katze_pose_entwurf.png` als Posenvorlage mit mittlerer Stärke (etwa 0,4–0,6) mitgeben. Den Stil bestimmt dann der Prompt.
- **Format.** 16:9 (z. B. 1600 × 900) für das Logo. Für das App-Symbol eignet sich ein quadratischer Ausschnitt mit Kopf, Pfote und der Tag-Nacht-Scheibe.
- **Herkunft dokumentieren.** Wird ein KI-Bild verwendet, Werkzeug, Datum und Prompt im Projekt festhalten, wie bei Draw2Race.

## Prompt (mit Schriftzug)

```text
Art Deco tarot-style game logo illustration, landscape 16:9, centered composition.

Main subject: an elegant adult tuxedo cat with midnight-navy fur, an ivory chest bib, ivory muzzle and ivory paw tips. The cat sits upright in three-quarter view, head tilted back, looking up toward the upper right, mouth open as if meowing. One front paw is raised and its tip touches the open mouth, a playful "pointing at my mouth" gesture. Large amber-gold eyes, slender graceful neck, refined proportions. Cute but grown-up and sophisticated, never childish.

Style: flat vector illustration with subtle gradients and crisp edges. Fine engraved gold linework on the fur (concentric Art Deco arcs on the haunch, small chevrons on the chest). A thin gold collar with a tiny medallion that is half sun, half crescent moon. Warm golden rim light on the cat's left side (day), cool violet rim light on its right side (night).

Behind the cat: two tall playing cards with rounded corners, slightly fanned apart, upright symmetric designs.
Left card (day): ivory paper, fine gold double frame, an arched window showing a geometric sunrise: an orange sun with concentric ivory rings rising behind stylized mountains, striped water reflections, radiating sunburst rays, small gold fan ornaments in the corners.
Right card (night): midnight blue, glowing violet neon outline, the same arched window with a large glowing violet crescent moon, small four-pointed stars, a row of tiny gold moon phases along the arch, dark mountain silhouettes and thin neon reflection lines on the water.

Near the cat's mouth: a small ivory speech bubble with a gold Art Deco frame containing the word "Mau!".
Below the scene: the wordmark "Mau-Mau Flip" in a bold 1920s Art Deco display typeface, warm gold with a thin dark inline and a gold outer contour; the last two letters "ip" glow soft violet.

Background: deep midnight navy with faint radiating gold sunburst lines, a thin gold halo circle behind the cat, a few sparkling stars on the right side. Luxurious, elegant, balanced, high detail, print quality.
```

## Prompt (ohne Schrift, empfohlen)

```text
Art Deco tarot-style illustration, landscape 16:9, centered composition, no text, no letters.

An elegant adult tuxedo cat with midnight-navy fur, ivory chest bib, ivory muzzle and ivory paw tips sits upright in three-quarter view, head tilted back, looking up to the upper right, mouth open as if meowing, one front paw raised with its tip touching the open mouth. Large amber-gold eyes, slender neck, graceful refined proportions, cute but grown-up. Fine engraved gold linework on the fur, thin gold collar with a tiny half-sun half-moon medallion. Warm golden rim light on the left, cool violet rim light on the right.

Behind the cat two tall rounded playing cards, slightly fanned: left an ivory day card with gold double frame and an arched window showing a geometric orange sunrise over stylized mountains and striped water with sunburst rays; right a midnight-blue night card with violet neon outline, an arched window with a glowing crescent moon, stars, tiny gold moon phases, dark mountains and neon water lines.

Deep midnight navy background with faint gold sunburst lines and a thin gold halo circle. Flat vector style, subtle gradients, crisp edges, luxurious and elegant. Leave empty space below the cat for a wordmark.
```

## Negativ-Prompt (falls das Werkzeug einen annimmt)

```text
oval shape in the card center, tilted or slanted card emblems, numbers with drop shadows, logos or branding of existing card games, extra text, misspelled letters, photorealism, 3D render, chibi, childish cartoon, oversized baby head, extra limbs, extra paws, deformed paws, fused toes, crossed eyes, watermark, signature, frame cropping the cat's ears
```
