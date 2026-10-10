class_name FunTexts
extends RefCounted
# Freche Sprüche (Beta 1.4.4, Ostereier Teil 1, Nutzerwunsch 10.10.2026): Statt des Standardtextes der Hinweisleiste erscheint
# gelegentlich ein Spruch – nur auf diesem Gerät, nichts wird an andere geschickt. Reine Logik (testbar, test_fun_texts.gd);
# der Tisch (TableView) hängt sich an drei Stellen ein: Ereignisse (observe), Hinweis (hint_for) und Zeit (tick).
# Der Browser-Client hat dieselben Sprüche und Regeln in webclient/spass.js (test_web_contract prüft den Gleichlauf).
#
# Einstellung "sprueche" je Gerät: aus (nur Standardtexte) | nett (ohne die frechen) | frech (alles, ab Werk).
# Regeln:
#   - Ersetzt wird nur ein harmloser Standardtext: „Du bist dran – …“ (wenn etwas passt) bzw. „%s ist dran.“ (Phase turn, keine
#     Strafe offen). Nie bei Farbwahl, Strafe, Mau-Pflicht („Denk an „Mau!““), Erwischen, Ablege-Auswahl, Glücksspiel,
#     Fehlermeldungen (Meldungen laufen ohnehin getrennt) und nie, solange der Weitergeben-Sichtschutz liegt (blocked).
#   - Ein Spruch steht SHOW_TIME s, danach kommt der Standardtext zurück (Häufigkeit „immer“: er bleibt stehen). Zufällige Sprüche
#     frühestens (Abklingzeit der Häufigkeit) s nach dem Ende des letzten; seltene Anlässe (Richtungswechsel, Pechsträhne, Farbjagd,
#     „Autsch“, Glück, Trödeln) mindestens GAP s danach (bei „immer“ sofort). Nie dieselbe Zeile kurz hintereinander: jeder Anlass
#     mischt seine Zeilen und geht sie der Reihe nach durch.
#   - Sprüche verraten keine Karten (nur öffentliche Kartenzahlen); Namen sind echte Mitspieler (keine Computergegner).

const SETTING := "sprueche"
const LEVELS := ["aus", "nett", "frech"]
const LEVEL_NAMES := [["aus", "Aus"], ["nett", "Nett"], ["frech", "Frech"]]
const DEFAULT := "frech"

# Einstellung "sprueche_oft" je Gerät (Beta 1.4.5, Nutzerwunsch 10.10.2026: „die Sprüche kommen sehr selten“): wie oft ein Spruch kommt.
# selten | normal | oft (ab Werk) | immer. Nur wirksam, wenn "sprueche" nicht "aus" ist.
#   Zug: Chance auf einen Spruch zum eigenen Zugbeginn; Abklingzeit: Pause nach dem Ende des letzten Spruchs; seltene Anlässe
#   (viele/wenige Karten, Richtungswechsel, eigenes Fertigwerden): selten ×0,6, normal wie bisher, oft ×1,8 (höchstens 0,95), immer 1.
#   immer: jeder eigene Zug und jeder Anlass bekommt einen Spruch, keine Abklingzeit; der Spruch bleibt stehen, bis ein neuer Anlass
#   (frühestens nach IMMER_MIN_SHOW s), der Zugwechsel oder ein wichtiger Hinweis kommt – die Standardtexte sind damit ersetzt.
const FREQ_SETTING := "sprueche_oft"
const FREQS := ["selten", "normal", "oft", "immer"]
const FREQ_NAMES := [["selten", "Selten"], ["normal", "Normal"], ["oft", "Oft"], ["immer", "Immer"]]
const FREQ_DEFAULT := "oft"
const FREQ_TURN := {"selten": 0.15, "normal": 0.35, "oft": 0.65, "immer": 1.0}
const FREQ_COOLDOWN := {"selten": 40.0, "normal": 15.0, "oft": 5.0, "immer": 0.0}
const FREQ_RARE := {"selten": 0.6, "normal": 1.0, "oft": 1.8, "immer": 1.0}   # Faktor für die seltenen Anlässe
const RARE_CAP := 0.95          # oft: höchstens so wahrscheinlich
const IMMER_MIN_SHOW := 1.5     # immer: so lange steht ein Spruch mindestens, bevor ein neuer Anlass ihn ablöst

const NOTHING_FITS_TEXT := "Du bist dran – nichts passt, zieh eine Karte."   # Standardhinweis (mau_game.gd), Anlass "nichts_passt"

const SHOW_TIME := 7.0         # so lange steht ein Spruch
const GAP := 4.0                # seltene Anlässe: Mindestabstand (nie direkt hintereinander)
const QUEUE_LIFE := 6.0         # ein Anlass, der so lange nicht gezeigt werden konnte, verfällt
const MANY_CHANCE := 0.5        # Grundwerte der seltenen Anlässe (Häufigkeit „normal“), siehe FREQ_RARE
const FEW_CHANCE := 0.4
const REVERSE_CHANCE := 0.6
const NAME_CHANCE := 0.35       # Stufe frech: Anteil der Sprüche mit einem Mitspielernamen
const SLOW_SELF := [15.0, 30.0] # eigener Zug: Trödel-Sprüche nach so vielen Sekunden
const SLOW_OTHER := 25.0        # anderer Mensch am Zug: Kommentar auf diesem Gerät
const MANY := 12                # „sehr viele Karten“
const FEW_MIN := 2
const FEW_MAX := 3
const STREAK := 3               # Glücksspiel-Treffer in Folge
const JAGD_MANY := 8            # Farbjagd: so viele gezogene Karten
const AUTSCH_AMOUNT := 5        # +5 (oder mehr) auf jemanden mit 1 Karte
const TIP_CHANCE := 0.1         # Stufe frech: Anteil der falschen Tipps („Zieh!“) unter den Zugsprüchen
const GLUECK_STAKE := 3         # Glücksspiel: so viele Drücke ohne Treffer, dann aufgehört oder Hand leer → Glück
const GLUECK_DISCARD := 4       # „Farbe mit ablegen“: so viele Karten mit abgelegt → Glück
const GLUECK_FINISH_CHANCE := 0.5  # eigene Hand leer (Platz belegt): so oft ein Glücks-Spruch

