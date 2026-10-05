# Bild-Prompt für das Logo-Motiv (Entwurf C)

## Prompt (englisch)

```
Flat geometric vector logo illustration, Bauhaus and Swiss modern style, like the brand of a
contemporary board game publisher: playful but grown-up, clean and confident.

Subject: an adult tuxedo cat (charcoal black with a cream-white chest, muzzle and paws), built
from simple geometric shapes: circles, half circles, triangles and arcs. The cat sits upright,
seen from the front, head tilted back, looking up and slightly to the right. One front paw is
raised and touches the corner of its open mouth, as if pointing at it while calling out.
Elegant almond-shaped amber eyes with the pupils at the top, small pink triangular nose, mouth
open with two tiny fangs and a pink tongue, a subtle "M" marking on the forehead, thin cream
whiskers. Cute but mature, calm and charming, not childish.

Behind the cat, two large playing cards, slightly fanned:
- Left card, tilted about 12 degrees to the left: the "day" side. Cream paper border, a flat
  sunflower-yellow panel (#FFDD33), a big upright circular sun disc in a deeper golden tone
  whose lower half is cut by three horizontal stripes like a horizon.
- Right card, tilted about 12 degrees to the right: the "night" side. Deep midnight navy
  (#15183C to #07081A), a thin glowing violet neon border, a large crescent moon formed by two
  overlapping circles in violet (#4527A0) with a bright lavender rim (#A891FF), a few small
  four-pointed stars.

A red speech bubble (#B3202A) shaped like a circle with one sharp corner pointing down
toward the cat's mouth, containing the word "Mau!" in a bold geometric sans serif, cream color.

A thin cream outline separates the cat from both cards, like a sticker. Soft flat drop shadow
under the cards. Plain warm off-white background (#EEE6D7). Landscape 16:9 composition,
emblem on the left, empty space on the right for a wordmark.

Style: flat vector, crisp edges, solid color areas, minimal shading, only a soft neon glow on
the night card. High contrast, limited palette: charcoal #262631, cream #F8F2E6, red #B3202A,
yellow #FFDD33, violet #4527A0, lavender #A891FF, navy #15183C.
```

**Negative prompt / avoid:**

```
photorealism, 3D render, fur texture, painterly, sketchy hand-drawn cartoon, childish
proportions, huge baby eyes, gradients on the day card, ovals or tilted ellipses on the cards,
numbers in ovals, drop-shadowed numbers, existing card game logos or branding, text other
than "Mau!", watermark
```

## Erläuterung

- Der Prompt beschreibt dasselbe Motiv wie `logo.svg`: Pose wie in der Referenz (sitzend, Blick nach oben, Pfote am offenen Maul), helle Karte links, dunkle Karte rechts. Der Stil ist flach und geometrisch statt gemalt.
- Die Farben sind als Hex-Werte angegeben, damit das Ergebnis zur Kartenpalette passt. Viele Generatoren treffen sie nur ungefähr; danach in einem Vektorprogramm angleichen.
- Den Schriftzug „Mau-Mau Flip“ besser nicht generieren lassen, weil Bildgeneratoren Schrift oft verfälschen. Rechts bleibt dafür Platz. Der Schriftzug kommt aus `logo.svg` (Jost, OFL).
- Die Negativliste schließt die Markenelemente des bekannten Vorbilds aus (Ovale, Zahlen im Oval, fremde Logos).
- Wird ein KI-Bild verwendet, die Herkunft wie bei Draw2Race dokumentieren (Werkzeug, Datum, Prompt).
