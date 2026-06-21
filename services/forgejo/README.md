# services/forgejo

Skripte zur vollstaendigen Einrichtung von Forgejo hinter
**pfSense/HAProxy** mit TLS-Terminierung am Proxy und
Zugriffsbeschraenkung auf einen dedizierten Subdomain.

Forgejo ist ein community-gesteuerter Free-Software-Fork von Gitea.

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
 Forgejo-Host :3000
   Forgejo lauscht nur auf 127.0.0.1:3000 (oder interne IP)
   DISABLE_REGISTRATION = true
   COOKIE_SECURE = true
   REVERSE_PROXY_TRUSTED_PROXIES = 127.0.0.1/32,::1/128
```

## Warum TLS am HAProxy (pfSense) terminieren?

- **Zentrale Zertifikatsverwaltung:** Let's Encrypt oder interne CA
  werden einmalig in pfSense konfiguriert und fuer alle Dienste genutzt.
- **Hostname-Routing:** Mehrere Dienste koennen denselben Port 443 teilen
  (z.B. `forgejo.own.dedyn.io`, `ci.own.dedyn.io`, ...).
- **Firewall-Kontrolle:** Zugriff auf Port 3000 kann per pfSense-Regel
  auf die HAProxy-IP beschraenkt werden. Kein direkter Zugriff von aussen.
- **Forgejo-Empfehlung:** Die offizielle Forgejo-Dokumentation empfiehlt
  dieses Modell explizit fuer den Produktiveinsatz.

## Ausfuehrungs-Reihenfolge

| Schritt | Skript | Als | Was passiert |
|---|---|---|---|
| 1 | `01-create-os-user.sh` | root | Linux-Systemuser `forgejo` + Verzeichnisse |
| 2 | `02-configure-haproxy.sh <domain> <ip>` | root | `app.ini` schreiben (mit Hardening) + HAProxy-Referenz ausgeben |
| 3 | pfSense HAProxy | GUI | Frontend/Backend gemaess Ausgabe von Schritt 2 einrichten |
| 4 | pfSense Firewall | GUI | Port 3000 nur fuer HAProxy-IP freigeben |
| 5 | DNS | GUI/CLI | A-Record fuer Subdomain auf HAProxy-IP |
| 6 | `03-create-forgejo-users.sh` | root/forgejo | Admin + Projekt-User anlegen (KeePass-integriert) |
| 7 | `04-create-repo.sh` | root/forgejo | privates Repo fuer Projekt-User anlegen |

Fuer eine All-in-One-Installation (ohne die Step-Skripte) steht `bootstrap.sh`
zur Verfuegung – allerdings ohne HAProxy-Hardening und ohne KeePass-Integration.

## Variablen

Alle Skripte unterstuetzen Umgebungsvariablen:

```bash
export FORGEJO_BIN=/usr/local/bin/forgejo
export FORGEJO_CFG=/etc/forgejo/app.ini
export FORGEJO_SYS_USER=forgejo
# Fuer 03-create-forgejo-users.sh:
export SB_BACKEND=keepassxc   # keepassxc | plain
export CREATE_PROJ_USER=1      # 1=anlegen, 0=ueberspringen
export PROJ_USER=forge-bot     # Projektuser-Name
```

## Credential-Backend (KeePass)

`03-create-forgejo-users.sh` laedt `lib/secret-backends.sh` automatisch.

- Passwort in KeePass vorhanden → wird direkt verwendet (kein Prompt)
- Passwort nicht vorhanden → interaktiv abgefragt, danach in KeePass gespeichert
- Schluessel-Pfade: `forgejo/admin_pass`, `forgejo/proj_<user>_pass`

Details: `CREDENTIAL-BACKENDS.md` im Repo-Root.

## Sicherheitshinweise

- Passwoerter werden niemals in Skriptdateien gespeichert.
- `DISABLE_REGISTRATION = true` in `app.ini` verhindert Selbstregistrierung.
- Port 3000 sollte per Firewall auf den HAProxy beschraenkt werden.
- `COOKIE_SECURE = true` und `REVERSE_PROXY_TRUSTED_PROXIES` sind gesetzt.
- `PASSWORD_HASH_ALGO = argon2` (staerker als Standard pbkdf2).
- Fuer Passwort-Verwaltung: `lib/secret-backends.sh` (KeePassXC, GPG, plain).

## Unterschiede zu services/gitea

| Aspekt | Gitea | Forgejo |
|---|---|---|
| Binary-Pfad | `/opt/gitea/gitea` | `/usr/local/bin/forgejo` |
| Konfig-Verzeichnis | `/etc/gitea/` | `/etc/forgejo/` |
| Work-Verzeichnis | `/var/lib/gitea/` | `/var/lib/forgejo/` |
| KeePass-Integration | nur 03 (read) | 03 mit sb_write (lazy-init) |
| `PASSWORD_HASH_ALGO` | pbkdf2 (Standard) | argon2 |
| Reverse-Proxy | HAProxy (pfSense) | HAProxy (pfSense) |