# Anlässe, die die Zeilen eines anderen mitbenutzen (Pech auf dich: Farbjagd, +5 auf deine letzte Karte)
const ALIAS := {"farbjagd_du": "pech_du", "autsch_du": "pech_du"}

# Anlass → [[deutscher Text (msgid in game/i18n/en_fun.po), Stufe]]; Stufe "nett" erscheint in nett und frech, "frech" nur in frech.
# Quelle: docs/module/sprueche.md (je Anlass 20). %s: bei zug_name/langsam_andere/pech/farbjagd der Name eines Mitspielers
# (kommt er zweimal vor, steht er zweimal). "tipp" = falscher Tipp beim eigenen Zug, "verarscht" = Pointe nach dem Ziehen.
const LINES := {
	"zug": [
		["Die anderen warten schon auf dich.", "nett"],
		["Was ist eigentlich deine Lieblingsfarbe?", "nett"],
		["Die Karten welcher Farbe stören dich am meisten?", "nett"],
		["Tu einfach so, als würdest du einen fiesen Plan schmieden.", "nett"],
		["Bühne frei für dich!", "nett"],
		["Alle Augen auf dich.", "nett"],
		["Jetzt kommt dein großer Auftritt.", "nett"],
		["Na, schon eine Idee?", "nett"],
		["Zeig mal, was du draufhast.", "nett"],
		["Deine Karten, deine Entscheidung.", "nett"],
		["Ganz ruhig – du schaffst das.", "nett"],
		["Die Katze schaut gespannt zu.", "nett"],
		["Heute ist dein Glückstag. Vielleicht.", "nett"],
		["Mach was Schlaues. Oder was Lustiges.", "nett"],
		["Jetzt nur nicht die falsche Farbe erwischen.", "nett"],
		["Spannung! Was legst du?", "nett"],
		["Dein Moment ist gekommen.", "nett"],
		["Erst denken, dann legen. Oder umgekehrt.", "nett"],
		["Die Ablage hat Hunger.", "nett"],
		["Leg los – im wahrsten Sinne.", "nett"],
	],
	"zug_name": [
		["%s hat gesagt, du wärst doof! Zahl's heim!", "frech"],
		["%s hat dir gerade in die Karten geguckt. Ich hab's genau gesehen.", "frech"],
		["%s lacht schon über deine Karten.", "frech"],
		["%s meint, du verlierst sowieso.", "frech"],
		["Zeig %s mal, wo der Hammer hängt.", "frech"],
		["%s hat heimlich Karten gezählt. Pass auf!", "frech"],
		["Gerüchten zufolge blufft %s.", "frech"],
		["%s hat eben die Augen verdreht. Rache?", "frech"],
		["Du weißt, was zu tun ist: %s ärgern.", "frech"],
		["%s hat behauptet, du kannst nicht mischen.", "frech"],
		["Ich würde ja %s eine reinwürgen. Nur so ein Gedanke.", "frech"],
		["%s grinst verdächtig. Sei auf der Hut.", "frech"],
		["%s hat gerade gegähnt. Weck %s mal auf!", "frech"],
		["Für %s wäre jetzt ein „+5“ genau richtig.", "frech"],
		["%s hält dich für harmlos. Beweis das Gegenteil.", "frech"],
		["Psst: %s hat nur noch schlechte Karten. Glaube ich.", "frech"],
		["%s hat gesagt, Katzen sind doof. Unverzeihlich!", "frech"],
		["%s hat dich „Anfänger“ genannt. Tu was!", "frech"],
		["Wenn du %s jetzt aussetzen lässt, sag ich nichts.", "frech"],
		["%s wettet gegen dich. Mit Keksen.", "frech"],
	],
	"nichts_passt": [
		["Nichts passt. Ab zum Stapel!", "nett"],
		["Leider nix dabei. Zieh eine!", "nett"],
		["Deine Karten streiken. Zieh eine neue.", "nett"],
		["Keine passt? Dann ab zum Ziehstapel.", "nett"],
		["Tja, nichts dabei. Der Stapel wartet schon.", "nett"],
		["Nix zu machen – zieh eine Karte.", "nett"],
		["Die Ablage mag gerade keine deiner Karten. Zieh!", "nett"],
		["Kein Treffer auf der Hand. Zieh eine.", "nett"],
		["Passt nicht, gibt's nicht? Doch. Zieh eine.", "nett"],
		["Deine Hand hat heute frei. Zieh eine Karte.", "nett"],
		["Leere Versprechen auf der Hand. Zieh!", "nett"],
		["Nichts passt – Zeit für Nachschub vom Stapel.", "nett"],
		["Ab zum Buffet: eine Karte vom Stapel, bitte.", "nett"],
		["Keine Chance. Der Stapel ruft.", "nett"],
		["Fehlanzeige! Zieh eine Karte.", "nett"],
		["Da passt nix. Ziehen, bitte.", "nett"],
		["Pech gehabt – nimm eine vom Stapel.", "nett"],
		["Zieh eine. Vielleicht ist ja die richtige dabei.", "nett"],
		["Deine Karten sind sich einig: Ziehen!", "nett"],
		["Nichts passt zusammen. Wie bei Socken. Zieh eine.", "nett"],
		["Der Stapel hat Sehnsucht nach dir. Zieh!", "nett"],
		["Keine passende Karte? Dann gibt's Nachschub.", "nett"],
		["Kartenflaute. Zieh eine.", "nett"],
		["Mit dieser Hand wird das nix. Zieh eine.", "nett"],
		["Die Farbe stimmt nicht, die Zahl auch nicht. Zieh!", "nett"],
		["Gut gemischt, schlecht getroffen. Zieh eine.", "nett"],
		["Shopping-Zeit: eine Karte vom Stapel.", "nett"],
		["Nix passt? Willkommen im Club. Zieh eine.", "nett"],
		["Deine Karten sind heute einfach nutzlos. Zieh eine.", "frech"],
		["Nichts passt. Ab zum Stapel, aber flott!", "frech"],
		["Nichts passt. War ja klar. Zieh eine.", "frech"],
		["Die Katze empfiehlt: eine vom Stapel ziehen.", "nett"],
		["Ziehen ist auch eine Strategie.", "nett"],
		["Kein Match. Nach links wischen – und eine ziehen.", "nett"],
		["Leider kein Volltreffer. Zieh eine Karte.", "nett"],
		["Der Stapel hat bestimmt was Passendes. Zieh!", "nett"],
		["Nichts zu legen, aber was zu ziehen!", "nett"],
		["Zieh eine – das Glück wartet vielleicht oben.", "nett"],
		["Nichts passt. Die anderen freuen sich schon. Zieh!", "frech"],
		["Deine Hand: viel Auswahl, null Treffer. Zieh eine.", "frech"]
	],
	"tipp": [
		["Im Ziehstapel liegt vielleicht genau die Karte, die du brauchst. Schau mal nach.", "frech"],
		["Oben auf dem Stapel liegt ein Joker. Ganz sicher.", "frech"],
		["Die nächste Karte ist bestimmt in deiner Lieblingsfarbe.", "frech"],
		["Psst: Ziehen lohnt sich gerade besonders.", "frech"],
		["Ich hab gehört, der Stapel verteilt heute Geschenke.", "frech"],
		["Der Ziehstapel hat dir gerade zugezwinkert.", "frech"],
		["Da wartet eine Überraschung im Stapel auf dich.", "frech"],
		["Zieh doch mal – nur so zum Spaß.", "frech"],
		["Die Katze sagt, im Stapel liegt was Gutes.", "frech"],
		["Heute gibt's im Stapel zwei zum Preis von einer.", "frech"],
		["Ich würde jetzt ziehen. Vertrau mir.", "frech"],
		["Der Stapel ist heute in Spendierlaune.", "frech"],
		["Gerüchten zufolge liegt da ein Joker ganz oben.", "frech"],
		["Die oberste Karte glänzt so verheißungsvoll.", "frech"],
		["Ein Blick in den Stapel kann nicht schaden. Oder?", "frech"],
		["Dein Glück liegt nur eine Karte entfernt.", "frech"],
		["Zieh! Der Stapel hat dich lieb.", "frech"],
		["Mein sechster Sinn sagt: ziehen!", "frech"],
		["Ich hab da so ein Gefühl beim Stapel …", "frech"],
		["Die beste Karte des Spiels wartet auf dich. Im Stapel.", "frech"],
	],
	"verarscht": [
		["Hehe, verarscht!", "frech"],
		["War gelogen.", "nett"],
		["Reingefallen!", "nett"],
		["Ups, falscher Stapel.", "nett"],
		["Hab ich das gesagt? Muss jemand anderes gewesen sein.", "nett"],
		["Na, wenigstens hast du jetzt eine Karte mehr.", "nett"],
		["Kleiner Scherz unter Freunden.", "nett"],
		["Die Katze hat gelogen, nicht ich.", "nett"],
		["Haha! Der älteste Trick der Welt.", "nett"],
		["Tja. Glaub nicht alles, was auf dem Bildschirm steht.", "nett"],
		["Mein sechster Sinn hat heute frei.", "nett"],
		["Ich nehm alles zurück.", "nett"],
		["Das war ein Test. Du hast bestanden. Nicht.", "frech"],
		["Erwischt – diesmal du!", "nett"],
		["Gerüchte sind halt Gerüchte.", "nett"],
		["Oh. Das war wohl doch nichts.", "nett"],
		["Sorry, ich konnte nicht widerstehen.", "nett"],
		["Wenigstens ehrlich gezogen.", "nett"],
		["Der Stapel war heute doch geizig.", "nett"],
		["Nächstes Mal glaubst du mir bestimmt wieder.", "nett"],
	],
	"langsam": [
		["Worauf wartest du, Weihnachten?", "nett"],
		["Wenn du noch länger brauchst, schlafen alle ein.", "nett"],
		["Trink ruhig aus, wir haben Zeit. *hust hust*", "frech"],
		["Lass die anderen ruhig schmoren.", "nett"],
		["Die Katze ist schon eingeschlafen.", "nett"],
		["Soll ich dir einen Kaffee bringen?", "nett"],
		["Schach ist ein anderes Spiel.", "nett"],
		["Die Karten werden vom Anschauen nicht besser.", "nett"],
		["Hallo? Jemand zu Hause?", "nett"],
		["Ich hab inzwischen die Steuererklärung gemacht.", "nett"],
		["Kleiner Tipp: Irgendeine Karte geht immer. Fast.", "nett"],
		["Die anderen altern gerade sichtbar.", "frech"],
		["Das ist kein Schönheitswettbewerb. Leg einfach was.", "nett"],
		["Tick, tack, tick, tack …", "nett"],
		["Mein Akku ist gleich leer. Deiner auch?", "nett"],
		["Noch eine Runde Nachdenken, und es ist Frühling.", "nett"],
		["Die Ablage fragt, ob du sie vergessen hast.", "nett"],
		["Du denkst so laut, man hört es bis hier.", "nett"],
		["Grübel, grübel und studier …", "nett"],
		["Nimm dir Zeit. Aber nicht ALLE Zeit.", "nett"],
	],
	"langsam_andere": [
		["%s schmiedet offenbar einen Masterplan.", "nett"],
		["%s denkt nach. Das kann dauern.", "nett"],
		["Wetten, %s hat die Regeln vergessen?", "frech"],
		["%s zählt heimlich Schäfchen.", "nett"],
		["Ob %s eingeschlafen ist?", "nett"],
		["%s sucht noch die passende Farbe. Seit Stunden.", "nett"],
		["%s braucht wohl einen Taschenrechner.", "frech"],
		["Zeit für einen Snack – %s braucht noch.", "nett"],
		["%s meditiert gerade.", "nett"],
		["Achtung, %s denkt! Bitte nicht stören.", "nett"],
		["Hat jemand %s gesehen?", "nett"],
		["%s schreibt vermutlich gerade ein Buch.", "nett"],
		["Bis %s legt, kannst du in Ruhe Tee kochen.", "nett"],
		["%s plant was Fieses. Ganz sicher.", "nett"],
		["%s hat den Faden verloren. Und die Karten.", "frech"],
		["Man hört förmlich, wie es bei %s rattert.", "nett"],
		["%s wartet auf eine Eingebung.", "nett"],
		["Das Universum dehnt sich aus. %s denkt noch.", "nett"],
		["Vielleicht braucht %s einen Wecker.", "nett"],
		["%s macht es heute spannend.", "nett"],
	],
	"viele": [
		["Komm schon, zieh noch eine. Das macht das Kraut auch nicht mehr fett.", "nett"],
		["Lass den anderen auch noch ein paar Karten.", "nett"],
		["Du könntest auch einfach aufgeben.", "frech"],
		["Sammelst du die etwa?", "nett"],
		["Deine Hand braucht bald einen Anbau.", "nett"],
		["Beeindruckende Sammlung!", "nett"],
		["Planst du einen eigenen Kartenladen?", "nett"],
		["Ein Fächer? Das ist schon ein Sonnenschirm.", "nett"],
		["Wenigstens wird dir beim Sortieren nicht langweilig.", "nett"],
		["Das sind ja mehr Karten als Freunde.", "frech"],
		["Wer viel hat, kann viel legen. Theoretisch.", "nett"],
		["Der Ziehstapel vermisst dich schon.", "nett"],
		["Hast du den halben Stapel abonniert?", "nett"],
		["Kopf hoch, Rekorde sind auch was wert.", "nett"],
		["Halte durch, es kann nur besser werden. Glaube ich.", "nett"],
		["Deine Karten haben Karten bekommen.", "nett"],
		["Noch zehn mehr und du bekommst einen Pokal.", "nett"],
		["Wenigstens hast du jetzt Auswahl.", "nett"],
		["Du siehst aus wie ein Fächer-Model.", "nett"],
		["Das wird ein langer Abend für dich.", "nett"],
	],
	"wenige": [
		["Du bist bald fertig – oder hast du einfach keine Lust mehr?", "nett"],
		["Komm schon, willst du jetzt schon fertig machen?", "nett"],
		["Wenn du jetzt fertig machst, kannst du nur noch zuschauen.", "nett"],
		["Willst du die anderen nicht noch etwas länger leiden sehen?", "frech"],
		["Die anderen werden langsam nervös.", "nett"],
		["Ganz schön eilig heute, was?", "nett"],
		["Vergiss das „Mau!“ nicht!", "nett"],
		["Gleich ist es geschafft. Oder doch nicht?", "nett"],
		["Die Ziellinie ist in Sicht!", "nett"],
		["Psst – nicht zu früh freuen.", "nett"],
		["Die anderen schmieden schon Rachepläne.", "nett"],
		["Fast leer – fast genial.", "nett"],
		["Nur nicht übermütig werden.", "nett"],
		["Wer zuletzt lacht …", "nett"],
		["Die Karten verlassen dich. Verständlich.", "frech"],
		["Noch ein paar Züge bis zum Ruhm.", "nett"],
		["Jetzt bloß kein „+5“ kassieren.", "nett"],
		["Ich spüre einen Sieg … oder ist das Hunger?", "nett"],
		["Halt dich fest, gleich wird's spannend.", "nett"],
		["Sieht gut aus. Zu gut.", "nett"],
	],
	"richtung": [
		["Und jetzt rückwärts. Alle kotzen schon.", "frech"],
		["Rückwärtsgang eingelegt!", "nett"],
		["Kommando zurück!", "nett"],
		["Alles andersrum – wie im Spiegel.", "nett"],
		["Uff, mir wird schwindelig.", "nett"],
		["Einmal im Kreis und zurück.", "nett"],
		["Wer hat am Lenkrad gedreht?", "nett"],
		["Rolle rückwärts!", "nett"],
		["Umleitung! Bitte der Beschilderung folgen.", "nett"],
		["Moonwalk-Modus aktiviert.", "nett"],
		["Die Erde dreht sich jetzt andersrum. Fast.", "nett"],
		["Rückwärts ist das neue Vorwärts.", "nett"],
		["Halt, falsche Richtung! Ach nee, Absicht.", "nett"],
		["Kehrtwende!", "nett"],
		["Und alle drehen sich um. Schwindelfrei?", "nett"],
		["Der Zug fährt jetzt in die Gegenrichtung.", "nett"],
		["Zurück auf Los. Aber nur die Richtung.", "nett"],
		["Wer eben noch zuletzt kam, kommt jetzt zuerst.", "nett"],
		["Uhrzeigersinn ist sowieso überbewertet.", "nett"],
		["Bitte anschnallen, es geht rückwärts.", "nett"],
	],
	"pech_du": [
		["Autsch!", "nett"],
		["Das tat weh.", "nett"],
		["Farbenblind?", "frech"],
		["Heute ist nicht dein Tag, oder?", "nett"],
		["Mitgefangen, mitgehangen.", "nett"],
		["Die Karten mögen dich. Sehr.", "nett"],
		["Na, Hauptsache, die anderen freuen sich.", "nett"],
		["Das gibt einen blauen Fleck.", "nett"],
		["Kopf hoch, schlimmer geht immer.", "nett"],
		["Wer zuletzt lacht … bist wohl nicht du.", "frech"],
		["Das war gemein. Herrlich gemein.", "nett"],
		["Gesammelte Werke, Band 2.", "nett"],
		["Und plötzlich: Kartenflut.", "nett"],
		["Mein Beileid.", "nett"],
		["Das Universum hat entschieden.", "nett"],
		["Ziehen, ziehen, ziehen …", "nett"],
		["Pech im Spiel, Glück in der Liebe.", "nett"],
		["Rache ist süß – merk dir das.", "nett"],
		["Huch, wo kommen die alle her?", "nett"],
		["Kleiner Rückschlag. Ganz kleiner. Okay, großer.", "nett"],
	],
	"pech": [
		["%s hat heute echt kein Glück.", "nett"],
		["Der Automat mag %s. Leider.", "nett"],
		["%s zockt heute mit dem Feuer.", "nett"],
		["%s und das Glücksspiel – eine tragische Liebesgeschichte.", "frech"],
		["Jemand sollte %s das Zocken verbieten.", "frech"],
		["Die Glückssträhne von %s ist eher eine Pechsträhne.", "frech"],
	],
	"farbjagd": [
		["Farbenblind, %s?", "frech"],
		["%s hat die halbe Ablage gefunden.", "nett"],
		["%s hat lange gesucht.", "nett"],
		["%s sammelt Karten wie andere Briefmarken.", "nett"],
		["Bei %s wird die Hand gerade sehr voll.", "nett"],
	],
	"autsch": [
		["Autsch!", "nett"],
		["Das tat weh.", "nett"],
		["So knapp vor dem Ziel. Autsch!", "nett"],
		["So kurz vor Schluss – das tut weh.", "nett"],
		["Fast fertig und dann das. Gemein!", "nett"],
		["Hehe. Ich meine: Oh nein!", "frech"],
	],
	"glueck": [
		["Läuft bei dir!", "nett"],
		["Glückspilz!", "nett"],
		["Das Glück ist mit dir.", "nett"],
		["Schon wieder? Unglaublich.", "nett"],
		["Hast du einen Glücksbringer dabei?", "nett"],
		["Die Karten lieben dich heute.", "nett"],
		["Volltreffer!", "nett"],
		["Dir droht bald Spielbank-Verbot!", "nett"],
		["Dir gelingt heute alles.", "nett"],
		["Respekt!", "nett"],
		["Wie machst du das nur?", "nett"],
		["Die anderen staunen.", "nett"],
		["Ein Hoch auf dich!", "nett"],
		["Sieht nach Talent aus. Oder nach Glück.", "nett"],
		["Bitte etwas von dem Glück abgeben.", "nett"],
		["Die Katze ist beeindruckt.", "nett"],
		["Zufall? Ich glaube nicht.", "nett"],
		["Jetzt nur nicht abheben.", "nett"],
		["So sehen Gewinner aus.", "nett"],
		["Bravo, weiter so!", "nett"],
	],
}

