#!/usr/bin/env bash
set -euo pipefail

TARGET="${TARGET:-migration.sh}"                  # override: TARGET=foo.sh sudo bash hunt_migration.sh
SINCE="${SINCE:-60d}"                             # how far back to search logs
REPORT="${REPORT:-$HOME/Desktop/migration_hunt_$(date +%Y%m%d_%H%M%S).txt}"

bold(){ printf "\033[1m%s\033[0m\n" "$*"; }
log(){ printf "[HUNT] %s\n" "$*" | tee -a "$REPORT"; }
sep(){ printf -- "------------------------------------------------------------\n" | tee -a "$REPORT"; }

require_root(){
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Please run with sudo." ; exit 1
  fi
}

main(){
  require_root
  : > "$REPORT"
  bold "macOS Hunt for: $TARGET"
  echo "Report: $REPORT"
  sep

  find_exact_files
  find_references_text
  find_in_launchd
  find_in_temp
  find_recent_mods
  find_spotlight
  find_unified_logs
  find_quarantine_db
  find_shell_history

  sep
  bold "Done. Review report: $REPORT"
}

find_exact_files(){
  bold "1) Exact filename on disk (this can take time)…" | tee -a "$REPORT"
  # Fast paths first, then full disk
  paths=(
    "/Users" "/private/tmp" "/tmp" "/var/tmp"
    "/var/folders" "/opt" "/usr/local" "/Applications"
    "/Library" "/System/Volumes/Data"
    "/"
  )
  for p in "${paths[@]}"; do
    log "Searching: $p"
    TIMEFORMAT=$'  -> completed in %3lR'
    { time find "$p" -xdev -type f -name "$TARGET" -print 2>/dev/null | tee -a "$REPORT" ; } || true
  done
  sep
}

find_references_text(){
  bold "2) References to the filename in likely config/script locations…" | tee -a "$REPORT"
  toscan=(
    "$HOME/Library/LaunchAgents"
    "/Library/LaunchAgents"
    "/Library/LaunchDaemons"
    "/etc"
    "/usr/local"
    "/opt"
    "/Library/Preferences"
  )
  for d in "${toscan[@]}"; do
    [ -d "$d" ] || continue
    log "Grep in: $d"
    grep -R --include='*.plist' --include='*.sh' --include='*.conf' --text -n "$TARGET" "$d" 2>/dev/null | tee -a "$REPORT" || true
  done
  sep
}

find_in_launchd(){
  bold "3) LaunchAgents/Daemons that might call it…" | tee -a "$REPORT"
  for d in "$HOME/Library/LaunchAgents" "/Library/LaunchAgents" "/Library/LaunchDaemons"; do
    [ -d "$d" ] || continue
    for f in "$d"/*.plist; do
      [ -f "$f" ] || continue
      if /usr/libexec/PlistBuddy -c "Print :ProgramArguments" "$f" 2>/dev/null | grep -q "$TARGET"; then
        log "MATCH in launchd: $f"
        # Suggest bootout command
        if [[ "$d" == "$HOME/Library/LaunchAgents" ]]; then
          echo "  -> Disable now: launchctl bootout gui/$(id -u) '$f'" | tee -a "$REPORT"
        elif [[ "$d" == "/Library/LaunchAgents" ]]; then
          echo "  -> Disable now: launchctl bootout gui/$(id -u) '$f'" | tee -a "$REPORT"
        else
          echo "  -> Disable now: sudo launchctl bootout system '$f'" | tee -a "$REPORT"
        fi
        echo "  -> Inspect: /usr/libexec/PlistBuddy -c 'Print' '$f'" | tee -a "$REPORT"
      fi
    done
  done
  sep
}

find_in_temp(){
  bold "4) Common temp stash locations…" | tee -a "$REPORT"
  for d in "/private/tmp" "/tmp" "/var/tmp" "/var/folders"; do
    [ -d "$d" ] || continue
    log "Searching: $d"
    find "$d" -type f -name "$TARGET" -print 2>/dev/null | tee -a "$REPORT" || true
  done
  sep
}

find_recent_mods(){
  bold "5) Recently changed files that include the name (last 3 days)…" | tee -a "$REPORT"
  find / -xdev -type f -mtime -3 -iname "*migration*" 2>/dev/null | tee -a "$REPORT" || true
  sep
}

find_spotlight(){
  bold "6) Spotlight (metadata) search…" | tee -a "$REPORT"
  if command -v mdfind >/dev/null; then
    mdfind "kMDItemFSName == '$TARGET'c" 2>/dev/null | tee -a "$REPORT" || true
  else
    log "mdfind not available."
  fi
  sep
}

find_unified_logs(){
  bold "7) Unified logs (last ${SINCE})…" | tee -a "$REPORT"
  # By message text or process image path
  log "Querying: eventMessage contains \"$TARGET\""
  log show --predicate "eventMessage CONTAINS[c] \"$TARGET\"" --last "$SINCE" --info --debug --style syslog 2>/dev/null | tee -a "$REPORT" || true
  sep
}

find_quarantine_db(){
  bold "8) Quarantine (download) database hits…" | tee -a "$REPORT"
  local qdb="$HOME/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2"
  if [ -f "$qdb" ]; then
    log "Inspecting $qdb"
    sqlite3 "$qdb" "SELECT datetime(LSQuarantineTimeStamp + 978307200,'unixepoch','localtime') AS ts,
                           LSQuarantineOriginURLString, LSQuarantineDataURLString, LSQuarantineAgentName
                    FROM LSQuarantineEvent
                    WHERE (LSQuarantineDataURLString LIKE '%$TARGET%' OR LSQuarantineOriginURLString LIKE '%$TARGET%' OR LSQuarantineAgentName LIKE '%$TARGET%')
                    ORDER BY ts DESC;" | tee -a "$REPORT" || true
  else
    log "No quarantine DB found for user: $qdb"
  fi
  sep
}

find_shell_history(){
  bold "9) Shell history mentions…" | tee -a "$REPORT"
  for h in "$HOME/.zsh_history" "$HOME/.bash_history"; do
    [ -f "$h" ] || continue
    log "Searching $h"
    grep -n "$TARGET" "$h" | tee -a "$REPORT" || true
  done
  sep
}

main "$@"
