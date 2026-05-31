# services/gitea

Skripte zur vollstaendigen Einrichtung von Gitea hinter
**pfSense/HAProxy** mit TLS-Terminierung am Proxy und
Zugriffsbeschraenkung auf einen dedizierten Subdomain.

## Architektur

```
Internet / LAN
      |
      v
 pfSense / HAProxy
   HTTPS :443  (TLS-Terminierung hier)
   Let's Encrypt Zertifikat oder internes CA-Zertifikat
      |
      | http  (nur intern, nur von HAProxy-IP)
      v
 Gitea-Host :3000
   Gitea lauscht nur auf 127.0.0.1:3000 (oder interne IP)
   DISABLE_REGISTRATION = true
```

## Warum TLS am HAProxy (pfSense) terminieren?

- **Zentrale Zertifikatsverwaltung:** Let's Encrypt oder interne CA
  werden einmalig in pfSense konfiguriert und fuer alle Dienste genutzt.
- **Hostname-Routing:** Mehrere Dienste koennen denselben Port 443 teilen
  (z.B. `git.example.lan`, `ci.example.lan`, `www.example.lan`).
- **Firewall-Kontrolle:** Zugriff auf Port 3000 kann per pfSense-Regel
  auf die HAProxy-IP beschraenkt werden. Kein direkter Zugriff von aussen.
- **Gitea-Empfehlung:** Die offizielle Gitea-Dokumentation empfiehlt dieses
  Modell explizit fuer den Produktiveinsatz.

## Subdomain

Empfohlen ist eine eigene Subdomain (z.B. `git.example.lan`) statt eines
Subpfades (`example.lan/gitea/`), weil Subpfade in der Gitea-Doku als
fehleranfaelliger beschrieben werden.

`ROOT_URL = https://git.example.lan/` muss exakt dieser Subdomain entsprechen.

## Ausfuehrungs-Reihenfolge

| Schritt | Skript | Als | Was passiert |
|---|---|---|---|
| 1 | `01-create-os-user.sh` | root | Linux-Systemuser `gitea` + Verzeichnisse |
| 2 | `02-configure-haproxy.sh <domain> <ip>` | root | `app.ini` schreiben + HAProxy-Referenzkonfiguration ausgeben |
| 3 | pfSense HAProxy | GUI | Frontend/Backend gemaess Ausgabe von Schritt 2 einrichten |
| 4 | pfSense Firewall | GUI | Port 3000 nur fuer HAProxy-IP freigeben |
| 5 | DNS | GUI/CLI | A-Record fuer Subdomain auf HAProxy-IP |
| 6 | `03-create-gitea-users.sh` | root/gitea | Admin + Projekt-User anlegen |
| 7 | `04-create-repo.sh` | root/gitea | privates Repo fuer Projekt-User anlegen |

## Variablen

Alle Skripte unterstuetzen Umgebungsvariablen:

```bash
export GITEA_BIN=/opt/gitea/gitea
export GITEA_CFG=/etc/gitea/app.ini
export GITEA_SYS_USER=gitea
```

## Sicherheitshinweise

- Passwoerter werden niemals in Skriptdateien gespeichert (nur interaktiv abgefragt).
- `DISABLE_REGISTRATION = true` in `app.ini` verhindert Selbstregistrierung.
- Port 3000 sollte per Firewall auf den HAProxy beschraenkt werden.
- `COOKIE_SECURE = true` und `REVERSE_PROXY_TRUSTED_PROXIES` sind gesetzt.
- Fuer Passwort-Verwaltung: `lib/secret-backends.sh` (KeePassXC, GPG, plain).
  Siehe `CREDENTIAL-BACKENDS.md`.