var level := DEFAULT
var freq := FREQ_DEFAULT
var nothing_ok := true           # false = „Spielbare Karten hervorheben“ aus: ein Spruch „nichts passt“ würde es verraten → nie
var _nofit := false              # der Hinweis ist gerade der reine „nichts passt, zieh eine Karte“-Fall (ersetzbar durch Anlass nichts_passt)
var rng := RandomNumberGenerator.new()
var now := 0.0                   # Sekunden seit Beginn (tick)
var text := ""                   # gerade angezeigter Spruch (fertig übersetzt); "" = keiner
var line := ""                   # sein deutscher Text (msgid), für Tests
var occasion := ""               # sein Anlass
var _until := -1.0
var _last_end := -1000.0
var _shown_turn := -2
var _queued := {}                # {occ, name, t}
var _notice := ""                # Pointe des falschen Tipps (als Meldung)
var _my_seat := -99
var _my_turn := false
var _turn_start := 0.0
var _start_due := false          # eigener Zug begonnen, Entscheidung steht noch aus (z. B. hinter dem Sichtschutz)
var _slow_done := 0
var _blocked := false
var _replaceable := false
var _other_seat := -1
var _other_start := 0.0
var _other_done := false
var _other_name := ""
var _fake_armed := false
var _streak := {}                # Platz → Glücksspiel-Treffer in Folge
var _jagd_victim := -1
var _last_pick := {}             # Anlass → zuletzt gewählte Zeile
var _bag := {}                   # Anlass → noch nicht gezeigte Zeilen (gemischt), siehe _pick
var _shown_at := 0.0             # Zeitpunkt, an dem der stehende Spruch erschien
var _picked := ""                # deutscher Text der zuletzt gewählten Zeile
var _asked := -1000.0


