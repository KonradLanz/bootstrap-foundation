#!/bin/sh
# lib/bw-session.sh
#
# Zentrale BW_SESSION-Verwaltung fuer Vaultwarden/Bitwarden CLI.
#
# Nutzung (Shell):
#   . "$KL_BOOTSTRAP_ROOT/lib/bw-session.sh"
#   kl_bw_ensure_session        # setzt/erneuert BW_SESSION wenn moeglich
#   val=$(kl_bw_get "nas/ssh_pass")
#   kl_bw_set "nas/ssh_pass" "geheim"
#
# Nutzung (Python - via subprocess oder os.environ nach Shell-Aufruf):
#   import subprocess, os
#   subprocess.run(['bash', '-c',
#     '. $KL_BOOTSTRAP_ROOT/lib/bw-session.sh && kl_bw_ensure_session'],
#     env={**os.environ})
#   # BW_SESSION ist danach in os.environ gesetzt
#
# Umgebungsvariablen:
#   BW_SESSION      Aktiver Session-Token (wird gesetzt/exportiert)
#   BW_CLIENTID     fuer bw login --apikey (optional)
#   BW_CLIENTSECRET fuer bw login --apikey (optional)
#   KL_BW_SERVER    Vaultwarden-Server-URL (default: Bitwarden Cloud)
#                   z.B. https://vault.example.com
#
# Verhalten:
#   - bw nicht installiert  -> still zurueck (kein Fehler, kein Abbruch)
#   - Session aktiv+unlocked -> sofort zurueck (kein Prompt)
#   - Session abgelaufen    -> bw unlock (fragt Master-Passwort, read -s)
#   - Nicht eingeloggt      -> bw login + unlock
#   - Interaktiv=nein       -> still zurueck (nie blockieren in Scripts)
#
# Item-Name-Konvention in Vaultwarden:
#   Alle kl-Cache-Keys werden als "kl: <key>" gespeichert.
#   Beispiel: "nas/ssh_pass" -> Vaultwarden-Item "kl: nas/ssh_pass"
#   Dasselbe Muster wie email-analyser ("email-analyser - IMAP").
#
# WICHTIG: Niemals BW_SESSION in eine Datei schreiben.
#          Nur als Shell-Variable/Env-Var fuer die Prozess-Lebensdauer.

# ---------------------------------------------------------------------------
# Interne Hilfsfunktionen
# ---------------------------------------------------------------------------

_kl_bw_available() {
    command -v bw >/dev/null 2>&1
}

_kl_bw_status() {
    # Gibt bw-Status-String zurueck: "unlocked", "locked", "unauthenticated"
    bw status 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unknown'))" \
        2>/dev/null || printf 'unknown'
}

_kl_bw_configure_server() {
    [ -z "${KL_BW_SERVER:-}" ] && return 0
    _current=$(bw config server 2>/dev/null | tr -d '[:space:]' || true)
    if [ "$_current" != "$KL_BW_SERVER" ]; then
        bw config server "$KL_BW_SERVER" >/dev/null 2>&1 || true
    fi
}

# ---------------------------------------------------------------------------
# kl_bw_ensure_session
#
# Prueft Session-Status und entsperrt/loggt ein wenn noetig.
# Exportiert BW_SESSION fuer den aktuellen Prozess.
# Gibt 0 zurueck wenn Session aktiv, 1 wenn nicht moeglich.
# ---------------------------------------------------------------------------
kl_bw_ensure_session() {
    _kl_bw_available || return 0  # bw nicht da -> kein Fehler

    # Interaktivitaet pruefen: im unassisted-Modus nie blockieren
    if [ "${KL_RUN_MODE:-auto}" = "unassisted" ] || [ ! -t 0 ]; then
        # Nur pruefen ob Session bereits aktiv, nie promten
        if [ -n "${BW_SESSION:-}" ]; then
            _kl_bw_configure_server
            _status=$(_kl_bw_status)
            [ "$_status" = "unlocked" ] && return 0
        fi
        return 1
    fi

    _kl_bw_configure_server
    _status=$(_kl_bw_status)

    case "$_status" in
        unlocked)
            # Session-Token aus Env bereits gueltig
            [ -n "${BW_SESSION:-}" ] && return 0
            # Token fehlt trotz unlocked-Status (z.B. nach bw unlock in Sub-Shell)
            # -> neu entsperren
            ;;
        locked)
            # Eingeloggt aber gesperrt -> nur unlock noetig
            printf '\n🔐 Vaultwarden entsperren (Master-Passwort):\n' >&2
            BW_SESSION=$(bw unlock --raw 2>/dev/null) || {
                printf '⚠️  bw unlock fehlgeschlagen. Weiter ohne Vault.\n' >&2
                return 1
            }
            export BW_SESSION
            return 0
            ;;
        unauthenticated)
            # Noch nie eingeloggt oder ausgeloggt
            printf '\n🔑 Vaultwarden Login erforderlich:\n' >&2
            if [ -n "${BW_CLIENTID:-}" ] && [ -n "${BW_CLIENTSECRET:-}" ]; then
                # API-Key Login (non-interaktiv moeglich)
                bw login --apikey >/dev/null 2>&1 || {
                    printf '⚠️  bw login --apikey fehlgeschlagen.\n' >&2
                    return 1
                }
            else
                # Interaktiver Login
                bw login >/dev/null 2>&1 || {
                    printf '⚠️  bw login fehlgeschlagen. Weiter ohne Vault.\n' >&2
                    return 1
                }
            fi
            BW_SESSION=$(bw unlock --raw 2>/dev/null) || return 1
            export BW_SESSION
            return 0
            ;;
        *)
            printf '⚠️  bw Status unbekannt (%s). Weiter ohne Vault.\n' "$_status" >&2
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# kl_bw_item_name KEY
# Gibt den Vaultwarden-Item-Namen fuer einen kl-Cache-Key zurueck.
# Konvention: "kl: <key>"  (konsistent mit email-analyser-Pattern)
# ---------------------------------------------------------------------------
kl_bw_item_name() {
    printf 'kl: %s' "$1"
}

