# Komplettes Setup — Ein Skript, sechs Schritte

> Fuer alle, die Termux schon installiert haben.
> Das Skript ist **idempotent**: einfach erneut ausfuehren, wenn etwas abbricht —
> es macht automatisch dort weiter, wo aufgehoert wurde. Nichts wird doppelt gemacht.

---

## Der eine Befehl

```
curl -fsSL https://raw.githubusercontent.com/KonradLanz/bootstrap-foundation/main/android/full-setup.sh | sh
```

---

## Was dabei passiert

| Schritt | Was das Skript macht | Was DU tun musst |
|---|---|---|
| 1/6 | Speicherzugriff anfragen | Erlauben antippen, falls gefragt |
| 2/6 | Programme installieren | Nichts, nur warten |
| 3/6 | Git-Name & E-Mail | Namen und E-Mail eintippen (nur beim ersten Mal) |
| 4/6 | Bei GitHub anmelden | Browser oeffnet sich → Code eingeben → bestaetigen (nur beim ersten Mal) |
| 5/6 | Projekte herunterladen | Nichts, nur warten |
| 6/6 | Kurzbefehle einrichten | Nichts |

---

## Warum kein SSH-Key mehr noetig ist

Frueher: `git@github.com: Permission denied (publickey).` — SSH-Key wurde erzeugt, aber nie bei GitHub hinterlegt.

Jetzt: Login per Browser (Schritt 4), `gh auth setup-git` verbindet das automatisch mit `git`.

---

## Wenn etwas abbricht

Einfach denselben Befehl noch einmal ausfuehren. Ueberspringt automatisch Erledigtes.

---

## Danach: erste Aenderung machen

```sh
cd ~/projects/hello-world-apk
gcp "meine erste Aenderung"
```