func _init() -> void:
	rng.randomize()


static func clean_level(v: Variant) -> String:
	var s := str(v)
	return s if LEVELS.has(s) else DEFAULT


static func clean_freq(v: Variant) -> String:
	var s := str(v)
	return s if FREQS.has(s) else FREQ_DEFAULT


func set_freq(v: Variant) -> void:
	var f := clean_freq(v)
	if f == freq:
		return
	freq = f
	_end()                           # ein stehender Spruch endet; die Hinweisleiste wird neu aufgebaut


# Chance eines seltenen Anlasses bei der eingestellten Häufigkeit (base = Wert für „normal“)
func rare(base: float) -> float:
	if freq == "immer":
		return 1.0
	var f := float(FREQ_RARE[freq])
	return minf(RARE_CAP, base * f) if f > 1.0 else base * f


func turn_chance() -> float:
	return float(FREQ_TURN[freq])


func cooldown() -> float:
	return float(FREQ_COOLDOWN[freq])


func _gap() -> float:
	return 0.0 if freq == "immer" else GAP


func set_level(v: Variant) -> void:
	var old := level
	level = clean_level(v)
	if level != old:
		_bag = {}
	if level == "aus":
		_end()
		_queued = {}
		_fake_armed = false
		_notice = ""


# Zeilen eines Anlasses für eine Stufe (aus = keine)
static func lines_for(occ: String, lvl: String) -> Array:
	var out: Array = []
	if lvl == "aus":
		return out
	for e in LINES.get(ALIAS.get(occ, occ), []):
		if lvl == "frech" or str(e[1]) == "nett":
			out.append(str(e[0]))
	return out