# ---------------------------------------------------------------------------
# kl_bw_get KEY
# Liest Wert aus Vaultwarden. Gibt leeren String zurueck wenn nicht gefunden.
# ---------------------------------------------------------------------------
kl_bw_get() {
    [ -n "${BW_SESSION:-}" ] || return 0
    _kl_bw_available || return 0
    _item=$(kl_bw_item_name "$1")
    bw get password "$_item" --session "$BW_SESSION" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# kl_bw_set KEY VALUE [USERNAME]
# Erstellt oder aktualisiert ein Vaultwarden-Item.
# USERNAME default: kl-cache
# ---------------------------------------------------------------------------
kl_bw_set() {
    [ -n "${BW_SESSION:-}" ] || return 0
    _kl_bw_available || return 0
    _key="$1" _value="$2" _username="${3:-kl-cache}"
    _item=$(kl_bw_item_name "$_key")

    # Existiert bereits?
    _existing_id=$(bw get item "$_item" --session "$BW_SESSION" 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || true)

    if [ -n "$_existing_id" ]; then
        # Update: bestehendes Item mit neuem Passwort
        # xargs -I{} schlaegt auf macOS mit mehrzeiligem JSON fehl (Newlines).
        # Stattdessen: encoded JSON in Variable, dann direkt uebergeben.
        _updated_encoded=$(bw get item "$_item" --session "$BW_SESSION" 2>/dev/null \
            | python3 -c "
import sys, json
item = json.load(sys.stdin)
item['login']['password'] = sys.argv[1]
item['login']['username'] = sys.argv[2]
print(json.dumps(item))
" "$_value" "$_username" \
            | bw encode 2>/dev/null)
        bw edit item "$_existing_id" "$_updated_encoded" --session "$BW_SESSION" >/dev/null 2>&1 \
            || { printf '⚠️  bw edit fehlgeschlagen fuer: %s\n' "$_item" >&2; return 1; }
    else
        # Neu erstellen
        # WICHTIG: "$(...)" als Argument, nicht Pipe -- stdin muss frei bleiben
        # (vgl. email-analyser/docs/bitwarden-imap-secret.md ERR_USE_AFTER_CLOSE)
        _encoded=$(bw get template item --session "$BW_SESSION" 2>/dev/null \
            | python3 -c "
import sys, json
t = json.load(sys.stdin)
t['type'] = 1
t['name'] = sys.argv[1]
t['login'] = {'password': sys.argv[2], 'username': sys.argv[3]}
print(json.dumps(t))
" "$_item" "$_value" "$_username" \
            | bw encode 2>/dev/null)
        bw create item "$_encoded" --session "$BW_SESSION" >/dev/null 2>&1 \
            || { printf '⚠️  bw create fehlgeschlagen fuer: %s\n' "$_item" >&2; return 1; }
    fi
    printf '✅ Vaultwarden: %s gespeichert\n' "$_item" >&2
}

# ---------------------------------------------------------------------------
# kl_bw_delete KEY
# Loescht ein Vaultwarden-Item (soft delete - Papierkorb).
# ---------------------------------------------------------------------------
kl_bw_delete() {
    [ -n "${BW_SESSION:-}" ] || return 0
    _kl_bw_available || return 0
    _item=$(kl_bw_item_name "$1")
    _id=$(bw get item "$_item" --session "$BW_SESSION" 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || true)
    [ -n "$_id" ] \
        && bw delete item "$_id" --session "$BW_SESSION" >/dev/null 2>&1 \
        && printf '🗑️  Vaultwarden: %s geloescht\n' "$_item" >&2 \
        || true
}

# ---------------------------------------------------------------------------
# kl_bw_suggest_store KEY VALUE
# Fragt interaktiv ob Wert in Vaultwarden gespeichert werden soll.
# Wird von kl_read_cached aufgerufen nach erstmaliger Eingabe.
# ---------------------------------------------------------------------------
kl_bw_suggest_store() {
    _kl_bw_available || return 0
    [ -t 1 ] || return 0  # Nur interaktiv
    _status=$(_kl_bw_status)
    [ "$_status" = "unlocked" ] || return 0

    printf '\n💡 In Vaultwarden speichern? (%s) [J/n] ' "$(kl_bw_item_name "$1")" >&2
    read -r _answer || _answer='n'
    case "${_answer:-J}" in
        j|J|y|Y|'')
            kl_bw_set "$1" "$2"
            ;;
    esac
}
