# Deine erste eigene App bauen

> 5 Schritte, ca. 15 Minuten (inklusive Wartezeit fuer den Cloud-Build).
> Voraussetzung: Termux-Bootstrap und Acode-GitHub-Verbindung sind bereits erledigt.

---

## SCHRITT 1 VON 5: PROJEKT HERUNTERLADEN

In Termux eintippen:

```
cd ~/projects
git clone https://github.com/KonradLanz/hello-world-apk.git
cd hello-world-apk
```

---

## SCHRITT 2 VON 5: PROJEKT IN ACODE OEFFNEN

1. Acode oeffnen
2. **Datei → Ordner oeffnen**
3. Zu `hello-world-apk` navigieren → auswaehlen

---

## SCHRITT 3 VON 5: TEXT AENDERN

1. In Acode die Datei **`www/index.html`** oeffnen
2. Diese Zeile suchen:

   ```html
   <h1 id="greeting">Hello World</h1>
   ```

3. Den Text zwischen den spitzen Klammern ersetzen durch:

   ```html
   <h1 id="greeting">Hello, we change the world</h1>
   ```

4. **Speichern** (in Acode: Menue → Speichern, oder Wischgeste je nach Version)

---

## SCHRITT 4 VON 5: AENDERUNG HOCHLADEN

Zurueck in Termux, im Ordner `hello-world-apk`:

```
git add -A
git commit -m "Text geaendert"
git push
```

> Diese drei Befehle sind IMMER GLEICH, IMMER IN DIESER REIHENFOLGE. Mehr braucht es nicht.

---

## SCHRITT 5 VON 5: FERTIGE APP HERUNTERLADEN

1. Im Browser oeffnen: **[github.com/KonradLanz/hello-world-apk/actions](https://github.com/KonradLanz/hello-world-apk/actions)**
2. Warten bis der oberste Eintrag ein **gruenes Haekchen** hat (ca. 3-5 Minuten)
3. Dann zu **[Releases](https://github.com/KonradLanz/hello-world-apk/releases)** wechseln
4. Neueste Version antippen → die `.apk`-Datei herunterladen
5. Datei antippen → **Installieren** erlauben → App oeffnen

---

**Fertig.** Deine eigene App mit deinem eigenen Text laeuft auf deinem Handy. Jede weitere Aenderung: Schritt 3 und 4 wiederholen.

## Wichtig: Immer nur `main`

Dieses Projekt bleibt bewusst einfach: **ein einziger Zweig (`main`)**, keine Branches, kein Merge-Konflikt. Jede Aenderung geht direkt und linear nacheinander auf `main`. Das reicht fuer den Einstieg voellig aus.