# Alle deutschen Texte (Tests, Übersetzungs- und Browser-Abgleich)
static func all_lines() -> Array:
	var out: Array = []
	for occ in LINES:
		for e in LINES[occ]:
			if not out.has(str(e[0])):
				out.append(str(e[0]))
	return out


# Darf der Standardtext dieses Hinweises durch einen Spruch ersetzt werden? Nur harmlose Zugtexte, nie wichtige Hinweise.
static func replaceable(v: Dictionary, h: Dictionary, my_seat: int) -> bool:
	if str(v.get("phase", "")) != "turn":
		return false
	var pend: Variant = v.get("pending", {})
	if pend is Dictionary and not (pend as Dictionary).is_empty():
		return false
	var dp: Variant = v.get("discard_pick", {})
	if dp is Dictionary and not (dp as Dictionary).is_empty():
		return false
	if bool(h.get("need_color", false)) or bool(h.get("can_challenge", false)):
		return false
	var c: Variant = h.get("catch", [])
	if c is Array and not (c as Array).is_empty():
		return false
	var t := str(h.get("text", ""))
	if t.contains("Mau") or t.contains("nichts passt"):
		return false
	var turn := int(v.get("turn", -1))
	if my_seat >= 0 and turn == my_seat:
		return t == "" or t.begins_with("Du bist dran")
	return t == "" or t.ends_with("ist dran.") or t.begins_with("Du bist fertig")


# Der reine „nichts passt, zieh eine Karte“-Fall (Beta 1.4.6): eigener Zug, keine Strafe/Ziehpflicht, keine Auswahl, kein Mau-Zusatz,
# Ziehen möglich. Jeder Spruch des Anlasses "nichts_passt" sagt dasselbe und darf den Hinweis ersetzen.
static func nothing_fits(v: Dictionary, h: Dictionary, my_seat: int) -> bool:
	if my_seat < 0 or str(v.get("phase", "")) != "turn" or int(v.get("turn", -1)) != my_seat:
		return false
	var pend: Variant = v.get("pending", {})
	if pend is Dictionary and not (pend as Dictionary).is_empty():
		return false
	var dp: Variant = v.get("discard_pick", {})
	if dp is Dictionary and not (dp as Dictionary).is_empty():
		return false
	if bool(h.get("need_color", false)) or bool(h.get("can_challenge", false)):
		return false
	var c: Variant = h.get("catch", [])
	if c is Array and not (c as Array).is_empty():
		return false
	return str(h.get("text", "")) == NOTHING_FITS_TEXT


# Ereignisse des Gastgebers (vor der neuen Sicht); before = bisherige Sicht (Kartenzahlen, Namen)
func observe(events: Array, before: Dictionary, my_seat: int) -> void:
	if level == "aus":
		return
	for e in events:
		if not e is Dictionary:
			continue
		var d: Dictionary = e
		var seat := int(d.get("seat", -1))
		match str(d.get("e", "")):
			"reverse":
				if rng.randf() < rare(REVERSE_CHANCE):
					_queue("richtung", "")
			"pending":
				if str(d.get("kind", "")) == "farbjagd":
					_jagd_victim = seat
				elif int(d.get("amount", 0)) >= AUTSCH_AMOUNT and _count_of(before, seat) == 1:
					_queue("autsch_du" if seat == my_seat else "autsch", "")
			"draw":
				var reason := str(d.get("reason", ""))
				if reason == "strafe" and seat == _jagd_victim:
					if int(d.get("count", 0)) >= JAGD_MANY:
						if seat == my_seat:
							_queue("farbjagd_du", "")
						else:
							_queue("farbjagd", _name_of(before, seat))
					_jagd_victim = -1
				if reason == "zug" and seat == my_seat and _fake_armed:
					_fake_armed = false
					_notice = _pick("verarscht", "")
			"gamble_roll":
				if int(d.get("value", 0)) > 0:
					_streak[seat] = int(_streak.get(seat, 0)) + 1
					if int(_streak[seat]) == STREAK:
						if seat == my_seat:
							_queue("pech_du", "")
						else:
							_queue("pech", _name_of(before, seat))
				else:
					_streak[seat] = 0
			"stake_discard":
				# Glücksspiel: mehrere Drücke ohne Treffer überstanden und aufgehört (oder Hand leer)
				if seat == my_seat and int(d.get("count", 0)) >= GLUECK_STAKE:
					_queue("glueck", "")
			"discard_color":
				if seat == my_seat and int(d.get("count", 0)) >= GLUECK_DISCARD:
					_queue("glueck", "")
			"finish":
				if seat == my_seat and rng.randf() < rare(GLUECK_FINISH_CHANCE):
					_queue("glueck", "")
			"round_start", "start", "seats":
				_streak = {}
				_jagd_victim = -1


# Pointe des falschen Tipps („Hehe, verarscht!“) einmal abholen; "" = keine
func take_notice() -> String:
	var n := _notice
	_notice = ""
	return n


# Text für die Hinweisleiste: standard (schon übersetzt) oder ein Spruch. blocked = Weitergeben-Sichtschutz liegt.
func hint_for(v: Dictionary, h: Dictionary, my_seat: int, standard: String, blocked := false) -> String:
	if my_seat != _my_seat:
		_reset_seat(my_seat)
	var turn := int(v.get("turn", -1))
	var phase := str(v.get("phase", ""))
	var playing := phase != "round_over" and phase != "game_over" and phase != "idle" and phase != ""
	var mine := my_seat >= 0 and turn == my_seat and playing
	_blocked = blocked
	_nofit = nothing_ok and level != "aus" and not blocked and nothing_fits(v, h, my_seat)
	_replaceable = level != "aus" and not blocked and (_nofit or replaceable(v, h, my_seat))
	# eigener Zug beginnt / endet
	if mine and not _my_turn:
		_turn_start = now
		_slow_done = 0
		_start_due = true
	elif not mine and _my_turn:
		_fake_armed = false
		_start_due = false
	_my_turn = mine
	if blocked:
		_turn_start = now            # hinter dem Sichtschutz läuft keine Uhr
	# anderer Mensch am Zug: Uhr für den Trödel-Kommentar
	if not mine and playing and turn >= 0 and phase == "turn":
		if turn != _other_seat:
			_other_seat = turn
			_other_start = now
			_other_done = false
		var p := _player_of(v, turn)
		_other_name = str(p.get("name", "")) if str(p.get("kind", "human")) != "bot" and turn != my_seat else ""
	else:
		_other_seat = -1
		_other_name = ""
	# ein laufender Spruch endet, wenn der Zug wechselt oder der Hinweis wichtig wird
	if text != "" and (not _replaceable or turn != _shown_turn or (occasion == "nichts_passt") != _nofit):
		_end()
	if level == "aus" or not _replaceable:
		if not blocked and mine and _start_due and not _replaceable:
			_start_due = false       # wichtiger Hinweis zu Zugbeginn: diesmal kein Spruch
		return standard
	if text != "" and freq == "immer" and _queue_ready(mine) and now - _shown_at >= IMMER_MIN_SHOW:
		_end()                       # ein neuer Anlass löst den stehenden Spruch ab
	if text == "":
		_try_show(v, my_seat, turn, mine)
	return text if text != "" else standard


# Zeit weiterzählen; true = die Hinweisleiste muss neu (Spruch abgelaufen oder ein Trödel-Anlass wartet)
func tick(delta: float) -> bool:
	now += delta
	var refresh := false
	if text != "" and now >= _until:
		_end()
		refresh = true
	if level == "aus" or _blocked:
		return refresh
	if _my_turn and _slow_done < SLOW_SELF.size() and now - _turn_start >= float(SLOW_SELF[_slow_done]):
		_slow_done += 1
		_queue("langsam", "")
		refresh = true
	if not _my_turn and _other_seat >= 0 and _other_name != "" and not _other_done and now - _other_start >= SLOW_OTHER:
		_other_done = true
		if now - _last_end >= cooldown():
			_queue("langsam_andere", _other_name)
			refresh = true
	# wartender Anlass: höchstens zweimal je Sekunde nachfragen, ob er jetzt passt
	if not _queued.is_empty() and _replaceable and now - _asked >= 0.5:
		if text == "" and now - _last_end >= _gap():
			_asked = now
			refresh = true
		elif text != "" and freq == "immer" and now - _shown_at >= IMMER_MIN_SHOW:
			_asked = now             # bei „immer“ löst ein neuer Anlass den stehenden Spruch ab
			refresh = true
	return refresh


func showing() -> bool:
	return text != ""


# --- intern ---

# Wartet ein Anlass, der zu diesem Zug passt? (Trödel-Sprüche gehören zum eigenen Zug, Kommentare über andere nicht dorthin)
func _queue_ready(mine: bool) -> bool:
	if _queued.is_empty() or now - float(_queued.t) > QUEUE_LIFE:
		return false
	if _nofit and _queued.occ != "nichts_passt":
		return false                     # bei „nichts passt“ nur Sprüche, die das Ziehen nennen
	return not ((_queued.occ == "langsam" and not mine) or (_queued.occ == "langsam_andere" and mine))


func _try_show(v: Dictionary, my_seat: int, turn: int, mine: bool) -> void:
	if not _queued.is_empty():
		if now - float(_queued.t) > QUEUE_LIFE:
			_queued = {}
		elif now - _last_end >= _gap():
			var q: Dictionary = _queued
			_queued = {}
			# Trödel-Sprüche gehören zum eigenen Zug, Kommentare zu anderen nicht dorthin
			if not _nofit and not ((q.occ == "langsam" and not mine) or (q.occ == "langsam_andere" and mine)):
				_show(_pick(str(q.occ), str(q.name)), str(q.occ), turn)
				if text != "":
					_start_due = false
					return
	if not (mine and _start_due):
		return
	_start_due = false
	if now - _last_end < cooldown():
		return
	if _nofit:                           # „nichts passt“: wie der Zug-Anlass, aber nur Sprüche, die das Ziehen nennen
		if rng.randf() < turn_chance():
			_show(_pick("nichts_passt", ""), "nichts_passt", turn)
		return
	var n := (v.get("hand", []) as Array).size() if v.get("hand", []) is Array else 0
	var occ := ""
	if n >= MANY and rng.randf() < rare(MANY_CHANCE):
		occ = "viele"
	elif n >= FEW_MIN and n <= FEW_MAX and rng.randf() < rare(FEW_CHANCE):
		occ = "wenige"
	elif rng.randf() < turn_chance():
		occ = "zug"
	if occ == "":
		return
	var name := ""
	if occ == "zug" and level == "frech":
		if rng.randf() < TIP_CHANCE:
			occ = "tipp"
		elif rng.randf() < NAME_CHANCE:
			name = _random_human(v, my_seat)
			if name != "":
				occ = "zug_name"
	var picked := _pick(occ, name)
	_show(picked, occ, turn)
	if occasion == "tipp":
		_fake_armed = true


func _show(t: String, occ: String, turn: int) -> void:
	if t == "":
		return
	text = t
	line = _picked
	occasion = occ
	_until = 1.0e18 if freq == "immer" else now + SHOW_TIME
	_shown_at = now
	_shown_turn = turn


func _end() -> void:
	if text != "":
		_last_end = now
	text = ""
	line = ""
	occasion = ""
	_until = -1.0


func _queue(occ: String, name: String) -> void:
	if lines_for(occ, level).is_empty():
		return
	if (occ == "pech" or occ == "farbjagd" or occ == "langsam_andere") and name == "":
		return
	# wichtigerer Anlass verdrängt keinen schon wartenden
	if not _queued.is_empty() and now - float(_queued.t) <= QUEUE_LIFE:
		return
	_queued = {"occ": occ, "name": name, "t": now}


# Nächste Zeile eines Anlasses (übersetzt, mit Namen): Die Zeilen werden gemischt und der Reihe nach gezeigt, erst dann wieder gemischt –
# nichts wiederholt sich, bevor alle dran waren (bei „immer“ wichtig). Die erste Zeile einer neuen Runde ist nie die zuletzt gezeigte.
# Aliase (Pech auf dich) teilen sich die Tüte.
func _pick(occ: String, name: String) -> String:
	var pool := lines_for(occ, level)
	if pool.is_empty():
		return ""
	var key := str(ALIAS.get(occ, occ))
	var bag: Array = (_bag.get(key, []) as Array).filter(func(s: String) -> bool: return pool.has(s))
	if bag.is_empty():
		bag = pool.duplicate()
		for i in range(bag.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp: Variant = bag[i]
			bag[i] = bag[j]
			bag[j] = tmp
		if bag.size() > 1 and str(bag[bag.size() - 1]) == str(_last_pick.get(key, "")):
			var t: Variant = bag[bag.size() - 1]
			bag[bag.size() - 1] = bag[0]
			bag[0] = t
	var de := str(bag.pop_back())
	_bag[key] = bag
	_last_pick[key] = de
	_picked = de
	return format_line(de, name)


# Übersetzt eine Zeile und setzt den Namen ein
static func format_line(de: String, name: String) -> String:
	var t := I18n.t(de)
	if de.contains("%s"):
		return t.replace("%s", name if name != "" else "?")
	return t


func _reset_seat(my_seat: int) -> void:
	_my_seat = my_seat
	_my_turn = false
	_start_due = false
	_fake_armed = false
	_notice = ""
	_end()


func _random_human(v: Dictionary, my_seat: int) -> String:
	var names: Array = []
	for p in v.get("players", []):
		if not p is Dictionary:
			continue
		var d: Dictionary = p
		if int(d.get("seat", -1)) == my_seat or str(d.get("kind", "human")) == "bot" or str(d.get("name", "")) == "":
			continue
		if d.has("connected") and not bool(d.get("connected", true)):
			continue
		names.append(str(d.name))
	return "" if names.is_empty() else str(names[rng.randi_range(0, names.size() - 1)])


static func _player_of(v: Dictionary, seat: int) -> Dictionary:
	for p in v.get("players", []):
		if p is Dictionary and int((p as Dictionary).get("seat", -1)) == seat:
			return p
	return {}


static func _count_of(v: Dictionary, seat: int) -> int:
	return int(_player_of(v, seat).get("count", -1))


static func _name_of(v: Dictionary, seat: int) -> String:
	return str(_player_of(v, seat).get("name", ""))
